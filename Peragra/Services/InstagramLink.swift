import Foundation

enum InstagramLink {
    private static let pattern =
        #"^https?://(www\.)?instagram\.com/(p|reel|reels|tv)/[a-zA-Z0-9_-]+/?"#

    /// Returns the canonical post/reel URL string if `value` looks like a
    /// valid Instagram post link, trimming any tracking query string.
    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(trimmed[range])
    }
}
