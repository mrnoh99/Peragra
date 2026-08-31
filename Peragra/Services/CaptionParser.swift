import Foundation

/// Best-effort extraction of place name(s) and address(es) from Instagram
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

    // Korean road-name/land-lot address, with an optional leading
    // province/city name so the match captures the whole thing (e.g.
    // "서울 강남구 ...") — matters for splitting "Name - Address" lines,
    // where whatever isn't part of the address match becomes the name.
    // Handles e.g. "서울 강남구 테헤란로 123", "경기도 성남시 분당구
    // 판교역로 235-1", "마포구 새창로2길 20" (road name followed by a
    // numbered sub-"길", then the building number), or just "부산 영도구
    // 청학동" (동-level only, no street number — common for
    // landmarks/trailheads that don't have one). The trailing building
    // number is optional for exactly that reason.
    private static let koreanAddress = try! NSRegularExpression(
        pattern: #"(?:(?:서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)(?:특별시|광역시|특별자치시|도|특별자치도)?\s?)?[가-힣]+(?:시|군|구)\s?[가-힣0-9]+(?:읍|면|동|로|길)(?:\s?[0-9]+길)?(?:\s?[0-9]+(?:-[0-9]+)?)?"#
    )

    // A generic Western-style street address: a number followed by a
    // street name, optionally with a comma-separated city/state/zip tail.
    private static let westernAddress = try! NSRegularExpression(
        pattern: #"\b\d{1,5}\s+[A-Za-z][A-Za-z0-9.'\s]*\b(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Boulevard|Dr|Drive|Ln|Lane|Way|Pl|Place|Ct|Court)\b\.?,?.*"#,
        options: [.caseInsensitive]
    )

    // Numbered/bulleted list markers ("1.", "1)", "①", "1️⃣", ...) that
    // mark the start of a new place in a "recommend N spots" caption.
    private static let numberedMarker = try! NSRegularExpression(
        pattern: #"^(?:\d{1,2}[.)]|[①②③④⑤⑥⑦⑧⑨⑩]|[❶❷❸❹❺❻❼❽❾❿]|\d{1,2}️?⃣)\s*"#
    )

    // Strips leading emoji/bullets/hashtags off a line before treating it
    // as a name/address candidate. The hyphen sits at the very end of the
    // class (away from the full-width space) so it can never be read as a
    // Unicode range with a neighboring char. ㆍ (HANGUL LETTER ARAEA — an
    // archaic vowel letter essentially unused in modern text) is what
    // real on-device OCR renders a pin/bullet glyph as, found by testing
    // actual OCR output: without it, lines like "ㆍ부산 강남구 …" left a
    // bare "ㆍ" mistaken for the place name.
    private static let leadingDecoration = try! NSRegularExpression(
        pattern: #"^[\s\p{Extended_Pictographic}️*·•・#　ㆍ-]+"#
    )

    // Same idea, anchored at the end — strips a trailing separator/emoji
    // run (e.g. the pin emoji before an inline address: "봉래산 📍 부산
    // ...", or a "Name - Address" dash) when extracting whatever precedes
    // an address match on the same line.
    private static let trailingDecoration = try! NSRegularExpression(
        pattern: #"[\s\p{Extended_Pictographic}️*·•・#　ㆍ\-–—:：|]+$"#
    )

    // A trailing Instagram handle mention in parentheses, e.g.
    // "모모스커피 본점 (@momos_coffee)" — common in "📍 Name (@handle)"
    // style listing captions. Stripped from the resolved name.
    private static let trailingHandle = try! NSRegularExpression(
        pattern: #"\s*\([@＠][^\s()]+\)\s*$"#
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

    private static func cleanTrailing(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let stripped = trailingDecoration.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespaces)
    }

    private static func stripHandle(_ name: String) -> String {
        let range = NSRange(name.startIndex..., in: name)
        let stripped = trailingHandle.stringByReplacingMatches(in: name, range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespaces)
    }

    private static func isHashtagLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        let words = trimmed.split(separator: " ").map(String.init)
        let hashtags = words.filter { $0.hasPrefix("#") }
        return !hashtags.isEmpty && Double(hashtags.count) >= Double(words.count) * 0.6
    }

    private static func isListMarkerLine(_ line: String) -> Bool {
        firstMatch(numberedMarker, in: line) != nil
    }

    private static func stripListMarker(_ line: String) -> String {
        guard let match = firstMatch(numberedMarker, in: line), let range = Range(match.range, in: line) else {
            return line
        }
        var result = line
        result.removeSubrange(range)
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func findAddressMatch(_ line: String) -> (regex: NSRegularExpression, match: NSTextCheckingResult)? {
        if let match = firstMatch(koreanAddress, in: line) { return (koreanAddress, match) }
        if let match = firstMatch(westernAddress, in: line) { return (westernAddress, match) }
        return nil
    }

    /// Parses a single place out of a block of caption lines (all the
    /// lines believed to describe just one place). Handles both "Name"
    /// then "Address" on separate lines, and "Name - Address" on one line.
    private static func parsePlaceBlock(_ lines: [String]) -> Result {
        var name: String?
        var address: String?

        // Pass 1: explicit "label: value" lines anywhere in the block.
        for line in lines {
            if name == nil, let match = firstMatch(nameLabel, in: line), let value = captured(line, match, 1) {
                name = cleanLine(value)
            }
            if address == nil, let match = firstMatch(addressLabel, in: line), let value = captured(line, match, 1) {
                address = cleanLine(value)
            }
        }

        // Pass 2: address-shaped text, when no label found. Remember which
        // line and where in it, so a "Name - Address" line can still yield
        // a name.
        var addressLineIndex = -1
        var addressRange: Range<String.Index>?
        if address == nil {
            for (i, line) in lines.enumerated() {
                if let (_, match) = findAddressMatch(line), let range = Range(match.range, in: line) {
                    address = cleanLine(String(line[range]))
                    addressLineIndex = i
                    addressRange = range
                    break
                }
            }
        }

        // Pass 3: name. Try, in order: splitting the address line itself
        // ("Name - Address"); the nearest non-hashtag line immediately
        // before the address (closest wins, so an unrelated intro line
        // earlier in a multi-address block doesn't get picked over the
        // actual name); then any other usable, non-hashtag line.
        if name == nil {
            if addressLineIndex >= 0, let addressRange {
                let line = lines[addressLineIndex]
                let before = cleanTrailing(String(line[line.startIndex..<addressRange.lowerBound]))
                let cleanedBefore = cleanLine(before)
                if !cleanedBefore.isEmpty { name = cleanedBefore }
            }
            if name == nil, addressLineIndex > 0 {
                for i in stride(from: addressLineIndex - 1, through: 0, by: -1) {
                    if isHashtagLine(lines[i]) { continue }
                    let cleaned = cleanLine(lines[i])
                    if !cleaned.isEmpty && cleaned.count <= 60 {
                        name = cleaned
                        break
                    }
                }
            }
            if name == nil {
                for (i, line) in lines.enumerated() {
                    if i == addressLineIndex { continue }
                    if isHashtagLine(line) { continue }
                    let cleaned = cleanLine(line)
                    if !cleaned.isEmpty && cleaned.count <= 60 {
                        name = cleaned
                        break
                    }
                }
            }
        }

        return Result(name: name.map(stripHandle), address: address)
    }

    private static func nonEmptyLines(_ caption: String) -> [String] {
        caption
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Handles both a caption describing a single place and one listing
    /// several — a "recommend N spots" numbered list, or several distinct
    /// address-shaped lines without numbering — returning a single-item
    /// list (or an empty one) when the caption only describes one place.
    static func parseMultiple(_ caption: String) -> [Result] {
        let lines = nonEmptyLines(caption)
        if lines.isEmpty { return [] }

        // Group into blocks split at each numbered-list marker line.
        // Anything before the first marker (an intro line like "3 spots I
        // loved!") is discarded rather than treated as its own place.
        var blocks: [[String]] = []
        var current: [String] = []
        var sawMarker = false
        for line in lines {
            if isListMarkerLine(line) {
                if sawMarker && !current.isEmpty { blocks.append(current) }
                sawMarker = true
                current = [stripListMarker(line)]
            } else if sawMarker {
                current.append(line)
            }
        }
        if sawMarker && !current.isEmpty { blocks.append(current) }

        if sawMarker && blocks.count > 1 {
            return blocks.map(parsePlaceBlock).filter { $0.name != nil || $0.address != nil }
        }

        // No numbered list: look for multiple distinct address-shaped
        // lines, each paired with whatever precedes it (back to the
        // previous address, or the start of the caption) as its block.
        let addressLineIndexes = lines.enumerated().compactMap { i, line in
            findAddressMatch(line) != nil ? i : nil
        }

        if addressLineIndexes.count <= 1 {
            let single = parsePlaceBlock(lines)
            return (single.name != nil || single.address != nil) ? [single] : []
        }

        var results: [Result] = []
        var previousIndex = -1
        for idx in addressLineIndexes {
            let blockLines = Array(lines[(previousIndex + 1)...idx])
            results.append(parsePlaceBlock(blockLines))
            previousIndex = idx
        }
        return results
    }
}
