import Foundation
import LinkPresentation

/// Reads a shared URL's title — the same "what is this link" a chat
/// app's link-preview card answers — so a share that's only a URL
/// (Google Maps' and Kakao Map's own "Share" action give no separate
/// name/address text, unlike Naver Map's, which shares the place name
/// and address as plain text alongside its link) still yields a
/// readable place name to geocode.
///
/// Only viable from the main app, not the web app: a browser's fetch()
/// is blocked by CORS for a cross-origin read like this (see the
/// equivalent note in lib/sharedPlaceImport.ts), but neither
/// LPMetadataProvider nor URLSession are subject to that — it's a
/// browser-specific restriction, not a server-side block — so this
/// works here with no extra infrastructure. Deliberately not run from
/// ShareExtension itself: keeps the extension fast/lightweight (Apple's
/// own guidance for share extensions), and the main app already shows a
/// loading state while Add Places opens.
enum OpenGraphFetcher {
    struct Info {
        var title: String?
        var description: String?
    }

    /// Tries three strategies in order, each one a fallback for a way
    /// the previous one can come back empty for a Google Maps link
    /// specifically (the reported, reproducing case — Naver/Kakao's
    /// plain server-rendered pages already work with the HTML scrape
    /// alone):
    ///
    /// 1. Read the place name straight out of the URL Google's own
    ///    short link (`maps.app.goo.gl/...`) redirects to — Google
    ///    Maps' real place URL is shaped like
    ///    `.../maps/place/<url-encoded name>/@lat,lng,...`, so the name
    ///    is sitting right there in the path once the redirect (a plain
    ///    HTTP 30x, no JavaScript involved) resolves, with no page
    ///    content needing to load at all. See placeName(fromMapsPath:).
    /// 2. LinkPresentation — the same framework Messages/Mail use to
    ///    render a rich preview for a pasted link. It follows redirects
    ///    and can read a destination's richer metadata beyond a single
    ///    page fetch's raw HTML, which covers non-Maps links this
    ///    module also has to handle.
    /// 3. A plain HTML `<meta>` scrape, for whatever's left — a static,
    ///    server-rendered page neither of the above needed any special
    ///    handling for.
    ///
    /// Google Maps' own place page is a JS-rendered app shell with no
    /// place name in its initial HTML response, which is why relying on
    /// strategy 3 alone (the original version of this function) always
    /// fell through to "Unknown" for Google Maps links — and why
    /// strategy 1 is tried first rather than left as a last resort: it's
    /// the one that doesn't depend on the destination page's own content
    /// at all.
    static func fetch(url: URL) async -> Info {
        if let title = await resolveGoogleMapsPlaceName(from: url) {
            return Info(title: title, description: nil)
        }
        if let title = await fetchTitleViaLinkPresentation(url: url) {
            return Info(title: title, description: nil)
        }
        return await fetchViaHTMLMetaTags(url: url)
    }

    private static func resolveGoogleMapsPlaceName(from url: URL) async -> String? {
        guard let host = url.host?.lowercased(), host.contains("google.com") || host.contains("goo.gl") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard
            let (_, response) = try? await URLSession.shared.data(for: request),
            let finalURL = response.url
        else { return nil }
        return placeName(fromMapsPath: finalURL.path)
    }

    /// Pulls the name out of a Google Maps place URL's own path —
    /// `/maps/place/<url-encoded name>/@37.5,127.0,17z/...` — decoding
    /// `+`-for-space the way a URL query/path component encodes it,
    /// same as `URLComponents` would for a query item, since
    /// `removingPercentEncoding` alone only undoes %XX escapes.
    private static func placeName(fromMapsPath path: String) -> String? {
        guard let nameRange = path.range(of: #"(?<=/maps/place/)[^/@]+"#, options: .regularExpression) else {
            return nil
        }
        let encoded = String(path[nameRange]).replacingOccurrences(of: "+", with: " ")
        guard let decoded = encoded.removingPercentEncoding?.trimmingCharacters(in: .whitespaces), !decoded.isEmpty else {
            return nil
        }
        return decoded
    }

    private static func fetchTitleViaLinkPresentation(url: URL) async -> String? {
        let provider = LPMetadataProvider()
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return nil }
        let title = metadata.title?.trimmingCharacters(in: .whitespaces)
        return (title?.isEmpty ?? true) ? nil : title
    }

    private static func fetchViaHTMLMetaTags(url: URL) async -> Info {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (compatible; Peragra/1.0)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return Info() }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return Info()
        }

        let metaTags = extractMetaTags(from: html)
        return Info(
            title: metaTags["og:title"] ?? metaTags["twitter:title"],
            description: metaTags["og:description"] ?? metaTags["twitter:description"] ?? metaTags["description"]
        )
    }

    /// Fills in a shared candidate's name when it arrived with none —
    /// Google Maps' and Kakao Map's own "Share" give only a link, unlike
    /// Naver Map's, which already includes the name (and address) as
    /// plain text alongside its link, needing no fetch at all. Tries
    /// this page's own Open Graph title before falling back to the same
    /// "Unknown" placeholder the on-site photo flow uses when it can't
    /// tell a place's name either — so the row is still reviewable and
    /// savable rather than stuck with a blank, unsavable name. Doesn't
    /// touch `address`: og:description mixes in ratings/category text
    /// alongside a place's actual address, which isn't reliable enough
    /// to feed into geocoding as address text.
    static func resolvingName(for candidate: SharedPlaceImport) async -> SharedPlaceImport {
        var resolved = candidate
        guard resolved.name.trimmingCharacters(in: .whitespaces).isEmpty else { return resolved }

        if let url = URL(string: resolved.link), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            let info = await fetch(url: url)
            if let title = info.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
                resolved.name = title
                return resolved
            }
        }

        resolved.name = "Unknown"
        return resolved
    }

    /// Maps each `<meta>` tag's `property`/`name` attribute to its
    /// `content` — a single regex pass over every meta tag, rather than
    /// one search per property name, since pages vary in attribute
    /// order (content before property, or after).
    private static func extractMetaTags(from html: String) -> [String: String] {
        guard let tagRegex = try? NSRegularExpression(pattern: "<meta\\s+[^>]*>", options: [.caseInsensitive]) else {
            return [:]
        }
        let fullRange = NSRange(html.startIndex..., in: html)

        var result: [String: String] = [:]
        for match in tagRegex.matches(in: html, range: fullRange) {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            guard let key = attributeValue(in: tag, name: "property") ?? attributeValue(in: tag, name: "name"),
                  let content = attributeValue(in: tag, name: "content") else { continue }
            if result[key] == nil {
                result[key] = decodeHTMLEntities(content)
            }
        }
        return result
    }

    private static func attributeValue(in tag: String, name: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\(name)\\s*=\\s*\"([^\"]*)\"", options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = regex.firstMatch(in: tag, range: range), let valueRange = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[valueRange])
    }

    /// A small, self-contained decoder for the handful of entities that
    /// actually show up in OG tag content — deliberately not
    /// NSAttributedString's HTML-import path (which parses via WebKit),
    /// to avoid that weight/uncertainty inside a process this simple.
    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let namedEntities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&nbsp;": " ",
        ]
        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        guard let regex = try? NSRegularExpression(pattern: "&#x?([0-9A-Fa-f]+);", options: [.caseInsensitive]) else {
            return result
        }
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let codeRange = Range(match.range(at: 1), in: result) else { continue }
            let isHex = result[fullRange].lowercased().contains("x")
            let codeString = String(result[codeRange])
            guard let scalarValue = isHex ? UInt32(codeString, radix: 16) : UInt32(codeString),
                  let scalar = Unicode.Scalar(scalarValue) else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }
}
