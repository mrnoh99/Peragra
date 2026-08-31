import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = AISettings.shared
    @State private var apiKeyInput: String = AISettings.shared.apiKey ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-...", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text("This app has no server — AI place extraction calls Anthropic's API directly from your device using this key, stored only in this device's Keychain. Get one at console.anthropic.com. Leave blank to skip AI — the free pattern-matching extraction still works without a key.")
                }

                if settings.apiKey != nil {
                    Section {
                        Button("Remove Key", role: .destructive) {
                            settings.setAPIKey(nil)
                            apiKeyInput = ""
                        }
                    }
                }
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        settings.setAPIKey(apiKeyInput)
                        dismiss()
                    }
                }
            }
        }
    }
}
