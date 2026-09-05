import CoreLocation
import Foundation

/// Naver Map's own app URL scheme. Unlike Kakao Map's public web link,
/// there's no documented universal/web fallback for this one: `nmap://`
/// only opens something when the Naver Map app is installed. Calling
/// openURL() with no app registered for the scheme just fails quietly on
/// native iOS (unlike a web page's `<a href>`, which pops Safari's own
/// "address is invalid" alert — confirmed on device for the web build,
/// worked around there with a hidden-iframe launch instead of a direct
/// link). `appname` is just a required identifier for the calling app,
/// not a registered API key.
enum NaverMapOpener {
    private static let appName = "com.peragra.app"

    static func url(for place: Place) -> URL? {
        guard
            let coordinate = place.coordinate2D,
            !place.name.isEmpty,
            KoreaRegion.contains(latitude: coordinate.latitude, longitude: coordinate.longitude)
        else { return nil }

        var components = URLComponents(string: "nmap://place")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "lng", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "name", value: place.name),
            URLQueryItem(name: "appname", value: appName),
        ]
        return components?.url
    }

    /// A directions link visiting several places in order, via Naver
    /// Map's own car-route scheme — like Kakao's, this requires an
    /// explicit starting coordinate (no "start from wherever I am"
    /// default) and supports a destination plus up to 5 waypoints
    /// (v1lat/v1lng/v1name … v5lat/v5lng/v5name), so anything past 6
    /// places is silently dropped.
    static func directionsURL(for places: [Place], from origin: CLLocationCoordinate2D) -> URL? {
        // Places outside Korea are dropped rather than failing the whole
        // route — this also naturally hides the button for a trip that
        // isn't in Korea at all, since `inKorea` ends up empty.
        let inKorea = places.filter { place in
            guard let coordinate = place.coordinate2D else { return false }
            return KoreaRegion.contains(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        guard let destination = inKorea.last, let destinationCoordinate = destination.coordinate2D else { return nil }
        let waypoints = inKorea.dropLast().prefix(5)

        var queryItems = [
            URLQueryItem(name: "slat", value: "\(origin.latitude)"),
            URLQueryItem(name: "slng", value: "\(origin.longitude)"),
            URLQueryItem(name: "sname", value: "현재 위치"),
            URLQueryItem(name: "dlat", value: "\(destinationCoordinate.latitude)"),
            URLQueryItem(name: "dlng", value: "\(destinationCoordinate.longitude)"),
            URLQueryItem(name: "dname", value: destination.name),
            URLQueryItem(name: "appname", value: appName),
        ]
        for (index, waypoint) in waypoints.enumerated() {
            guard let coordinate = waypoint.coordinate2D else { continue }
            let n = index + 1
            queryItems.append(URLQueryItem(name: "v\(n)lat", value: "\(coordinate.latitude)"))
            queryItems.append(URLQueryItem(name: "v\(n)lng", value: "\(coordinate.longitude)"))
            queryItems.append(URLQueryItem(name: "v\(n)name", value: waypoint.name))
        }

        var components = URLComponents(string: "nmap://route/car")
        components?.queryItems = queryItems
        return components?.url
    }
}
