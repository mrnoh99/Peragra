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

    /// A search/route query for one place. Prefers "name, address" — but
    /// only when this app's own geocoding actually resolved that address
    /// (`.located`); for anything else (no address, or a `.failed`/
    /// `.estimated` pin that never located cleanly on our own map) the
    /// address text has already proven unreliable, so it's dropped in
    /// favor of qualifying the name with the trip's destination city
    /// instead. Confirmed by a real "can't find a way to the specified
    /// destination" failure on a place whose pin didn't show on our map
    /// either.
    ///
    /// When the name itself can't be trusted as search text — the
    /// "Unknown" placeholder left by an on-site capture with no legible
    /// signage, or truly empty — a text search has nothing real to match
    /// and Google Maps reports "no results" even though this app already
    /// has a real coordinate for the place. There, the query is the
    /// coordinate itself ("lat,lng", which Google's search API accepts
    /// directly) so the pin still resolves, at the cost of a coordinate
    /// label instead of a name.
    private static func query(for place: Place, tripDestination: String?) -> String? {
        let trimmedName = place.name.trimmingCharacters(in: .whitespaces)
        let hasUsableName = !trimmedName.isEmpty && trimmedName != "Unknown"

        if !hasUsableName, let latitude = place.latitude, let longitude = place.longitude,
           place.geocodeStatus == .located || place.geocodeStatus == .estimated {
            return "\(latitude),\(longitude)"
        }

        guard !place.name.isEmpty else { return nil }
        if place.geocodeStatus == .located, !place.address.isEmpty {
            return "\(place.name), \(place.address)"
        }
        guard let tripDestination, !tripDestination.isEmpty else { return place.name }
        return "\(place.name), \(tripDestination)"
    }
}
