import SwiftUI
import SwiftData

struct AddPlaceSheet: View {
    let trip: Trip
    var defaultCollection: PlaceCollection?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var instagramInput = ""
    @State private var name = ""
    @State private var category: PlaceCategory = .restaurant
    @State private var address = ""
    @State private var notes = ""
    @State private var isSaving = false

    private var normalizedInstagramURL: URL? {
        InstagramLink.normalized(instagramInput).flatMap(URL.init(string:))
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://www.instagram.com/p/...", text: $instagramInput)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !instagramInput.isEmpty && normalizedInstagramURL == nil {
                        Label("That doesn't look like an instagram.com/p/... or /reel/... link.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let url = normalizedInstagramURL {
                        InstagramEmbedView(url: url)
                            .frame(height: 420)
                            .listRowInsets(EdgeInsets())
                    }
                } header: {
                    Text("Instagram post link (optional)")
                } footer: {
                    Text("Paste the link from a post you saved. Instagram doesn't let apps read your Saved collection directly, so bring the link over and we'll show the post alongside your notes.")
                }

                Section("Place") {
                    TextField("Name (e.g. Ichiran Ramen Shibuya)", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(PlaceCategory.allCases) { option in
                            Label(option.label, systemImage: option.symbolName).tag(option)
                        }
                    }
                    TextField("Address (improves map accuracy)", text: $address)
                }

                Section("Notes") {
                    TextField("What made you save this?", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Save a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSubmit)
                    }
                }
            }
            .disabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        let place = Place(
            name: name.trimmingCharacters(in: .whitespaces),
            category: category,
            address: address.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            instagramURLString: normalizedInstagramURL?.absoluteString,
            trip: trip
        )
        modelContext.insert(place)
        if let defaultCollection {
            place.collections.append(defaultCollection)
        }

        let query = address.trimmingCharacters(in: .whitespaces).isEmpty
            ? name.trimmingCharacters(in: .whitespaces)
            : address.trimmingCharacters(in: .whitespaces)
        if let result = await GeocodingService.geocode(query: query, contextHint: trip.destination) {
            place.latitude = result.latitude
            place.longitude = result.longitude
            place.geocodeStatus = .located
        } else {
            place.geocodeStatus = .failed
        }

        isSaving = false
        dismiss()
    }
}
