import Foundation
import Observation

/// Which map/geocoding provider to use. `.free` (Apple MapKit + CLGeocoder)
/// needs no API key and is the default; `.google` requires the user's own
/// Google Maps API key, entered in Settings.
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

    private(set) var provider: MapProvider
    private(set) var googleMapsAPIKey: String?

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.providerDefaultsKey)
        provider = stored.flatMap(MapProvider.init(rawValue:)) ?? .free
        googleMapsAPIKey = KeychainService.load(for: Self.keychainKey)
    }

    /// Google requires a key to actually do anything, so this is what the
    /// rest of the app should check rather than `provider` alone.
    var isGoogleActive: Bool {
        provider == .google && googleMapsAPIKey != nil
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
