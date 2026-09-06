import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The receiving side of "share a whole board": paste the text from
/// someone's "Copy as Text" board export, or pick the file from their
/// "Share as File" export, then add it as a brand-new board — unlike
/// restoring a whole-app backup, which replaces everything, this can
/// never collide with or overwrite what's already here.
struct ImportBoardSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var pastedText = ""
    @State private var preview: BackupService.BackupData?
    @State private var parseError: String?
    @State private var isImportingFile = false
    @State private var importFailureMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let preview {
                    previewList(preview)
                } else {
                    pasteForm
                }
            }
            .navigationTitle("Import a Shared Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                parseError = "Couldn't read that file."
                return
            }
            pastedText = text
            tryParse(text)
        }
        // Parses as soon as something's pasted in, rather than making the
        // person also find and tap a separate "Parse Text" button — a
        // paste delivers the whole share text in one change event, so this
        // moves straight from the paste box to the board preview/confirm
        // screen on its own. Guarded on non-empty so the error message
        // doesn't flash before anything's been pasted at all.
        .onChange(of: pastedText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                parseError = nil
                preview = nil
                return
            }
            tryParse(newValue)
        }
        .alert("Couldn't Add This Board", isPresented: Binding(
            get: { importFailureMessage != nil },
            set: { if !$0 { importFailureMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(importFailureMessage ?? "")
        }
    }

    private var pasteForm: some View {
        Form {
            Section {
                Text("Paste text from someone's \"Copy as Text\" board share, or choose the .json file from their \"Share as File\" share.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $pastedText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 140)
                if let parseError {
                    Text(parseError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Button("Choose File…") { isImportingFile = true }
            }
        }
    }

    private func previewList(_ preview: BackupService.BackupData) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(preview.trips, id: \.id) { trip in
                        let count = preview.places.filter { $0.tripId == trip.id }.count
                        HStack(spacing: 8) {
                            Text(trip.coverEmoji).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.name).font(.subheadline.weight(.medium))
                                Text("\(trip.destination) · \(count) place\(count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(preview.trips.count == 1 ? "Add this board?" : "Add these \(preview.trips.count) boards?")
                }
            }
            Button("Add \(preview.trips.count == 1 ? "Board" : "Boards")") {
                importBoard(preview)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func tryParse(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            parseError = "That doesn't look like a Peragra board export."
            preview = nil
            return
        }
        do {
            let decoded = try JSONDecoder().decode(BackupService.BackupData.self, from: data)
            guard decoded.app == "peragra", !decoded.trips.isEmpty else {
                parseError = "That doesn't look like a Peragra board export."
                preview = nil
                return
            }
            parseError = nil
            preview = decoded
        } catch {
            // Printed rather than shown, since the person can't act on a
            // raw decoding error — but it's worth having in the console
            // the next time an export/import schema mismatch like this
            // slips through.
            print("ImportBoardSheet: failed to decode pasted board — \(error)")
            parseError = "That doesn't look like a Peragra board export."
            preview = nil
        }
    }

    private func importBoard(_ preview: BackupService.BackupData) {
        do {
            try BackupService.importBoard(preview, context: modelContext)
            dismiss()
        } catch {
            importFailureMessage = "Something went wrong while adding this board. Nothing was added — try again."
        }
    }
}
