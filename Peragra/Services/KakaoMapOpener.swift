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
}
