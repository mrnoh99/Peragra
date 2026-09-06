import Foundation

enum MapProviderPolicy {
    struct PlaceLike {
        let latitude: Double?
        let longitude: Double?
        let name: String
        let address: String
    }

    /// Whether this place is (or almost certainly is) outside Korea —
    /// from its own geocoded coordinate when it has one, otherwise from
    /// its name/address text mentioning a known non-Korean country (see
    /// CountryNames). A place with neither signal returns false — "not
    /// confirmed non-Korea", not "confirmed Korea".
    static func isPlaceOutsideKorea(_ place: PlaceLike) -> Bool {
        if let latitude = place.latitude, let longitude = place.longitude {
            return !KoreaRegion.contains(latitude: latitude, longitude: longitude)
        }
        return CountryNames.mentionsNonKoreanCountry(place.address)
            || CountryNames.mentionsNonKoreanCountry(place.name)
    }

    /// Naver Map has essentially no useful data outside Korea — its
    /// geocoder simply can't resolve a non-Korean address at all. If
    /// Naver is the globally selected provider but this board's own
    /// places include one outside Korea (checked across every place
    /// passed in — a brand new place being added counts too, via its own
    /// address/name text, not just already-geocoded siblings), fall back
    /// to Google for this board specifically — Google always has a
    /// usable key (the user's own, or the app's bundled default), so
    /// unlike the web app there's no further "no key" fallback to make.
    /// Google and the free provider are left as-is either way, since both
    /// already work fine worldwide.
    static func pickProvider(_ provider: MapProvider, places: [PlaceLike]) -> MapProvider {
        guard provider == .naver else { return provider }
        guard places.contains(where: isPlaceOutsideKorea) else { return .naver }
        return .google
    }
}
