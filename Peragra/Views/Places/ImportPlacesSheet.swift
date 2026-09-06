import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The receiving side of "share places": paste the text from someone's
/// "Copy as Text" share, or pick the file from their "Share as File",
/// parse it deterministically (no AI involved — the payload is already
/// structured), then review/deselect before adding to this board. Each
/// added place is geocoded fresh, since a coordinate from the sender's
/// board means nothing on this one.
struct ImportPlacesSheet: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var pastedText = ""
    @State private var rows: [ReviewRow]?
    @State private var parseError: String?
    @State private var isSaving = false
    @State private var isImportingFile = false

    struct ReviewRow: Identifiable {
        let id = UUID()
        var selected = true
        var name: String
        var category: PlaceCategory
        var address: String
        var phone: String?
        var notes: String
        var linkURL: String?
    }

    var body: some View {
        NavigationStack {
            Group {
                if let rows {
                    reviewList(rows)
                } else {
                    pasteForm
                }
            }
            .navigationTitle("Import Shared Places")
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
    }

    private var pasteForm: some View {
        Form {
            Section {
                Text("Paste text from someone's \"Copy as Text\" share, or choose the .json file from their \"Share as File\" share.")
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
                Button("Parse Text") { tryParse(pastedText) }
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Choose File…") { isImportingFile = true }
            }
        }
    }

    private func reviewList(_ rows: [ReviewRow]) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        reviewRow(row, index: index)
                    }
                } header: {
                    HStack {
                        Text("\(rows.filter(\.selected).count) of \(rows.count) selected")
                        Spacer()
                        Button(rows.allSatisfy(\.selected) ? "Deselect All" : "Select All") {
                            toggleAll()
                        }
                        .font(.caption)
                    }
                }
            }
            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    Text("Adding & Locating…")
                } else {
                    let count = rows.filter(\.selected).count
                    Text("Add \(count) Place\(count == 1 ? "" : "s")")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || rows.allSatisfy { !$0.selected })
            .padding()
        }
    }

    private func reviewRow(_ row: ReviewRow, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                self.rows?[index].selected.toggle()
            } label: {
                Image(systemName: row.selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.selected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: Binding(
                    get: { row.name },
                    set: { self.rows?[index].name = $0 }
                ))
                .font(.subheadline.weight(.medium))

                Picker("Category", selection: Binding(
                    get: { row.category },
                    set: { self.rows?[index].category = $0 }
                )) {
                    ForEach(PlaceCategory.allCases) { category in
                        Text(category.label).tag(category)
                    }
                }
                .font(.caption)
                .pickerStyle(.menu)

                TextField("Address", text: Binding(
                    get: { row.address },
                    set: { self.rows?[index].address = $0 }
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func tryParse(_ text: String) {
        guard let shared = SharePlaces.parse(text) else {
            parseError = "That doesn't look like a Peragra places share — paste the text exactly as copied, or choose the .json file."
            rows = nil
            return
        }
        parseError = nil
        rows = shared.map { place in
            ReviewRow(
                name: place.name,
                category: PlaceCategory(rawValue: place.category) ?? .other,
                address: place.address,
                phone: place.phone,
                notes: place.notes,
                linkURL: place.linkURL
            )
        }
    }

    private func toggleAll() {
        guard let rows else { return }
        let allSelected = rows.allSatisfy(\.selected)
        self.rows = rows.map { row in
            var row = row
            row.selected = !allSelected
            return row
        }
    }

    private func save() async {
        guard let rows else { return }
        let selected = rows.filter(\.selected)
        guard !selected.isEmpty else { return }
        isSaving = true

        for row in selected {
            let place = Place(
                name: row.name.trimmingCharacters(in: .whitespaces),
                category: row.category,
                address: row.address.trimmingCharacters(in: .whitespaces),
                phone: row.phone?.trimmingCharacters(in: .whitespaces),
                notes: row.notes,
                instagramURLString: nil,
                linkURLString: row.linkURL,
                trip: trip
            )
            modelContext.insert(place)

            let siblingPlaces = trip.places.map {
                MapProviderPolicy.PlaceLike(latitude: $0.latitude, longitude: $0.longitude, name: $0.name, address: $0.address)
            }
            if let result = await GeocodingService.geocode(name: place.name, address: place.address, contextHint: trip.destination, siblingPlaces: siblingPlaces) {
                place.latitude = result.latitude
                place.longitude = result.longitude
                place.geocodeStatus = .located
            } else {
                place.geocodeStatus = .failed
            }
            place.syncCountryList(context: modelContext)
        }

        try? modelContext.save()
        isSaving = false
        dismiss()
    }
}
