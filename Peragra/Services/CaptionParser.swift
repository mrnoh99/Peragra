import Foundation

/// Best-effort extraction of a place name and address from Instagram
/// caption text the user provides (pasted, or OCR'd from a screenshot).
/// Instagram doesn't expose caption text via any client-accessible API, so
/// this only ever sees text the person brings over themselves — always
/// treat the result as a starting point the person can edit, not a
/// guaranteed-correct parse. Mirrors web/src/lib/captionParser.ts.
enum CaptionParser {
    struct Result {
        let name: String?
        let address: String?
    }

    // Labels people commonly use in Korean/English caption text to call out
    // a place's name or address explicitly.
    private static let nameLabel = try! NSRegularExpression(
        pattern: #"^(?:상호명?|가게\s*이름|매장명|카페명|식당명|이름|name)\s*[:：]\s*(.+)$"#,
        options: [.caseInsensitive]
    )
    private static let addressLabel = try! NSRegularExpression(
        pattern: #"^(?:주소|위치|location|address)\s*[:：]\s*(.+)$"#,
        options: [.caseInsensitive]
    )

    // Korean road-name/land-lot address: e.g. "서울 강남구 테헤란로 123",
    // "경기도 성남시 분당구 판교역로 235-1", or "마포구 새창로2길 20" (road
    // name followed by a numbered sub-"길", then the building number).
    private static let koreanAddress = try! NSRegularExpression(
        pattern: #"[가-힣]+(?:시|군|구)\s?[가-힣0-9]+(?:읍|면|동|로|길)(?:\s?[0-9]+길)?\s?[0-9]+(?:-[0-9]+)?"#
    )

    // A generic Western-style street address: a number followed by a
    // street name, optionally with a comma-separated city/state/zip tail.
    private static let westernAddress = try! NSRegularExpression(
        pattern: #"\b\d{1,5}\s+[A-Za-z][A-Za-z0-9.'\s]*\b(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Boulevard|Dr|Drive|Ln|Lane|Way|Pl|Place|Ct|Court)\b\.?,?.*"#,
        options: [.caseInsensitive]
    )

    // Strips leading emoji/bullets/hashtags off a line before treating it
    // as a name/address candidate. The hyphen sits at the very end of the
    // class (away from the full-width space) so it can never be read as a
    // Unicode range with a neighboring char.
    private static let leadingDecoration = try! NSRegularExpression(
        pattern: #"^[\s\p{Extended_Pictographic}\uFE0F*\u00B7\u2022\u30FB#\u3000-]+"#
    )

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func captured(_ text: String, _ match: NSTextCheckingResult, _ index: Int) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static func cleanLine(_ line: String) -> String {
        var result = line
        if let match = firstMatch(leadingDecoration, in: result), let range = Range(match.range, in: result) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func isHashtagLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        let words = trimmed.split(separator: " ").map(String.init)
        let hashtags = words.filter { $0.hasPrefix("#") }
        return !hashtags.isEmpty && Double(hashtags.count) >= Double(words.count) * 0.6
    }

    static func parse(_ caption: String) -> Result {
        let lines = caption
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var name: String?
        var address: String?

        // Pass 1: explicit "label: value" lines anywhere in the caption.
        for line in lines {
            if name == nil, let match = firstMatch(nameLabel, in: line), let value = captured(line, match, 1) {
                name = cleanLine(value)
            }
            if address == nil, let match = firstMatch(addressLabel, in: line), let value = captured(line, match, 1) {
                address = cleanLine(value)
            }
        }

        // Pass 2: address-shaped lines (Korean or Western), when no label found.
        if address == nil {
            addressSearch: for line in lines {
                if let match = firstMatch(koreanAddress, in: line), let value = captured(line, match, 0) {
                    address = cleanLine(value)
                    break addressSearch
                }
                if let match = firstMatch(westernAddress, in: line), let value = captured(line, match, 0) {
                    address = cleanLine(value)
                    break addressSearch
                }
            }
        }

        // Pass 3: name fallback — first non-hashtag, non-address line, so
        // the typical "shop name on line 1, then description/address"
        // caption shape works without any labels at all.
        if name == nil {
            for line in lines {
                if isHashtagLine(line) { continue }
                if let address, line.contains(address) { continue }
                let cleaned = cleanLine(line)
                if !cleaned.isEmpty && cleaned.count <= 60 {
                    name = cleaned
                    break
                }
            }
        }

        return Result(name: name, address: address)
    }
}
