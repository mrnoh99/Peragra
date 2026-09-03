import SwiftUI

struct SettingsSheet: View {
    // Explicit, so this view's access level never depends on Swift's
    // synthesized-memberwise-init rules (bit us once already on
    // AddPlaceSheet) — every stored property below already has its own
    // default value, so there's nothing else to assign here.
    init() {}

    private static let customModelTag = "__custom__"

    private static func initialModelSelection() -> String {
        let current = AISettings.shared.model
        return GatewayModels.all.contains(where: { $0.id == current }) ? current : customModelTag
    }

    private static func initialCustomModelInput() -> String {
        let current = AISettings.shared.model
        return GatewayModels.all.contains(where: { $0.id == current }) ? "" : current
    }

    @Environment(\.dismiss) private var dismiss
    @State private var settings = AISettings.shared
    @State private var apiKeyInput: String = AISettings.shared.apiKey ?? ""
    @State private var modelSelection: String = SettingsSheet.initialModelSelection()
    @State private var customModelInput: String = SettingsSheet.initialCustomModelInput()

    @State private var mapSettings = MapSettings.shared
    @State private var mapProvider: MapProvider = MapSettings.shared.provider
    @State private var googleMapsKeyInput: String = MapSettings.shared.googleMapsAPIKey ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("API key", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("Model", selection: $modelSelection) {
                        ForEach(GatewayModels.all) { model in
                            Text(model.label).tag(model.id)
                        }
                        Text("Custom…").tag(Self.customModelTag)
                    }

                    if modelSelection == Self.customModelTag {
                        TextField("model-id", text: $customModelInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("AI extraction API key")
                } footer: {
                    Text("This app has no server — AI place extraction calls the gateway at factchat-cloud.mindlogic.ai directly from your device using this key, stored only in this device's Keychain. This is a third-party gateway, not Anthropic's own API — your caption/screenshot data passes through it. The model list is from the gateway's own catalog — pick \"Custom…\" for any other ID it supports. Leave the key blank to skip AI — the free pattern-matching extraction still works without one.")
                }

                if settings.apiKey != nil {
                    Section {
                        Button("Remove Key", role: .destructive) {
                            settings.setAPIKey(nil)
                            apiKeyInput = ""
                        }
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
                        settings.setAPIKey(apiKeyInput)
                        let chosenModel = modelSelection == Self.customModelTag ? customModelInput : modelSelection
                        settings.setModel(chosenModel)
                        mapSettings.setProvider(mapProvider)
                        mapSettings.setGoogleMapsAPIKey(googleMapsKeyInput)
                        dismiss()
                    }
                }
            }
        }
    }
}
