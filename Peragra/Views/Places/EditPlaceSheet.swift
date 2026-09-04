import SwiftUI
import SwiftData
import PhotosUI
import Photos
import UIKit
import CoreLocation

private struct OnSitePhoto: Identifiable {
    let id = UUID()
    // The JPEG-recompressed version used for the AI call and thumbnail.
    var displayData: Data
    // The raw bytes as picked, so EXIF metadata survives — re-encoding
    // through UIImage/jpegData (which produces `displayData`) strips it.
    // Still the fallback source for location/time when `assetLocation`
    // below isn't available.
    var originalData: Data
    // Read straight from the Photos library's own record for this asset
    // when the app has photo library access — more reliable than EXIF,
    // since PhotosPicker strips location metadata from the image data it
    // hands back unless the app has that access.
    var assetLocation: CLLocationCoordinate2D?
}

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

    @State private var uploadPhotoItems: [PhotosPickerItem] = []
    @State private var showingUploadPicker = false
    @State private var isProcessingPhotos = false
    @State private var onSitePhotos: [OnSitePhoto] = []
    @State private var photoErrorMessage: String?
    @State private var photoResultMessage: String?
    // A coordinate read from a photo (its Photos library record, or EXIF)
    // since the sheet opened — applied on Save instead of immediately, so
    // Cancel still discards it like every other field here.
    @State private var pendingCoordinate: CLLocationCoordinate2D?

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

                Section {
                    Button {
                        Task {
                            // Requested here, before the picker opens, so
                            // the picked items' itemIdentifier (needed to
                            // resolve their PHAsset for accurate location)
                            // is available from this very first pick
                            // rather than only from the next one. A no-op
                            // prompt-wise once already decided; silently
                            // proceeds without it if denied.
                            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                            showingUploadPicker = true
                        }
                    } label: {
                        Label(
                            onSitePhotos.isEmpty ? "Upload On-Site Photos" : "Add More On-Site Photos",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .disabled(isProcessingPhotos)
                    .photosPicker(isPresented: $showingUploadPicker, selection: $uploadPhotoItems, matching: .images)

                    ForEach(Array(onSitePhotos.enumerated()), id: \.element.id) { index, photo in
                        HStack {
                            if let uiImage = UIImage(data: photo.displayData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Text("On-site photo \(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                onSitePhotos.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !onSitePhotos.isEmpty {
                        Button {
                            Task { await fillFromPhotos() }
                        } label: {
                            if isProcessingPhotos {
                                ProgressView()
                            } else {
                                Text("✨ Fill In From Photos")
                            }
                        }
                        .disabled(isProcessingPhotos)
                        .buttonStyle(.borderedProminent)
                    }

                    if let photoErrorMessage {
                        Text(photoErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let photoResultMessage {
                        Text(photoResultMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Add Info From a Photo")
                } footer: {
                    Text("Upload a photo of this place (a sign, a menu, ...) and AI reads it to fill in whatever's still blank above — it never overwrites what you've already entered. A location read from the photo is queued to apply when you save.")
                }
            }
            .navigationTitle("Edit Place")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: uploadPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await loadUploadPhotos(newItems)
                    uploadPhotoItems = []
                }
            }
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

        // A coordinate captured from a photo (its Photos library record,
        // or EXIF) is already a real fix — more trustworthy than geocoding
        // an address — so it's used directly instead of the
        // address-change geocode.
        if let pendingCoordinate {
            place.latitude = pendingCoordinate.latitude
            place.longitude = pendingCoordinate.longitude
            place.geocodeStatus = .located
        } else if addressChanged {
            // Only re-geocode when the address actually changed —
            // otherwise leave the existing coordinates (and
            // geocodeStatus) alone.
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

        if aiSettings.activeAPIKey != nil {
            do {
                let guessedAddress = try await AIExtractionService.guessNearestAddress(
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

    private func loadUploadPhotos(_ items: [PhotosPickerItem]) async {
        isProcessingPhotos = true
        photoErrorMessage = nil
        photoResultMessage = nil
        defer { isProcessingPhotos = false }

        for item in items {
            guard
                let originalData = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: originalData),
                let jpegData = image.jpegData(compressionQuality: 0.85)
            else {
                photoErrorMessage = "Couldn't read one of those photos."
                continue
            }

            var assetLocation: CLLocationCoordinate2D?
            if let identifier = item.itemIdentifier,
               let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject {
                assetLocation = asset.location?.coordinate
            }

            onSitePhotos.append(OnSitePhoto(displayData: jpegData, originalData: originalData, assetLocation: assetLocation))
        }
    }

    /// Sends all accumulated photos to AI in one request (so it can
    /// cross-reference them into one result) and uses whatever it finds to
    /// fill in fields that are still blank, plus appends any notes found —
    /// this only adds information, it never overwrites what's already
    /// there. Also reads a coordinate from each photo's own location data
    /// (its Photos library record, or EXIF as a fallback) — using the
    /// first one found — queued in `pendingCoordinate` for save() to
    /// apply.
    private func fillFromPhotos() async {
        guard !onSitePhotos.isEmpty else { return }
        isProcessingPhotos = true
        photoErrorMessage = nil
        photoResultMessage = nil
        defer { isProcessingPhotos = false }

        let photos = onSitePhotos
        onSitePhotos = []

        var coordinate: CLLocationCoordinate2D?
        for photo in photos {
            // The Photos library's own record for this asset, when
            // available, is more reliable than EXIF parsed from the
            // (possibly privacy-stripped) image data — prefer it.
            let location = photo.assetLocation ?? PhotoMetadata.extract(from: photo.originalData).location
            if coordinate == nil { coordinate = location }
        }

        var extracted: [AIExtractedPlace] = []
        var extractionFailureMessage: String?
        if aiSettings.activeAPIKey != nil {
            do {
                extracted = try await AIExtractionService.extractPlaces(
                    images: photos.map { (data: $0.displayData, mediaType: "image/jpeg") }
                )
            } catch {
                extractionFailureMessage = (error as? LocalizedError)?.errorDescription ?? "AI extraction failed."
            }
        }

        let found = extracted.first
        var filledSomething = false
        if let found {
            if address.trimmingCharacters(in: .whitespaces).isEmpty, let foundAddress = found.address {
                address = foundAddress
                filledSomething = true
            }
            if phone.trimmingCharacters(in: .whitespaces).isEmpty, let foundPhone = found.telephone {
                phone = foundPhone
                filledSomething = true
            }
            if let foundNotes = found.notes {
                let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                notes = trimmedNotes.isEmpty ? foundNotes : "\(trimmedNotes)\n\n\(foundNotes)"
                filledSomething = true
            }
        }

        if let coordinate {
            pendingCoordinate = coordinate
        }

        if let extractionFailureMessage {
            photoErrorMessage = extractionFailureMessage
        } else if aiSettings.activeAPIKey == nil {
            photoResultMessage = coordinate != nil
                ? "📍 Location captured from your photo — add an AI extraction API key in Settings to also read details from it."
                : "Add an AI extraction API key in Settings to read details from your photos."
        } else if filledSomething, coordinate != nil {
            photoResultMessage = "✨ Filled in details and captured a location from your photos — review before saving."
        } else if filledSomething {
            photoResultMessage = "✨ Filled in details from your photos — review before saving."
        } else if coordinate != nil {
            photoResultMessage = "📍 Captured a location from your photos — review before saving."
        } else {
            photoResultMessage = "Didn't find any new details in those photos."
        }
    }
}
