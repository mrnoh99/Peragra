import Foundation

/// Builds a universal Google Maps link that opens the native app on
/// devices where it's installed, or maps.google.com otherwise. Centers on
/// the geocoded coordinate when there is one, falling back to a text
/// search for "name, address" so it still works for places that never
/// geocoded.
enum GoogleMapsOpener {
    static func url(for place: Place) -> URL? {
        let query: String
        if let coordinate = place.coordinate2D {
            query = "\(coordinate.latitude),\(coordinate.longitude)"
        } else {
            let parts = [place.name, place.address].filter { !$0.isEmpty }
            guard !parts.isEmpty else { return nil }
            query = parts.joined(separator: ", ")
        }

        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: query),
        ]
        return components?.url
    }
}
