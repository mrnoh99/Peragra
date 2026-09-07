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
    ///
    /// The query's trailing country name is normalized to English first
    /// (see CountryNames) — a Korean-language source address often has
    /// just the country name translated (e.g. "..., 이탈리아" for an
    /// otherwise Italian address), and that one mixed-script token can be
    /// enough to make a geocoder fail on an address it would otherwise
    /// handle fine.
    ///
    /// `providerOverride`, when given, is used in place of the globally
    /// configured provider — set by geocode(name:address:contextHint:)
    /// when this board has a non-Korean place and Naver (which has no
    /// useful data outside Korea at all) is the global setting.
    static func geocode(query: String, contextHint: String?, providerOverride: MapProvider? = nil) async -> Result? {
        let trimmed = CountryNames.normalizeTrailingCountryName(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { return nil }

        let fullQuery: String
        if let contextHint, !contextHint.trimmingCharacters(in: .whitespaces).isEmpty {
            fullQuery = "\(trimmed), \(contextHint)"
        } else {
            fullQuery = trimmed
        }

        let effectiveProvider = providerOverride ?? MapSettings.shared.provider

        if effectiveProvider == .google {
            let apiKey = MapSettings.shared.effectiveGoogleMapsAPIKey
            guard let result = await GoogleGeocodingService.geocode(query: fullQuery, apiKey: apiKey) else {
                return nil
            }
            return Result(latitude: result.latitude, longitude: result.longitude)
        }

        if effectiveProvider == .naver,
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

    /// Tries geocoding a place's own address text first (when it has
    /// one), then falls back to geocoding by its name alone. An
    /// address-focused geocoder is much better at matching a well-known
    /// landmark by its *name* than at parsing a vague, informal, or
    /// incomplete address string — e.g. a private island's garden with
    /// no real street address of its own, which the interactive Google
    /// Maps app still finds by name even though the Geocoding API
    /// rejects its address text outright.
    ///
    /// `siblingPlaces` — this board's other places — is checked alongside
    /// this place's own name/address for a non-Korean signal (see
    /// MapProviderPolicy), so one confirmed non-Korean place is enough to
    /// switch the whole board off Naver, not just places that happen to
    /// name a country themselves.
    static func geocode(
        name: String,
        address: String,
        contextHint: String?,
        siblingPlaces: [MapProviderPolicy.PlaceLike] = []
    ) async -> Result? {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let selfPlace = MapProviderPolicy.PlaceLike(latitude: nil, longitude: nil, name: trimmedName, address: trimmedAddress)

        let places = [selfPlace] + siblingPlaces
        let providerOverride = MapProviderPolicy.pickProvider(MapSettings.shared.provider, places: places)

        if !trimmedAddress.isEmpty,
           let result = await geocode(query: trimmedAddress, contextHint: contextHint, providerOverride: providerOverride),
           isPlausible(result, selfPlace: selfPlace, siblingPlaces: siblingPlaces) {
            return result
        }
        if !trimmedName.isEmpty,
           let result = await geocode(query: trimmedName, contextHint: contextHint, providerOverride: providerOverride),
           isPlausible(result, selfPlace: selfPlace, siblingPlaces: siblingPlaces) {
            return result
        }
        return nil
    }

    /// A geocoder can confidently return a real coordinate for an
    /// obscure/short name that just happens to phonetically or partially
    /// match something completely unrelated on another continent — one
    /// place ended up plotted in the Gulf of Guinea for exactly this
    /// reason. Rejects a result that lands outside Korea when nothing
    /// suggests it should: this place's own name/address doesn't mention
    /// a non-Korean country, AND this board already has another place
    /// confirmed inside Korea (so this isn't just a legitimately
    /// international board/trip, where an out-of-Korea result is
    /// expected and fine). A rejected result falls back to the next
    /// query (name after address, or "couldn't locate") rather than
    /// silently showing a wrong location.
    private static func isPlausible(_ result: Result, selfPlace: MapProviderPolicy.PlaceLike, siblingPlaces: [MapProviderPolicy.PlaceLike]) -> Bool {
        if KoreaRegion.contains(latitude: result.latitude, longitude: result.longitude) { return true }
        if CountryNames.mentionsNonKoreanCountry(selfPlace.address) || CountryNames.mentionsNonKoreanCountry(selfPlace.name) { return true }
        let siblingConfirmedInKorea = siblingPlaces.contains { sibling in
            guard let latitude = sibling.latitude, let longitude = sibling.longitude else { return false }
            return KoreaRegion.contains(latitude: latitude, longitude: longitude)
        }
        return !siblingConfirmedInKorea
    }

    /// Reverse geocoding (coordinate -> address/name), for turning a GPS
    /// fix read off an on-site photo into something readable to fill in a
    /// place's address (and, best-effort, its name) automatically. Same
    /// Google/Apple dispatch as `geocode(query:contextHint:)`.
    ///
    /// For a Korean coordinate, this always tries Naver for the *name* as
    /// a final step when the primary provider didn't find one — even if
    /// Naver isn't the active provider — since Naver's own address
    /// database is the most reliable at resolving "what business is
    /// actually at this exact address" in Korea (a storefront photo with
    /// no legible signage otherwise has no way to name itself). Only
    /// needs a Client ID + Secret to have been entered in Settings, not
    /// selected as the active provider.
    static func reverseGeocode(latitude: Double, longitude: Double) async -> ReverseResult? {
        var result: ReverseResult?

        if MapSettings.shared.isGoogleActive {
            let apiKey = MapSettings.shared.effectiveGoogleMapsAPIKey
            if let googleResult = await GoogleGeocodingService.reverseGeocode(latitude: latitude, longitude: longitude, apiKey: apiKey) {
                result = ReverseResult(address: googleResult.address, name: googleResult.name)
            }
        } else if MapSettings.shared.isNaverActive,
                  let clientId = MapSettings.shared.naverClientId,
                  let clientSecret = MapSettings.shared.naverClientSecret {
            if let naverResult = await NaverGeocodingService.reverseGeocode(latitude: latitude, longitude: longitude, clientId: clientId, clientSecret: clientSecret) {
                result = ReverseResult(address: naverResult.address, name: naverResult.name)
            }
        } else {
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: latitude, longitude: longitude)
            if let placemarks = try? await geocoder.reverseGeocodeLocation(location), let placemark = placemarks.first {
                result = ReverseResult(address: formattedAddress(from: placemark), name: placemark.name)
            }
        }

        if result?.name == nil, !MapSettings.shared.isNaverActive,
           let clientId = MapSettings.shared.naverClientId, let clientSecret = MapSettings.shared.naverClientSecret,
           KoreaRegion.contains(latitude: latitude, longitude: longitude),
           let naverResult = await NaverGeocodingService.reverseGeocode(latitude: latitude, longitude: longitude, clientId: clientId, clientSecret: clientSecret),
           let name = naverResult.name {
            result = ReverseResult(address: result?.address ?? naverResult.address, name: name)
        }

        return result
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
