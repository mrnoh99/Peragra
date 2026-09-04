import Foundation
import Observation

enum AIProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openai
    case gemini
    case perplexity
    // Listed last — it's the fallback, not the first thing to reach for.
    case gateway

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gateway: return "Gateway (default)"
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        case .perplexity: return "Perplexity"
        }
    }
}

/// Reactive wrapper around the Keychain-stored AI extraction API keys and
/// chosen models (UserDefaults — not sensitive) for every provider AI
/// extraction can use — see AIExtractionService — so SwiftUI views update
/// automatically when any of them changes.
///
/// The default provider ("gateway") routes through the
/// factchat-cloud.mindlogic.ai gateway. The others call
/// Anthropic/OpenAI/Google/Perplexity's own API directly with the user's
/// own key for that provider, bypassing the gateway entirely — each kept
/// under its own Keychain/UserDefaults key so switching providers never
/// loses what was entered for another one.
@Observable
final class AISettings {
    static let shared = AISettings()

    private static let providerDefaultsKey = "ai-extraction-provider"

    private static let gatewayKeychainKey = "anthropic-api-key"
    private static let gatewayModelDefaultsKey = "ai-extraction-model"
    private static let anthropicKeychainKey = "ai-anthropic-api-key"
    private static let anthropicModelDefaultsKey = "ai-anthropic-model"
    private static let openaiKeychainKey = "ai-openai-api-key"
    private static let openaiModelDefaultsKey = "ai-openai-model"
    private static let geminiKeychainKey = "ai-gemini-api-key"
    private static let geminiModelDefaultsKey = "ai-gemini-model"
    private static let perplexityKeychainKey = "ai-perplexity-api-key"
    private static let perplexityModelDefaultsKey = "ai-perplexity-model"

    private(set) var provider: AIProvider

    private(set) var apiKey: String?
    private(set) var model: String
    private(set) var anthropicAPIKey: String?
    private(set) var anthropicModel: String
    private(set) var openaiAPIKey: String?
    private(set) var openaiModel: String
    private(set) var geminiAPIKey: String?
    private(set) var geminiModel: String
    private(set) var perplexityAPIKey: String?
    private(set) var perplexityModel: String

    /// The key for whichever provider is currently active, or nil if unset.
    var activeAPIKey: String? {
        switch provider {
        case .gateway: return apiKey
        case .anthropic: return anthropicAPIKey
        case .openai: return openaiAPIKey
        case .gemini: return geminiAPIKey
        case .perplexity: return perplexityAPIKey
        }
    }

    private init() {
        provider = UserDefaults.standard.string(forKey: Self.providerDefaultsKey)
            .flatMap(AIProvider.init(rawValue:)) ?? .gateway

        apiKey = KeychainService.load(for: Self.gatewayKeychainKey)
        model = UserDefaults.standard.string(forKey: Self.gatewayModelDefaultsKey) ?? GatewayModels.defaultModel

        anthropicAPIKey = KeychainService.load(for: Self.anthropicKeychainKey)
        anthropicModel = UserDefaults.standard.string(forKey: Self.anthropicModelDefaultsKey)
            ?? AIExtractionService.defaultAnthropicModel

        openaiAPIKey = KeychainService.load(for: Self.openaiKeychainKey)
        openaiModel = UserDefaults.standard.string(forKey: Self.openaiModelDefaultsKey)
            ?? AIExtractionService.defaultOpenAIModel

        geminiAPIKey = KeychainService.load(for: Self.geminiKeychainKey)
        geminiModel = UserDefaults.standard.string(forKey: Self.geminiModelDefaultsKey)
            ?? AIExtractionService.defaultGeminiModel

        perplexityAPIKey = KeychainService.load(for: Self.perplexityKeychainKey)
        perplexityModel = UserDefaults.standard.string(forKey: Self.perplexityModelDefaultsKey)
            ?? AIExtractionService.defaultPerplexityModel
    }

    func setProvider(_ value: AIProvider) {
        provider = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.providerDefaultsKey)
    }

    func setAPIKey(_ value: String?) {
        apiKey = Self.save(value, keychainKey: Self.gatewayKeychainKey)
    }

    func setModel(_ value: String) {
        model = Self.saveModel(value, default: GatewayModels.defaultModel, defaultsKey: Self.gatewayModelDefaultsKey)
    }

    func setAnthropicAPIKey(_ value: String?) {
        anthropicAPIKey = Self.save(value, keychainKey: Self.anthropicKeychainKey)
    }

    func setAnthropicModel(_ value: String) {
        anthropicModel = Self.saveModel(
            value, default: AIExtractionService.defaultAnthropicModel, defaultsKey: Self.anthropicModelDefaultsKey
        )
    }

    func setOpenaiAPIKey(_ value: String?) {
        openaiAPIKey = Self.save(value, keychainKey: Self.openaiKeychainKey)
    }

    func setOpenaiModel(_ value: String) {
        openaiModel = Self.saveModel(
            value, default: AIExtractionService.defaultOpenAIModel, defaultsKey: Self.openaiModelDefaultsKey
        )
    }

    func setGeminiAPIKey(_ value: String?) {
        geminiAPIKey = Self.save(value, keychainKey: Self.geminiKeychainKey)
    }

    func setGeminiModel(_ value: String) {
        geminiModel = Self.saveModel(
            value, default: AIExtractionService.defaultGeminiModel, defaultsKey: Self.geminiModelDefaultsKey
        )
    }

    func setPerplexityAPIKey(_ value: String?) {
        perplexityAPIKey = Self.save(value, keychainKey: Self.perplexityKeychainKey)
    }

    func setPerplexityModel(_ value: String) {
        perplexityModel = Self.saveModel(
            value, default: AIExtractionService.defaultPerplexityModel, defaultsKey: Self.perplexityModelDefaultsKey
        )
    }

    private static func save(_ value: String?, keychainKey: String) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            KeychainService.save(trimmed, for: keychainKey)
            return trimmed
        } else {
            KeychainService.delete(for: keychainKey)
            return nil
        }
    }

    private static func saveModel(_ value: String, default defaultValue: String, defaultsKey: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = trimmed.isEmpty ? defaultValue : trimmed
        UserDefaults.standard.set(result, forKey: defaultsKey)
        return result
    }
}
