import Foundation

/// Tmap's own app URL scheme. Like Naver Map's nmap://, there's no
/// documented web fallback (not that this matters for a native openURL()
/// call the way it does on web). Unlike Kakao and Naver's route schemes,
/// a starting point is optional here: Tmap defaults to the device's own
/// current location when rStX/rStY/rStName are omitted, so no
/// LocationService round-trip is needed just to send a route.
enum TmapOpener {
    static func url(for place: Place) -> URL? {
        guard
            let coordinate = place.coordinate2D,
            !place.name.isEmpty,
            KoreaRegion.contains(latitude: coordinate.latitude, longitude: coordinate.longitude)
        else { return nil }

        var components = URLComponents(string: "tmap://route")
        components?.queryItems = [
            URLQueryItem(name: "rGoName", value: place.name),
            URLQueryItem(name: "rGoX", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "rGoY", value: "\(coordinate.latitude)"),
        ]
        return components?.url
    }
}
