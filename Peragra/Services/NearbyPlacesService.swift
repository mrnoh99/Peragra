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
    static func search(latitude: Double, longitude: Double, categoryHint: PlaceCategory? = nil) async -> [Candidate] {
        if MapSettings.shared.isGoogleActive {
            let apiKey = MapSettings.shared.effectiveGoogleMapsAPIKey
            return await GoogleNearbyPlacesService.search(latitude: latitude, longitude: longitude, apiKey: apiKey, categoryHint: categoryHint)
        }
        return await appleSearch(latitude: latitude, longitude: longitude, categoryHint: categoryHint)
    }

    private static func appleSearch(latitude: Double, longitude: Double, categoryHint: PlaceCategory?) async -> [Candidate] {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        var request = MKLocalPointsOfInterestRequest(center: center, radius: 100)
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
