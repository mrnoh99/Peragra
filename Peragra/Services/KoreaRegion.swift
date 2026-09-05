import Foundation

/// A rough bounding box for South Korea (including Jeju and the east-sea
/// islands). Kakao Map and Naver Map have essentially no useful data
/// outside Korea, unlike Google Maps, so their "open in..." links only
/// make sense for a place actually located here.
enum KoreaRegion {
    static func contains(latitude: Double, longitude: Double) -> Bool {
        (33.0...38.9).contains(latitude) && (124.5...132.0).contains(longitude)
    }
}
