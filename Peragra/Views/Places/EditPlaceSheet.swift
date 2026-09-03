import SwiftUI
import SwiftData

struct EditPlaceSheet: View {
    let place: Place

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var category: PlaceCategory
    @State private var address: String
    @State private var phone: String
    @State private var notes: String
    @State private var isSaving = false

    private var aiSettings: AISettings { AISettings.shared }

    init(place: Place) {
        self.place = place
        _name = State(initialValue: place.name)
        _category = State(initialValue: place.category)
        _address = State(initialValue: place.address)
        _phone = State(initialValue: place.phone ?? "")
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
                    TextField("Phone (optional)", text: $phone)
                        .keyboardType(.phonePad)
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
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressChanged = trimmedAddress != place.address

        place.name = trimmedName
        place.category = category
        place.address = trimmedAddress
        place.phone = trimmedPhone.isEmpty ? nil : trimmedPhone
        place.notes = trimmedNotes

        // Only re-geocode when the address actually changed — otherwise
        // leave the existing coordinates (and geocodeStatus) alone.
        if addressChanged {
            await geocodeAndStore(
                name: trimmedName,
                address: trimmedAddress,
                phone: trimmedPhone,
                notes: trimmedNotes
            )
        }

        // Explicit rather than relying on SwiftData's autosave timing —
        // views elsewhere (like TripDetailView's @Query-backed Export
        // button) need this committed to be sure they see it as soon as
        // this sheet dismisses, not whenever autosave next happens to run.
        try? modelContext.save()

        isSaving = false
        dismiss()
    }

    /// Geocodes the place's own address/name; if that fails and an AI API
    /// key is configured, falls back to asking AI for its best guess at
    /// the nearest plausible real address (using everything known about
    /// the place as context) and geocodes that instead — marked
    /// `.estimated` rather than `.located` so the UI can flag it as
    /// approximate. Only `.failed` once both the real geocode and the AI
    /// estimate come up empty (or there's no API key to try at all).
    private func geocodeAndStore(name: String, address: String, phone: String, notes: String) async {
        let query = address.isEmpty ? name : address
        let destination = place.trip?.destination

        if let result = await GeocodingService.geocode(query: query, contextHint: destination) {
            place.latitude = result.latitude
            place.longitude = result.longitude
            place.geocodeStatus = .located
            return
        }

        if let apiKey = aiSettings.apiKey {
            do {
                let guessedAddress = try await AIExtractionService.guessNearestAddress(
                    apiKey: apiKey,
                    destination: destination ?? "",
                    name: name,
                    address: address.isEmpty ? nil : address,
                    telephone: phone.isEmpty ? nil : phone,
                    notes: notes.isEmpty ? nil : notes
                )
                if let guessedAddress,
                   let estimate = await GeocodingService.geocode(query: guessedAddress, contextHint: destination) {
                    place.latitude = estimate.latitude
                    place.longitude = estimate.longitude
                    place.geocodeStatus = .estimated
                    return
                }
            } catch {
                // fall through to .failed below
            }
        }

        place.latitude = nil
        place.longitude = nil
        place.geocodeStatus = .failed
    }
}
