import Foundation

/// Builds Google Maps links that open the native app on devices where
/// it's installed, or maps.google.com otherwise. Always searches/routes by
/// "name, address" rather than the geocoded lat/lng, so the map shows a
/// readable label instead of raw coordinates.
enum GoogleMapsOpener {
    static func url(for place: Place) -> URL? {
        guard let query = query(for: place) else { return nil }

        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: query),
        ]
        return components?.url
    }

    /// A directions link visiting several places in order — the last one
    /// as the destination, everything before it as waypoints. Origin is
    /// left unset so Google Maps starts from wherever the user currently is.
    static func directionsURL(for places: [Place]) -> URL? {
        let queries = places.compactMap(query(for:))
        guard let destination = queries.last else { return nil }
        let waypoints = queries.dropLast()

        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        var queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: destination),
        ]
        if !waypoints.isEmpty {
            queryItems.append(URLQueryItem(name: "waypoints", value: waypoints.joined(separator: "|")))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    private static func query(for place: Place) -> String? {
        let parts = [place.name, place.address].filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }
}
