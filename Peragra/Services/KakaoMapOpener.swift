import CoreLocation
import Foundation

/// Kakao Map's own public "share a route" link — no API key needed, unlike
/// Kakao Navi's own app-launch scheme. Opens the native app on devices
/// where it's installed, or map.kakao.com otherwise; from inside the app,
/// "길찾기" hands off to Kakao Navi. Unlike GoogleMapsOpener's name/address
/// text search, this format takes a real numeric coordinate, so it's only
/// available once this app's own geocoding has actually located the place.
enum KakaoMapOpener {
    static func url(for place: Place) -> URL? {
        guard let coordinate = place.coordinate2D, !place.name.isEmpty else { return nil }

        var components = URLComponents(string: "https://map.kakao.com")
        components?.path = "/link/to/\(place.name),\(coordinate.latitude),\(coordinate.longitude)"
        return components?.url
    }

    /// A directions link visiting several places in order, via Kakao Map's
    /// mobile route scheme — unlike `url(for:)` above, this scheme has no
    /// "start from wherever I am" default, so it requires an explicit
    /// starting coordinate (resolve one via LocationService before calling
    /// this). Only a destination and up to 5 waypoints are supported, so
    /// anything past 6 places is silently dropped.
    ///
    /// This route scheme is far less documented than the single-place link
    /// above and untested against a real Kakao Map install — if it turns
    /// out to be wrong, the single-place "Kakao Map" button on each place
    /// is the verified fallback.
    static func directionsURL(for places: [Place], from origin: CLLocationCoordinate2D) -> URL? {
        let coordinates = places.compactMap { place -> String? in
            guard let coordinate = place.coordinate2D else { return nil }
            return "\(coordinate.latitude),\(coordinate.longitude)"
        }
        guard let destination = coordinates.last else { return nil }
        let waypoints = coordinates.dropLast().prefix(5)

        var queryItems = [
            URLQueryItem(name: "sp", value: "\(origin.latitude),\(origin.longitude)"),
            URLQueryItem(name: "ep", value: destination),
            URLQueryItem(name: "by", value: "car"),
        ]
        for (index, waypoint) in waypoints.enumerated() {
            queryItems.append(URLQueryItem(name: index == 0 ? "vp" : "vp\(index + 1)", value: waypoint))
        }

        var components = URLComponents(string: "http://m.map.kakao.com/scheme/route")
        components?.queryItems = queryItems
        return components?.url
    }
}
