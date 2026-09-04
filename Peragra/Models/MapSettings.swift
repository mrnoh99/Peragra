import Foundation
import Observation

/// Which map/geocoding provider to use. `.free` (Apple MapKit + CLGeocoder)
/// needs no API key and is the default; `.google` uses the app's bundled
/// Google Maps key unless the user enters their own in Settings.
enum MapProvider: String {
    case free
    case google
}

/// Reactive wrapper around the map provider choice (UserDefaults — not
/// sensitive) and the Keychain-stored Google Maps API key, so SwiftUI views
/// update automatically when either changes.
@Observable
final class MapSettings {
    static let shared = MapSettings()

    private static let keychainKey = "google-maps-api-key"
    private static let providerDefaultsKey = "map-provider"

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

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.providerDefaultsKey)
        provider = stored.flatMap(MapProvider.init(rawValue:)) ?? .free
        googleMapsAPIKey = KeychainService.load(for: Self.keychainKey)
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
}
