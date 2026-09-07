import Contacts
import CoreLocation
import MapKit

/// Finds real places near a coordinate, for presenting as pickable
/// candidates when a GPS fix (from an on-site photo) is the only
/// information available — letting the person confirm which actual place
/// it was rather than trusting a bare reverse geocode. Uses Apple's free
/// MapKit points-of-interest search by default (no key required); when
/// the user has opted into Google Maps with their own key, uses the
/// Places API (New) instead, matching the rest of this app's Google/Apple
/// dispatch pattern.
///
/// A monument or memorial can go missing from Apple's results even
/// within range: MKPointOfInterestCategory has no monument/landmark
/// case at all, so poiCategories(for:) below can only route `.attraction`
/// to the categories it does have (museum, park, ...) — one it doesn't
/// cover is simply never returned when a category hint is set narrowing
/// to attraction, and even an unfiltered search still depends on
/// whether Apple's own database indexed that specific site. Google's
/// Places API does have a "landmark" type (see
/// GoogleNearbyPlacesService) and tends to have better coverage here.
enum NearbyPlacesService {
    struct Candidate: Identifiable {
        let id = UUID()
        let name: String
        let address: String?
        let phone: String?
        let latitude: Double
        let longitude: Double
        let category: PlaceCategory
    }

    /// - Parameter categoryHint: Narrows the search to one category, for
    ///   when the plain nearby list is too ambiguous to tell which result
    ///   is right and the person supplies a hint (restaurant, cafe, ...).
    ///
    /// Always returned nearest-first, regardless of provider — Google's
    /// own API already ranks by distance (rankPreference: DISTANCE, see
    /// GoogleNearbyPlacesService), but Apple's MKLocalPointsOfInterestRequest
    /// doesn't document any particular result order, so this sorts every
    /// result by its actual distance from the query coordinate itself
    /// rather than trusting either provider's ordering.
    static func search(latitude: Double, longitude: Double, categoryHint: PlaceCategory? = nil) async -> [Candidate] {
        let results: [Candidate]
        if MapSettings.shared.isGoogleActive {
            let apiKey = MapSettings.shared.effectiveGoogleMapsAPIKey
            results = await GoogleNearbyPlacesService.search(latitude: latitude, longitude: longitude, apiKey: apiKey, categoryHint: categoryHint)
        } else {
            results = await appleSearch(latitude: latitude, longitude: longitude, categoryHint: categoryHint)
        }

        let origin = CLLocation(latitude: latitude, longitude: longitude)
        return results.sorted { lhs, rhs in
            let lhsDistance = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(from: origin)
            let rhsDistance = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude).distance(from: origin)
            return lhsDistance < rhsDistance
        }
    }

    // A photo's GPS fix and a POI's own indexed coordinate rarely land in
    // exactly the same spot — more so for something spread across its
    // own plaza, like a monument — so 100m was cutting off real, nearby
    // matches.
    private static let searchRadiusMeters: CLLocationDistance = 200

    private static func appleSearch(latitude: Double, longitude: Double, categoryHint: PlaceCategory?) async -> [Candidate] {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        var request = MKLocalPointsOfInterestRequest(center: center, radius: searchRadiusMeters)
        if let categoryHint, let poiCategories = poiCategories(for: categoryHint) {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: poiCategories)
        }
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.prefix(8).map { item in
                Candidate(
                    name: item.name ?? "Unnamed place",
                    address: formattedAddress(from: item.placemark),
                    phone: item.phoneNumber,
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude,
                    category: category(for: item.pointOfInterestCategory)
                )
            }
        } catch {
            return []
        }
    }

    private static func formattedAddress(from placemark: MKPlacemark) -> String? {
        if let postalAddress = placemark.postalAddress {
            return CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
                .replacingOccurrences(of: "\n", with: ", ")
        }
        return placemark.title
    }

    /// Inverse of `category(for:)` — nil for `.other` since that's every
    /// category MapKit knows about *except* the ones already covered by a
    /// more specific hint, not a filterable POI category of its own.
    private static func poiCategories(for category: PlaceCategory) -> [MKPointOfInterestCategory]? {
        switch category {
        case .restaurant:
            return [.restaurant, .bakery, .foodMarket]
        case .cafe:
            return [.cafe]
        case .attraction:
            return [.museum, .park, .nationalPark, .zoo, .aquarium, .amusementPark, .beach, .campground, .theater, .stadium]
        case .shopping:
            return [.store]
        case .hotel:
            return [.hotel]
        case .nightlife:
            return [.nightlife, .brewery, .winery]
        case .other:
            return nil
        }
    }

    private static func category(for poiCategory: MKPointOfInterestCategory?) -> PlaceCategory {
        guard let poiCategory else { return .other }
        switch poiCategory {
        case .restaurant, .bakery, .foodMarket:
            return .restaurant
        case .cafe:
            return .cafe
        case .museum, .park, .nationalPark, .zoo, .aquarium, .amusementPark, .beach, .campground, .theater, .stadium:
            return .attraction
        case .store:
            return .shopping
        case .hotel:
            return .hotel
        case .nightlife, .brewery, .winery:
            return .nightlife
        default:
            return .other
        }
    }
}
