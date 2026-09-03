import Foundation

/// Builds Google Maps links that open the native app on devices where
/// it's installed, or maps.google.com otherwise. Always searches/routes by
/// "name, address" rather than the geocoded lat/lng, so the map shows a
/// readable label instead of raw coordinates.
enum GoogleMapsOpener {
    static func url(for place: Place, tripDestination: String? = nil) -> URL? {
        guard let query = query(for: place, tripDestination: tripDestination) else { return nil }

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
    static func directionsURL(for places: [Place], tripDestination: String? = nil) -> URL? {
        let queries = places.compactMap { query(for: $0, tripDestination: tripDestination) }
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

    /// A search/route query for one place. Prefers "name, address"; when a
    /// place has no address on file, a bare name is often too ambiguous
    /// for Google Maps to resolve into an actual routable point (confirmed
    /// by a real "can't find a way to the specified destination" failure
    /// on a name-only waypoint) — qualifying it with the trip's
    /// destination city gives Maps something to disambiguate against.
    private static func query(for place: Place, tripDestination: String?) -> String? {
        guard !place.name.isEmpty else { return nil }
        if !place.address.isEmpty {
            return "\(place.name), \(place.address)"
        }
        guard let tripDestination, !tripDestination.isEmpty else { return place.name }
        return "\(place.name), \(tripDestination)"
    }
}
