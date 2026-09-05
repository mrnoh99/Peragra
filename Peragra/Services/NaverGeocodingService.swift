import Foundation

/// Geocoding via NAVER Cloud Platform's Maps Geocoding/Reverse Geocoding
/// REST APIs, for people who've opted into Naver Maps in Settings with
/// their own Client ID + Client Secret — the most accurate geocoder for
/// Korean addresses, since Apple's CLGeocoder and Google's Geocoding API
/// both have comparatively weak Korean road-name/lot-number coverage.
///
/// Unlike the web app (which loads Naver's JS SDK and calls
/// naver.maps.Service.geocode — see naverGeocode.ts for why a plain fetch
/// isn't an option there), a native URLSession request isn't subject to
/// CORS, so this calls Naver's REST endpoints directly, the same way
/// GoogleGeocodingService already does for Google.
///
/// NOTE: implemented against NAVER Cloud Platform's documented REST
/// endpoints (naveropenapi.apigw.ntruss.com) without a live NCP key to
/// test against in this environment — if geocoding fails outright (not
/// just "no result"), check the surfaced error message first; NCP has
/// migrated this product's API gateway domain before, so a 404 most
/// likely means the endpoint moved again and needs updating here.
enum NaverGeocodingService {
    struct Result {
        let latitude: Double
        let longitude: Double
    }

    struct ReverseResult {
        let address: String
        let name: String?
    }

    private static let geocodeURL = URL(string: "https://naveropenapi.apigw.ntruss.com/map-geocode/v2/geocode")!
    private static let reverseGeocodeURL = URL(string: "https://naveropenapi.apigw.ntruss.com/map-reversegeocode/v2/gc")!

    static func geocode(query: String, clientId: String, clientSecret: String) async -> Result? {
        var components = URLComponents(url: geocodeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "query", value: query)]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(clientId, forHTTPHeaderField: "x-ncp-apigw-api-key-id")
        request.setValue(clientSecret, forHTTPHeaderField: "x-ncp-apigw-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                print("Naver geocoding failed: unexpected HTTP status")
                return nil
            }
            let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
            guard let first = decoded.addresses?.first,
                  let latitude = Double(first.y), let longitude = Double(first.x) else {
                return nil
            }
            return Result(latitude: latitude, longitude: longitude)
        } catch {
            print("Naver geocoding request failed: \(error)")
            return nil
        }
    }

    static func reverseGeocode(latitude: Double, longitude: Double, clientId: String, clientSecret: String) async -> ReverseResult? {
        var components = URLComponents(url: reverseGeocodeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            // Naver's coords param is "lng,lat" — the opposite order from
            // how this app's own Result/ReverseResult always name them.
            URLQueryItem(name: "coords", value: "\(longitude),\(latitude)"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "orders", value: "roadaddr,addr"),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(clientId, forHTTPHeaderField: "x-ncp-apigw-api-key-id")
        request.setValue(clientSecret, forHTTPHeaderField: "x-ncp-apigw-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                print("Naver reverse geocoding failed: unexpected HTTP status")
                return nil
            }
            let decoded = try JSONDecoder().decode(ReverseGeocodeResponse.self, from: data)
            guard let results = decoded.results, !results.isEmpty else { return nil }
            let roadResult = results.first(where: { $0.name == "roadaddr" }) ?? results[0]
            let address = formattedAddress(from: roadResult)
            guard !address.isEmpty else { return nil }
            return ReverseResult(address: address, name: roadResult.land?.addition0?.value)
        } catch {
            print("Naver reverse geocoding request failed: \(error)")
            return nil
        }
    }

    private static func formattedAddress(from result: ReverseGeocodeResult) -> String {
        var parts = [result.region?.area1?.name, result.region?.area2?.name, result.region?.area3?.name, result.region?.area4?.name]
            .compactMap { $0 }
        if let land = result.land {
            if let name = land.name { parts.append(name) }
            if let number1 = land.number1 {
                parts.append(land.number2.map { "\(number1)-\($0)" } ?? number1)
            }
            if let building = land.addition0?.value { parts.append(building) }
        }
        return parts.joined(separator: " ")
    }

    private struct GeocodeResponse: Decodable {
        let addresses: [GeocodeAddress]?
    }

    private struct GeocodeAddress: Decodable {
        let roadAddress: String?
        let jibunAddress: String?
        let x: String
        let y: String
    }

    private struct ReverseGeocodeResponse: Decodable {
        let results: [ReverseGeocodeResult]?
    }

    private struct ReverseGeocodeResult: Decodable {
        let name: String?
        let region: ReverseGeocodeRegion?
        let land: ReverseGeocodeLand?
    }

    private struct ReverseGeocodeRegion: Decodable {
        let area1: ReverseGeocodeAreaName?
        let area2: ReverseGeocodeAreaName?
        let area3: ReverseGeocodeAreaName?
        let area4: ReverseGeocodeAreaName?
    }

    private struct ReverseGeocodeAreaName: Decodable {
        let name: String?
    }

    private struct ReverseGeocodeLand: Decodable {
        let name: String?
        let number1: String?
        let number2: String?
        let addition0: ReverseGeocodeAddition?
    }

    private struct ReverseGeocodeAddition: Decodable {
        let value: String?
    }
}
