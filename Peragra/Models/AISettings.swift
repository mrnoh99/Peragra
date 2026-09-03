import Observation

/// Reactive wrapper around the Keychain-stored Anthropic API key, so
/// SwiftUI views update automatically when it changes.
@Observable
final class AISettings {
    static let shared = AISettings()

    private static let keychainKey = "anthropic-api-key"

    private(set) var apiKey: String?

    private init() {
        apiKey = KeychainService.load(for: Self.keychainKey)
    }

    func setAPIKey(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            KeychainService.save(trimmed, for: Self.keychainKey)
            apiKey = trimmed
        } else {
            KeychainService.delete(for: Self.keychainKey)
            apiKey = nil
        }
    }
}
