import Foundation
import Observation

/// Which map/geocoding provider to use. `.free` (Apple MapKit + CLGeocoder)
/// needs no API key and is the default; `.google` uses the app's bundled
/// Google Maps key unless the user enters their own in Settings; `.naver`
/// needs the user's own NCP Client ID/Secret (no bundled default — unlike
/// Google's key, restricted by app package name, a Naver key can't safely
/// ship in a public repo's compiled binary the same way) and is the most
/// accurate for Korean addresses. All three only affect geocoding here —
/// the map view itself always renders with Apple MapKit.
enum MapProvider: String {
    case free
    case google
    case naver
}

/// Reactive wrapper around the map provider choice (UserDefaults — not
/// sensitive) and the Keychain-stored Google Maps API key, so SwiftUI views
/// update automatically when either changes.
@Observable
final class MapSettings {
    static let shared = MapSettings()

    private static let keychainKey = "google-maps-api-key"
    private static let providerDefaultsKey = "map-provider"
    private static let naverClientIdKeychainKey = "naver-maps-client-id"
    private static let naverClientSecretKeychainKey = "naver-maps-client-secret"

    /// Ships with the app so switching to Google Maps in Settings works
    /// immediately, without every installer needing their own Google
    /// Cloud project — restricted in Google Cloud Console to this app's
    /// bundle ID (com.peragra.app) and to just the Maps JavaScript and
    /// Geocoding APIs, with a daily quota, since (like any client-embedded
    /// key) it's extractable from the compiled binary. A user's own key,
    /// entered in Settings, always takes priority over this one.
    private static let defaultGoogleMapsAPIKey = "AIzaSyAVDyA5hl0P7xHT9qT4jRS3nAUFFfaOnzo"

    private(set) var provider: MapProvider
    /// The user's own key, set explicitly in Settings — nil when they
    /// haven't entered one. Use `effectiveGoogleMapsAPIKey` for actual
    /// API calls, which falls back to the bundled default.
    private(set) var googleMapsAPIKey: String?

    /// Naver's REST Geocoding API needs both of these (unlike the web
    /// app's JS SDK, which only needs a Client ID) — no bundled default
    /// for either, so `.naver` only becomes active once both are set.
    private(set) var naverClientId: String?
    private(set) var naverClientSecret: String?

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.providerDefaultsKey)
        provider = stored.flatMap(MapProvider.init(rawValue:)) ?? .free
        googleMapsAPIKey = KeychainService.load(for: Self.keychainKey)
        naverClientId = KeychainService.load(for: Self.naverClientIdKeychainKey)
        naverClientSecret = KeychainService.load(for: Self.naverClientSecretKeychainKey)
    }

    /// The user's own key when set, otherwise the app's bundled default —
    /// what every Google Maps/geocoding call site should actually use.
    var effectiveGoogleMapsAPIKey: String {
        googleMapsAPIKey ?? Self.defaultGoogleMapsAPIKey
    }

    /// A usable key (the user's own, or the bundled default) is always
    /// available once Google is selected, so this just reflects the
    /// provider choice.
    var isGoogleActive: Bool {
        provider == .google
    }

    /// Unlike Google, there's no bundled default — Naver only becomes
    /// active once the user has entered both their own Client ID and
    /// Client Secret.
    var isNaverActive: Bool {
        provider == .naver && naverClientId != nil && naverClientSecret != nil
    }

    func setProvider(_ value: MapProvider) {
        provider = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.providerDefaultsKey)
    }

    func setGoogleMapsAPIKey(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            KeychainService.save(trimmed, for: Self.keychainKey)
            googleMapsAPIKey = trimmed
        } else {
            KeychainService.delete(for: Self.keychainKey)
            googleMapsAPIKey = nil
        }
    }

    func setNaverClientId(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            KeychainService.save(trimmed, for: Self.naverClientIdKeychainKey)
            naverClientId = trimmed
        } else {
            KeychainService.delete(for: Self.naverClientIdKeychainKey)
            naverClientId = nil
        }
    }

    func setNaverClientSecret(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            KeychainService.save(trimmed, for: Self.naverClientSecretKeychainKey)
            naverClientSecret = trimmed
        } else {
            KeychainService.delete(for: Self.naverClientSecretKeychainKey)
            naverClientSecret = nil
        }
    }
}
