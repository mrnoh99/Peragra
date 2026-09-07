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

    /// - Parameters:
    ///   - categoryHint: Narrows the search to one category, for when the
    ///     plain nearby list is too ambiguous to tell which result is
    ///     right and the person supplies a hint (restaurant, cafe, ...).
    ///   - accuracy: The GPS fix's own reported horizontalAccuracy, when
    ///     known — sizes the search radius (see radius(for:accuracy:))
    ///     instead of trusting one fixed distance for every situation.
    ///
    /// Always returned nearest-first, regardless of provider — Google's
    /// own API already ranks by distance (rankPreference: DISTANCE, see
    /// GoogleNearbyPlacesService), but Apple's MKLocalPointsOfInterestRequest
    /// doesn't document any particular result order, so this sorts every
    /// result by its actual distance from the query coordinate itself
    /// rather than trusting either provider's ordering.
    static func search(
        latitude: Double,
        longitude: Double,
        categoryHint: PlaceCategory? = nil,
        accuracy: CLLocationAccuracy? = nil
    ) async -> [Candidate] {
        let radius = radius(for: categoryHint, accuracy: accuracy)
        let results: [Candidate]
        if MapSettings.shared.isGoogleActive {
            let apiKey = MapSettings.shared.effectiveGoogleMapsAPIKey
            results = await GoogleNearbyPlacesService.search(latitude: latitude, longitude: longitude, apiKey: apiKey, categoryHint: categoryHint, radius: radius)
        } else {
            results = await appleSearch(latitude: latitude, longitude: longitude, categoryHint: categoryHint, radius: radius)
        }

        let origin = CLLocation(latitude: latitude, longitude: longitude)
        return results.sorted { lhs, rhs in
            let lhsDistance = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(from: origin)
            let rhsDistance = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude).distance(from: origin)
            return lhsDistance < rhsDistance
        }
    }

    /// A restaurant/cafe/shop/hotel/nightlife spot is a single building —
    /// a tight radius avoids pulling in unrelated places from down the
    /// block. An attraction can be spread across its own plaza or park,
    /// and so can whatever's behind an unset hint (it might turn out to
    /// be an attraction) — a much wider radius is worth the extra,
    /// dismissable candidates it can pull in, since too narrow risks
    /// missing the real match entirely rather than just showing extras.
    ///
    /// Sized around the GPS fix's own reported accuracy (plus a fixed
    /// buffer for the ordinary case of a POI's indexed coordinate not
    /// landing exactly where the fix did), clamped to a floor (accuracy
    /// alone, on a great fix, would otherwise search unrealistically
    /// tight) and a ceiling (a bad fix shouldn't search a whole
    /// neighborhood). No accuracy at all (older/nil-carrying data) falls
    /// back to that category's own ceiling — better to search wide than
    /// assume a fix was good when it's genuinely unknown.
    private static func radius(for categoryHint: PlaceCategory?, accuracy: CLLocationAccuracy?) -> CLLocationDistance {
        let isPointLike: Bool
        switch categoryHint {
        case .restaurant, .cafe, .shopping, .hotel, .nightlife:
            isPointLike = true
        case .attraction, .other, nil:
            isPointLike = false
        }

        let buffer: CLLocationDistance = isPointLike ? 30 : 100
        let minimum: CLLocationDistance = isPointLike ? 80 : 150
        let maximum: CLLocationDistance = isPointLike ? 150 : 500

        guard let accuracy, accuracy > 0 else { return maximum }
        return min(maximum, max(minimum, accuracy + buffer))
    }

    private static func appleSearch(latitude: Double, longitude: Double, categoryHint: PlaceCategory?, radius: CLLocationDistance) async -> [Candidate] {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        var request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
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
