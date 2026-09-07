import Foundation

/// Reads a webpage's Open Graph title/description — the same tags a
/// chat app's link-preview card reads — so a share that's only a URL
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
enum OpenGraphFetcher {
    struct Info {
        var title: String?
        var description: String?
    }

    static func fetch(url: URL) async -> Info {
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
