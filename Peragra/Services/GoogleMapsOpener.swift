import Foundation

/// Builds a universal Google Maps link that opens the native app on
/// devices where it's installed, or maps.google.com otherwise. Always
/// searches by "name, address" rather than the geocoded lat/lng, so the
/// map shows a readable label instead of raw coordinates.
enum GoogleMapsOpener {
    static func url(for place: Place) -> URL? {
        let parts = [place.name, place.address].filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        let query = parts.joined(separator: ", ")

        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: query),
        ]
        return components?.url
    }
}
