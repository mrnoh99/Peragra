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

    /// A directions link visiting several places in order — the last one
    /// as the destination, up to 2 more before it as waypoints (rV1.../
    /// rV2..., the scheme's own cap; anything past 2 is dropped). No
    /// explicit starting coordinate needed (see `url(for:)` above), so
    /// unlike KakaoMapOpener/NaverMapOpener's directionsURL this needs no
    /// LocationService lookup and isn't async.
    static func directionsURL(for places: [Place]) -> URL? {
        // Places outside Korea are dropped rather than failing the whole
        // route — this also naturally hides the button for a trip that
        // isn't in Korea at all, since `inKorea` ends up empty.
        let inKorea = places.filter { place in
            guard let coordinate = place.coordinate2D else { return false }
            return KoreaRegion.contains(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        guard let destination = inKorea.last, let destinationCoordinate = destination.coordinate2D else { return nil }
        let waypoints = inKorea.dropLast().prefix(2)

        var queryItems = [
            URLQueryItem(name: "rGoName", value: destination.name),
            URLQueryItem(name: "rGoX", value: "\(destinationCoordinate.longitude)"),
            URLQueryItem(name: "rGoY", value: "\(destinationCoordinate.latitude)"),
        ]
        for (index, waypoint) in waypoints.enumerated() {
            guard let coordinate = waypoint.coordinate2D else { continue }
            let n = index + 1
            queryItems.append(URLQueryItem(name: "rV\(n)Name", value: waypoint.name))
            queryItems.append(URLQueryItem(name: "rV\(n)X", value: "\(coordinate.longitude)"))
            queryItems.append(URLQueryItem(name: "rV\(n)Y", value: "\(coordinate.latitude)"))
        }

        var components = URLComponents(string: "tmap://route")
        components?.queryItems = queryItems
        return components?.url
    }
}
