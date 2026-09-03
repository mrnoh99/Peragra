import SwiftUI

struct SettingsSheet: View {
    // Explicit, so this view's access level never depends on Swift's
    // synthesized-memberwise-init rules (bit us once already on
    // AddPlaceSheet) — every stored property below already has its own
    // default value, so there's nothing else to assign here.
    init() {}

    fileprivate static let customModelTag = "__custom__"

    fileprivate static let anthropicModels: [GatewayModels.Model] = [
        GatewayModels.Model(id: "claude-sonnet-5", label: "Claude Sonnet 5"),
        GatewayModels.Model(id: "claude-opus-5", label: "Claude Opus 5"),
    ]

    private static func initialModelSelection(current: String, known: [GatewayModels.Model]) -> String {
        known.contains(where: { $0.id == current }) ? current : customModelTag
    }

    private static func initialCustomModelInput(current: String, known: [GatewayModels.Model]) -> String {
        known.contains(where: { $0.id == current }) ? "" : current
    }

    @Environment(\.dismiss) private var dismiss
    @State private var settings = AISettings.shared
    @State private var provider: AIProvider = AISettings.shared.provider

    @State private var gatewayKeyInput: String = AISettings.shared.apiKey ?? ""
    @State private var gatewayModelSelection: String = SettingsSheet.initialModelSelection(
        current: AISettings.shared.model, known: GatewayModels.all
    )
    @State private var gatewayCustomModelInput: String = SettingsSheet.initialCustomModelInput(
        current: AISettings.shared.model, known: GatewayModels.all
    )

    @State private var anthropicKeyInput: String = AISettings.shared.anthropicAPIKey ?? ""
    @State private var anthropicModelSelection: String = SettingsSheet.initialModelSelection(
        current: AISettings.shared.anthropicModel, known: SettingsSheet.anthropicModels
    )
    @State private var anthropicCustomModelInput: String = SettingsSheet.initialCustomModelInput(
        current: AISettings.shared.anthropicModel, known: SettingsSheet.anthropicModels
    )

    @State private var openaiKeyInput: String = AISettings.shared.openaiAPIKey ?? ""
    @State private var openaiModelInput: String = AISettings.shared.openaiModel

    @State private var geminiKeyInput: String = AISettings.shared.geminiAPIKey ?? ""
    @State private var geminiModelInput: String = AISettings.shared.geminiModel

    @State private var perplexityKeyInput: String = AISettings.shared.perplexityAPIKey ?? ""
    @State private var perplexityModelInput: String = AISettings.shared.perplexityModel

    @State private var mapSettings = MapSettings.shared
    @State private var mapProvider: MapProvider = MapSettings.shared.provider
    @State private var googleMapsKeyInput: String = MapSettings.shared.googleMapsAPIKey ?? ""

    /// Whether the *currently selected* provider (which may not be saved
    /// yet) already has a stored key, to decide whether "Remove Key" shows.
    private var currentProviderHasStoredKey: Bool {
        switch provider {
        case .gateway: return settings.apiKey != nil
        case .anthropic: return settings.anthropicAPIKey != nil
        case .openai: return settings.openaiAPIKey != nil
        case .gemini: return settings.geminiAPIKey != nil
        case .perplexity: return settings.perplexityAPIKey != nil
        }
    }

    private func removeCurrentProviderKey() {
        switch provider {
        case .gateway:
            settings.setAPIKey(nil)
            gatewayKeyInput = ""
        case .anthropic:
            settings.setAnthropicAPIKey(nil)
            anthropicKeyInput = ""
        case .openai:
            settings.setOpenaiAPIKey(nil)
            openaiKeyInput = ""
        case .gemini:
            settings.setGeminiAPIKey(nil)
            geminiKeyInput = ""
        case .perplexity:
            settings.setPerplexityAPIKey(nil)
            perplexityKeyInput = ""
        }
    }

    private var providerFooterText: String {
        switch provider {
        case .gateway:
            return "AI place extraction calls the gateway at factchat-cloud.mindlogic.ai directly from this device using this key, stored only in this device's Keychain. This is a third-party gateway, not any provider's own API — your caption/screenshot data passes through it. The model list is from the gateway's own catalog — pick \"Custom…\" for any other ID it supports."
        case .anthropic:
            return "Calls Anthropic's own API (api.anthropic.com) directly from this device with your own Anthropic API key — bypasses the gateway entirely."
        case .openai:
            return "Calls OpenAI's own API (api.openai.com) directly from this device with your own OpenAI API key — bypasses the gateway entirely. Needs a vision-capable model (the default, gpt-4o, supports screenshots)."
        case .gemini:
            return "Calls Google's Gemini API directly from this device with your own Gemini API key (from Google AI Studio) — bypasses the gateway entirely."
        case .perplexity:
            return "Calls Perplexity's own API directly from this device with your own Perplexity API key. Perplexity has no vision support, so screenshot extraction is unavailable while it's selected — caption-text extraction still works."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $provider) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.menu)

                    switch provider {
                    case .gateway:
                        ModelPickerProviderFields(
                            placeholder: "API key",
                            knownModels: GatewayModels.all,
                            keyInput: $gatewayKeyInput,
                            modelSelection: $gatewayModelSelection,
                            customModelInput: $gatewayCustomModelInput
                        )
                    case .anthropic:
                        ModelPickerProviderFields(
                            placeholder: "sk-ant-...",
                            knownModels: Self.anthropicModels,
                            keyInput: $anthropicKeyInput,
                            modelSelection: $anthropicModelSelection,
                            customModelInput: $anthropicCustomModelInput
                        )
                    case .openai:
                        SimpleProviderFields(placeholder: "sk-...", keyInput: $openaiKeyInput, modelInput: $openaiModelInput)
                    case .gemini:
                        SimpleProviderFields(placeholder: "AIzaSy...", keyInput: $geminiKeyInput, modelInput: $geminiModelInput)
                    case .perplexity:
                        SimpleProviderFields(placeholder: "pplx-...", keyInput: $perplexityKeyInput, modelInput: $perplexityModelInput)
                    }
                } header: {
                    Text("AI place extraction")
                } footer: {
                    Text(providerFooterText + " Leave the key blank to skip AI — the free pattern-matching extraction still works without one.")
                }

                if currentProviderHasStoredKey {
                    Section {
                        Button("Remove Key", role: .destructive) { removeCurrentProviderKey() }
                    }
                }

                Section {
                    Picker("Map provider", selection: $mapProvider) {
                        Text("Free (Apple Maps)").tag(MapProvider.free)
                        Text("Google Maps").tag(MapProvider.google)
                    }
                    .pickerStyle(.segmented)

                    if mapProvider == .google {
                        SecureField("AIzaSy...", text: $googleMapsKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Map provider")
                } footer: {
                    Text(mapProvider == .google
                        ? "Requires your own Google Maps API key (with the Maps JavaScript and Geocoding APIs enabled) from a Google Cloud project with billing set up — Google's free monthly credit covers light personal use. The map and address lookups call Google's APIs directly from this device."
                        : "Apple Maps and its geocoder need no API key and no account — this is the default.")
                }

                if mapSettings.googleMapsAPIKey != nil {
                    Section {
                        Button("Remove Google Maps Key", role: .destructive) {
                            mapSettings.setGoogleMapsAPIKey(nil)
                            googleMapsKeyInput = ""
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        settings.setProvider(provider)

                        settings.setAPIKey(gatewayKeyInput)
                        settings.setModel(gatewayModelSelection == Self.customModelTag ? gatewayCustomModelInput : gatewayModelSelection)

                        settings.setAnthropicAPIKey(anthropicKeyInput)
                        settings.setAnthropicModel(anthropicModelSelection == Self.customModelTag ? anthropicCustomModelInput : anthropicModelSelection)

                        settings.setOpenaiAPIKey(openaiKeyInput)
                        settings.setOpenaiModel(openaiModelInput)

                        settings.setGeminiAPIKey(geminiKeyInput)
                        settings.setGeminiModel(geminiModelInput)

                        settings.setPerplexityAPIKey(perplexityKeyInput)
                        settings.setPerplexityModel(perplexityModelInput)

                        mapSettings.setProvider(mapProvider)
                        mapSettings.setGoogleMapsAPIKey(googleMapsKeyInput)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// A provider whose model is picked from a known list, with a "Custom…"
/// escape hatch for any other ID the provider supports (used by the
/// gateway and Anthropic).
private struct ModelPickerProviderFields: View {
    let placeholder: String
    let knownModels: [GatewayModels.Model]
    @Binding var keyInput: String
    @Binding var modelSelection: String
    @Binding var customModelInput: String

    var body: some View {
        SecureField(placeholder, text: $keyInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        Picker("Model", selection: $modelSelection) {
            ForEach(knownModels) { model in
                Text(model.label).tag(model.id)
            }
            Text("Custom…").tag(SettingsSheet.customModelTag)
        }
        if modelSelection == SettingsSheet.customModelTag {
            TextField("model-id", text: $customModelInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

/// A provider with no bundled model catalog here — just a free-text model
/// ID (used by OpenAI, Gemini, and Perplexity).
private struct SimpleProviderFields: View {
    let placeholder: String
    @Binding var keyInput: String
    @Binding var modelInput: String

    var body: some View {
        SecureField(placeholder, text: $keyInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        TextField("model-id", text: $modelInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}
