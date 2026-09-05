import Contacts
import CoreLocation

enum GeocodingService {
    struct Result {
        let latitude: Double
        let longitude: Double
    }

    struct ReverseResult {
        let address: String
        // Best-effort — only set when the coordinate resolved to an
        // actual named place rather than just a street address.
        let name: String?
    }

    /// Looks up coordinates for a free-text place name/address. Uses the
    /// Google Geocoding API when the user has opted into Google Maps in
    /// Settings (their own key if they entered one, otherwise the app's
    /// bundled default), or Naver's Geocoding API when opted into Naver
    /// Maps with their own Client ID/Secret (the most accurate for
    /// Korean addresses); otherwise falls back to Apple's system geocoder
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

        if MapSettings.shared.isNaverActive,
           let clientId = MapSettings.shared.naverClientId,
           let clientSecret = MapSettings.shared.naverClientSecret {
            guard let result = await NaverGeocodingService.geocode(query: fullQuery, clientId: clientId, clientSecret: clientSecret) else {
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

    /// Reverse geocoding (coordinate -> address/name), for turning a GPS
    /// fix read off an on-site photo into something readable to fill in a
    /// place's address (and, best-effort, its name) automatically. Same
    /// Google/Apple dispatch as `geocode(query:contextHint:)`.
    static func reverseGeocode(latitude: Double, longitude: Double) async -> ReverseResult? {
        if MapSettings.shared.isGoogleActive {
            let apiKey = MapSettings.shared.effectiveGoogleMapsAPIKey
            guard let result = await GoogleGeocodingService.reverseGeocode(latitude: latitude, longitude: longitude, apiKey: apiKey) else {
                return nil
            }
            return ReverseResult(address: result.address, name: result.name)
        }

        if MapSettings.shared.isNaverActive,
           let clientId = MapSettings.shared.naverClientId,
           let clientSecret = MapSettings.shared.naverClientSecret {
            guard let result = await NaverGeocodingService.reverseGeocode(latitude: latitude, longitude: longitude, clientId: clientId, clientSecret: clientSecret) else {
                return nil
            }
            return ReverseResult(address: result.address, name: result.name)
        }

        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            return ReverseResult(address: formattedAddress(from: placemark), name: placemark.name)
        } catch {
            return nil
        }
    }

    private static func formattedAddress(from placemark: CLPlacemark) -> String {
        if let postalAddress = placemark.postalAddress {
            return CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
                .replacingOccurrences(of: "\n", with: ", ")
        }
        return [placemark.name, placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
