import CoreLocation

enum GeocodingService {
    struct Result {
        let latitude: Double
        let longitude: Double
    }

    /// Looks up coordinates for a free-text place name/address. Uses the
    /// Google Geocoding API when the user has opted into Google Maps in
    /// Settings (their own key if they entered one, otherwise the app's
    /// bundled default); otherwise falls back to Apple's system geocoder
    /// (no API key required — the default). `contextHint` (typically the
    /// trip's destination) disambiguates places that share a common name.
    static func geocode(query: String, contextHint: String?) async -> Result? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fullQuery: String
        if let contextHint, !contextHint.trimmingCharacters(in: .whitespaces).isEmpty {
            fullQuery = "\(trimmed), \(contextHint)"
        } else {
            fullQuery = trimmed
        }

        if MapSettings.shared.isGoogleActive {
            let apiKey = MapSettings.shared.effectiveGoogleMapsAPIKey
            guard let result = await GoogleGeocodingService.geocode(query: fullQuery, apiKey: apiKey) else {
                return nil
            }
            return Result(latitude: result.latitude, longitude: result.longitude)
        }

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(fullQuery)
            guard let coordinate = placemarks.first?.location?.coordinate else { return nil }
            return Result(latitude: coordinate.latitude, longitude: coordinate.longitude)
        } catch {
            return nil
        }
    }
}
