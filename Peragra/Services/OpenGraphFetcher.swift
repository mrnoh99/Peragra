import Foundation

/// Reads a shared URL's title — the same "what is this link" a chat
/// app's link-preview card answers — so a share that's only a URL
/// (Google Maps' and Kakao Map's own "Share" action give no separate
/// name/address text, unlike Naver Map's, which shares the place name
/// and address as plain text alongside its link) still yields a
/// readable place name to geocode.
///
/// Only viable from the main app, not the web app: a browser's fetch()
/// is blocked by CORS for a cross-origin read like this (see the
/// equivalent note in lib/sharedPlaceImport.ts), but URLSession isn't
/// subject to that — it's a browser-specific restriction, not a
/// server-side block — so this works here with no extra infrastructure.
/// Deliberately not run from ShareExtension itself: keeps the extension
/// fast/lightweight (Apple's own guidance for share extensions), and
/// the main app already shows a loading state while Add Places opens.
///
/// Deliberately plain URLSession only — an earlier version of this
/// tried LinkPresentation's LPMetadataProvider (the framework
/// Messages/Mail use for rich link previews) first, on the theory that
/// it could follow a JS-driven redirect a plain HTTP client can't. On a
/// real device, that consistently failed instead: LPMetadataProvider
/// spins up its own WebContent/GPU helper processes, and those failed
/// to acquire the RunningBoard assertion they need right after the
/// extension-to-main-app handoff — "target is not running or doesn't
/// have entitlement com.apple.developer.web-browser-engine.*" in the
/// device console, every fetch ending cancelled (-999). Whatever the
/// exact cause, it's a real, reproducing failure in this exact
/// launch path, not a fluke worth retrying — so this sticks to
/// URLSession, which doesn't depend on any of that.
enum OpenGraphFetcher {
    struct Info {
        var title: String?
        var description: String?
    }

    private static let mobileSafariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    /// Two strategies, in order:
    ///
    /// 1. Read the place name straight out of a Google Maps URL —
    ///    `.../maps/place/<url-encoded name>/@lat,lng,...` — whether
    ///    that's the URL this function was handed directly, the one a
    ///    short link (`maps.app.goo.gl/...`) redirects to at the plain
    ///    HTTP level, or one just sitting as text inside that short
    ///    link's own landing page. That page is server-rendered
    ///    specifically so it works as a social/link-preview card when
    ///    shared — even when actually visiting it takes a JS-driven
    ///    redirect a plain HTTP client won't follow, the real place URL
    ///    it's about to navigate to is typically still sitting in its
    ///    HTML/JS as plain text, findable without executing anything.
    /// 2. A plain HTML `<meta>` scrape, for whatever's left — covers
    ///    Kakao Map's and any other static, server-rendered page that
    ///    never needed special handling to begin with.
    ///
    /// Google Maps' own place page (once actually navigated to in a
    /// browser) is a JS-rendered app shell with no place name in its
    /// initial HTML response, which is why relying on strategy 2 alone
    /// (the original version of this function) always fell through to
    /// "Unknown" for Google Maps links specifically.
    static func fetch(url: URL) async -> Info {
        guard let (data, response) = try? await URLSession.shared.data(for: request(for: url)) else {
            return Info()
        }

        if let finalURL = response.url, let name = placeName(fromMapsText: finalURL.absoluteString) {
            return Info(title: name, description: nil)
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return Info()
        }
        if let name = placeName(fromMapsText: html) {
            return Info(title: name, description: nil)
        }

        let metaTags = extractMetaTags(from: html)
        return Info(
            title: metaTags["og:title"] ?? metaTags["twitter:title"],
            description: metaTags["og:description"] ?? metaTags["twitter:description"] ?? metaTags["description"]
        )
    }

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(mobileSafariUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Finds the first `/maps/place/<url-encoded name>/` occurring
    /// anywhere in the given text — a full page's HTML/JS source, or
    /// just a URL's own path — and decodes the name out of it. Un-escapes
    /// `\/` to `/` first, since a URL embedded in inline JSON (a common
    /// way a page hands its own JS the data it was server-rendered
    /// with) backslash-escapes every forward slash. Decodes `+`-for-space
    /// the way a URL query/path component encodes it, same as
    /// `URLComponents` would for a query item, since
    /// `removingPercentEncoding` alone only undoes %XX escapes.
    private static func placeName(fromMapsText text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\\/", with: "/")
        guard let nameRange = normalized.range(of: #"(?<=/maps/place/)[^/@"'\\]+"#, options: .regularExpression) else {
            return nil
        }
        let encoded = String(normalized[nameRange]).replacingOccurrences(of: "+", with: " ")
        guard let decoded = encoded.removingPercentEncoding?.trimmingCharacters(in: .whitespaces), !decoded.isEmpty else {
            return nil
        }
        return decoded
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
