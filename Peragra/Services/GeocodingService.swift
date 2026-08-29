import CoreLocation

enum GeocodingService {
    struct Result {
        let latitude: Double
        let longitude: Double
    }

    /// Looks up coordinates for a free-text place name/address using Apple's
    /// system geocoder. No API key required. `contextHint` (typically the
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
