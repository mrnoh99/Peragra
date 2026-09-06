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
}
