import Foundation

/// Nearby-place search via the Places API (New)'s searchNearby endpoint,
/// for people who've opted into Google Maps in Settings (using the app's
/// bundled key, or their own if they entered one). Only called when that
/// opt-in is active — see NearbyPlacesService.search, the entry point
/// every call site actually uses.
enum GoogleNearbyPlacesService {
    static func search(latitude: Double, longitude: Double, apiKey: String) async -> [NearbyPlacesService.Candidate] {
        guard let url = URL(string: "https://places.googleapis.com/v1/places:searchNearby") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "places.displayName,places.formattedAddress,places.location,places.primaryType,places.nationalPhoneNumber",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        // See GoogleGeocodingService for why this header is needed for a
        // direct URLSession call (Google's own SDKs set it automatically).
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        let body: [String: Any] = [
            "maxResultCount": 8,
            "rankPreference": "DISTANCE",
            "locationRestriction": [
                "circle": [
                    "center": ["latitude": latitude, "longitude": longitude],
                    "radius": 100.0,
                ],
            ],
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return [] }
        request.httpBody = bodyData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(SearchNearbyResponse.self, from: data)
            guard let places = decoded.places else { return [] }
            return places.compactMap { place in
                guard let location = place.location else { return nil }
                return NearbyPlacesService.Candidate(
                    name: place.displayName?.text ?? "Unnamed place",
                    address: place.formattedAddress,
                    phone: place.nationalPhoneNumber,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    category: categoryForPrimaryType(place.primaryType)
                )
            }
        } catch {
            print("Google nearby places request failed: \(error)")
            return []
        }
    }

    private static func categoryForPrimaryType(_ primaryType: String?) -> PlaceCategory {
        guard let primaryType else { return .other }
        switch primaryType {
        case "restaurant", "meal_takeaway", "meal_delivery", "bakery", "food_court":
            return .restaurant
        case "cafe", "coffee_shop":
            return .cafe
        case "tourist_attraction", "museum", "art_gallery", "park", "landmark", "place_of_worship",
             "church", "temple", "zoo", "amusement_park", "aquarium":
            return .attraction
        case "store", "shopping_mall", "clothing_store", "supermarket", "convenience_store",
             "book_store", "department_store", "electronics_store", "gift_shop":
            return .shopping
        case "lodging", "hotel":
            return .hotel
        case "bar", "night_club", "pub", "casino":
            return .nightlife
        default:
            return .other
        }
    }

    private struct SearchNearbyResponse: Decodable {
        let places: [PlaceResult]?
    }

    private struct PlaceResult: Decodable {
        let displayName: DisplayName?
        let formattedAddress: String?
        let location: Location?
        let primaryType: String?
        let nationalPhoneNumber: String?
    }

    private struct DisplayName: Decodable {
        let text: String
    }

    private struct Location: Decodable {
        let latitude: Double
        let longitude: Double
    }
}
