import SwiftUI
import SwiftData

struct EditPlaceSheet: View {
    let place: Place

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: PlaceCategory
    @State private var address: String
    @State private var notes: String
    @State private var isSaving = false

    init(place: Place) {
        self.place = place
        _name = State(initialValue: place.name)
        _category = State(initialValue: place.category)
        _address = State(initialValue: place.address)
        _notes = State(initialValue: place.notes)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Place name", text: $name)
                    TextField("Address (improves map accuracy)", text: $address)
                    Picker("Category", selection: $category) {
                        ForEach(PlaceCategory.allCases) { option in
                            Label(option.label, systemImage: option.symbolName).tag(option)
                        }
                    }
                }

                Section("Notes") {
                    TextField("What made you save this?", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Edit Place")
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

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        let addressChanged = trimmedAddress != place.address

        place.name = trimmedName
        place.category = category
        place.address = trimmedAddress
        place.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only re-geocode when the address actually changed — otherwise
        // leave the existing coordinates (and geocodeStatus) alone.
        if addressChanged {
            let query = trimmedAddress.isEmpty ? trimmedName : trimmedAddress
            if let result = await GeocodingService.geocode(query: query, contextHint: place.trip?.destination) {
                place.latitude = result.latitude
                place.longitude = result.longitude
                place.geocodeStatus = .located
            } else {
                place.latitude = nil
                place.longitude = nil
                place.geocodeStatus = .failed
            }
        }

        isSaving = false
        dismiss()
    }
}
