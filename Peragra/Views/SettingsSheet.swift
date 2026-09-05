import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @Environment(\.modelContext) private var modelContext
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

    @State private var extractionLanguage: String = AISettings.shared.extractionLanguage

    @State private var mapSettings = MapSettings.shared
    @State private var mapProvider: MapProvider = MapSettings.shared.provider
    @State private var googleMapsKeyInput: String = MapSettings.shared.googleMapsAPIKey ?? ""
    @State private var naverClientIdInput: String = MapSettings.shared.naverClientId ?? ""
    @State private var naverClientSecretInput: String = MapSettings.shared.naverClientSecret ?? ""

    @State private var showingBackupExporter = false
    @State private var backupDocument: BackupDocument?
    @State private var showingRestoreImporter = false
    @State private var showingRestoreConfirm = false
    @State private var restorePendingURL: URL?
    @State private var backupMessage: String?

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

    /// `.fileImporter` hands back a security-scoped URL that's only
    /// readable while access is explicitly requested — without that
    /// bracketing, reading a file from outside the app's own sandbox
    /// (iCloud Drive, another app's Files location, ...) fails silently.
    private func performRestore() {
        guard let url = restorePendingURL else { return }
        restorePendingURL = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try BackupService.restore(from: data, context: modelContext)
            backupMessage = "Restored from backup."
        } catch {
            backupMessage = (error as? BackupService.BackupError)?.errorDescription ?? "Couldn't restore from that file."
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
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("User Guide", systemImage: "book")
                    }
                }

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

                Section {
                    Picker("Info language", selection: $extractionLanguage) {
                        ForEach(AIExtractionService.extractionLanguages, id: \.code) { language in
                            Text(language.label).tag(language.code)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("AI extracted info language")
                } footer: {
                    Text("Language for the notes AI extracts from photos and screenshots. Names, addresses, and phone numbers are always kept exactly as written. This app's own menus and buttons always stay in English.")
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
                        Text("Naver Maps").tag(MapProvider.naver)
                    }
                    .pickerStyle(.segmented)

                    if mapProvider == .google {
                        SecureField("Your own key (optional) — AIzaSy...", text: $googleMapsKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    if mapProvider == .naver {
                        TextField("Client ID", text: $naverClientIdInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Client Secret", text: $naverClientSecretInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Map provider")
                } footer: {
                    switch mapProvider {
                    case .google:
                        Text("Works right away using this app's own Google Maps key — enter your own above only if you'd rather use your own Google Cloud project's quota instead.")
                    case .naver:
                        Text("Requires your own free NAVER Cloud Platform Maps Client ID and Client Secret (Console → AI·NAVER API → Maps) — the most accurate geocoder for Korean addresses. No bundled default, unlike Google.")
                    case .free:
                        Text("Apple Maps and its geocoder need no API key and no account — this is the default.")
                    }
                }

                if mapSettings.googleMapsAPIKey != nil {
                    Section {
                        Button("Remove Google Maps Key", role: .destructive) {
                            mapSettings.setGoogleMapsAPIKey(nil)
                            googleMapsKeyInput = ""
                        }
                    }
                }

                if mapSettings.naverClientId != nil || mapSettings.naverClientSecret != nil {
                    Section {
                        Button("Remove Naver Maps Credentials", role: .destructive) {
                            mapSettings.setNaverClientId(nil)
                            mapSettings.setNaverClientSecret(nil)
                            naverClientIdInput = ""
                            naverClientSecretInput = ""
                        }
                    }
                }

                Section {
                    Button("Back Up Data") {
                        do {
                            backupDocument = BackupDocument(data: try BackupService.exportData(context: modelContext))
                            showingBackupExporter = true
                        } catch {
                            backupMessage = "Couldn't prepare a backup."
                        }
                    }
                    .fileExporter(
                        isPresented: $showingBackupExporter,
                        document: backupDocument,
                        contentType: .json,
                        defaultFilename: BackupService.filename()
                    ) { result in
                        switch result {
                        case .success: backupMessage = "Backup saved."
                        case .failure: backupMessage = "Couldn't save the backup."
                        }
                    }

                    Button("Restore from Backup", role: .destructive) {
                        showingRestoreImporter = true
                    }
                    .fileImporter(isPresented: $showingRestoreImporter, allowedContentTypes: [.json]) { result in
                        switch result {
                        case .success(let url):
                            restorePendingURL = url
                            showingRestoreConfirm = true
                        case .failure:
                            backupMessage = "Couldn't read that file."
                        }
                    }

                    if let backupMessage {
                        Text(backupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Back up every board and place to a file you choose, or restore from one — restoring replaces everything currently in the app.")
                }
            }
            .confirmationDialog(
                "Replace all boards and places with this backup?",
                isPresented: $showingRestoreConfirm,
                titleVisibility: .visible
            ) {
                Button("Restore", role: .destructive) { performRestore() }
                Button("Cancel", role: .cancel) { restorePendingURL = nil }
            } message: {
                Text("This can't be undone.")
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

                        settings.setExtractionLanguage(extractionLanguage)

                        mapSettings.setProvider(mapProvider)
                        mapSettings.setGoogleMapsAPIKey(googleMapsKeyInput)
                        mapSettings.setNaverClientId(naverClientIdInput)
                        mapSettings.setNaverClientSecret(naverClientSecretInput)
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
