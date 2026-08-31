import Observation

/// Reactive wrapper around the Keychain-stored Anthropic API key, so
/// SwiftUI views update automatically when it changes.
@Observable
final class AISettings {
    static let shared = AISettings()

    private(set) var apiKey: String?

    private init() {
        apiKey = KeychainService.load()
    }

    func setAPIKey(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            KeychainService.save(trimmed)
            apiKey = trimmed
        } else {
            KeychainService.delete()
            apiKey = nil
        }
    }
}
