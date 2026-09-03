import Foundation
import Observation

/// Reactive wrapper around the Keychain-stored AI extraction API key and
/// the chosen model (UserDefaults — not sensitive) for the
/// factchat-cloud.mindlogic.ai gateway — see AIExtractionService — so
/// SwiftUI views update automatically when either changes.
@Observable
final class AISettings {
    static let shared = AISettings()

    private static let keychainKey = "anthropic-api-key"
    private static let modelDefaultsKey = "ai-extraction-model"

    private(set) var apiKey: String?
    private(set) var model: String

    private init() {
        apiKey = KeychainService.load(for: Self.keychainKey)
        model = UserDefaults.standard.string(forKey: Self.modelDefaultsKey) ?? GatewayModels.defaultModel
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

    func setModel(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        model = trimmed.isEmpty ? GatewayModels.defaultModel : trimmed
        UserDefaults.standard.set(model, forKey: Self.modelDefaultsKey)
    }
}
