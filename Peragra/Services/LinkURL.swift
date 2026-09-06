import Foundation

/// Shared normalization for a manually-entered or AI-extracted
/// Instagram/website link — a person (or a model reading a caption) often
/// gives one without "https://" (e.g. "instagram.com/x"), which
/// URL(string:) would otherwise treat as a relative path rather than the
/// address it looks like.
enum LinkURL {
    static func normalize(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        if raw.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) != nil {
            return URL(string: raw)
        }
        return URL(string: "https://\(raw)")
    }

    /// Whether a link points at Instagram — used to label it "Instagram"
    /// instead of the generic "Website" wherever it's shown.
    static func isInstagram(_ raw: String) -> Bool {
        normalize(raw)?.host?.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression) == "instagram.com"
    }
}
