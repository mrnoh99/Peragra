import Foundation

/// Free-text geocoding via the Google Geocoding API, for people who've
/// opted into Google Maps in Settings with their own API key. Only called
/// when that opt-in is active — see GeocodingService.geocode, which is the
/// entry point every call site actually uses.
enum GoogleGeocodingService {
    struct Result {
        let latitude: Double
        let longitude: Double
    }

    static func geocode(query: String, apiKey: String) async -> Result? {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/geocode/json")
        components?.queryItems = [
            URLQueryItem(name: "address", value: query),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
            guard let location = decoded.results.first?.geometry.location else { return nil }
            return Result(latitude: location.lat, longitude: location.lng)
        } catch {
            return nil
        }
    }

    private struct GeocodeResponse: Decodable {
        let results: [GeocodeResult]
    }

    private struct GeocodeResult: Decodable {
        let geometry: Geometry
    }

    private struct Geometry: Decodable {
        let location: Location
    }

    private struct Location: Decodable {
        let lat: Double
        let lng: Double
    }
}
