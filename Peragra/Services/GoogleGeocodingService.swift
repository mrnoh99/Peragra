import Foundation

/// Free-text geocoding via the Google Geocoding API, for people who've
/// opted into Google Maps in Settings (using the app's bundled key, or
/// their own if they entered one). Only called when that opt-in is
/// active — see GeocodingService.geocode, which is the entry point every
/// call site actually uses.
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

        var request = URLRequest(url: url)
        // A Google Cloud Console API key restricted to "iOS apps" is
        // verified via this header — Google's own SDKs (like the Maps
        // JS API this app's map view loads in a WKWebView) set it
        // automatically, but a direct URLSession call like this one has
        // to add it itself, or the key gets REQUEST_DENIED even though
        // it's the right key for the right app.
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
            guard let location = decoded.results.first?.geometry.location else {
                // Logged rather than surfaced in the UI (the caller just
                // treats this as "couldn't locate") — but genuinely useful
                // when debugging why geocoding fails. REQUEST_DENIED in
                // particular usually means the Geocoding API isn't enabled
                // for this key/project — a separate toggle in Google Cloud
                // Console from the Maps SDK the map display itself uses.
                if decoded.status != "OK", decoded.status != "ZERO_RESULTS" {
                    print("Google geocoding failed: \(decoded.status) \(decoded.errorMessage ?? "")")
                }
                return nil
            }
            return Result(latitude: location.lat, longitude: location.lng)
        } catch {
            print("Google geocoding request failed: \(error)")
            return nil
        }
    }

    private struct GeocodeResponse: Decodable {
        let results: [GeocodeResult]
        let status: String
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case results
            case status
            case errorMessage = "error_message"
        }
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
