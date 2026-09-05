import SwiftUI
import SwiftData
import PhotosUI
import Photos
import UIKit
import CoreLocation

private struct OnSitePhoto: Identifiable {
    enum Source {
        case camera
        case upload
    }

    let id = UUID()
    // The JPEG-recompressed version used for the AI call and thumbnail.
    var displayData: Data
    // The raw bytes as picked, so EXIF metadata survives — re-encoding
    // through UIImage/jpegData (which produces `displayData`) strips it.
    // Still the fallback source for location/time when `assetLocation`
    // below isn't available. Empty for a camera capture, which has no
    // asset/EXIF data of its own — that path uses a live GPS fix instead.
    var originalData: Data
    // Read straight from the Photos library's own record for this asset
    // when the app has photo library access — more reliable than EXIF,
    // since PhotosPicker strips location metadata from the image data it
    // hands back unless the app has that access. Only meaningful for
    // `.upload` photos.
    var assetLocation: CLLocationCoordinate2D?
    var source: Source = .upload
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
    @State private var showingCamera = false
    @State private var isProcessingPhotos = false
    @State private var onSitePhotos: [OnSitePhoto] = []
    @State private var photoErrorMessage: String?
    @State private var photoResultMessage: String?
    // A coordinate read from a photo (its Photos library record, or EXIF)
    // since the sheet opened — applied on Save instead of immediately, so
    // Cancel still discards it like every other field here.
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    // Real nearby places offered as pickable candidates once a photo's
    // location is known — picking one is an explicit choice, so unlike
    // the AI/reverse-geocode fallbacks above it does overwrite
    // name/address/phone/category with the selection.
    @State private var nearbyCandidates: [NearbyPlacesService.Candidate] = []

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
                        // Opens the picker immediately — Photos access
                        // (needed to resolve a picked item's PHAsset for
                        // accurate location) is requested separately, in
                        // the background, so it never delays this tap.
                        showingUploadPicker = true
                    } label: {
                        Label(
                            onSitePhotos.isEmpty ? "Upload On-Site Photos" : "Add More On-Site Photos",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .disabled(isProcessingPhotos)
                    .photosPicker(isPresented: $showingUploadPicker, selection: $uploadPhotoItems, matching: .images)

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label(
                                onSitePhotos.isEmpty ? "Take Photo Here" : "Take Another Photo",
                                systemImage: "camera"
                            )
                        }
                        .disabled(isProcessingPhotos)
                        .fullScreenCover(isPresented: $showingCamera) {
                            CameraCaptureView(onCapture: handleCameraCapture)
                                .ignoresSafeArea()
                        }
                    }

                    ForEach(Array(onSitePhotos.enumerated()), id: \.element.id) { index, photo in
                        HStack {
                            if let uiImage = UIImage(data: photo.displayData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Text(photo.source == .camera ? "📷 Photo \(index + 1)" : "📌 On-site photo \(index + 1)")
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
                    Text("Take a photo here or upload one of this place (a sign, a menu, ...) and AI reads it to fill in whatever's still blank above — it never overwrites what you've already entered. A location read from the photo (or your current location) is queued to apply when you save.")
                }

                if !nearbyCandidates.isEmpty {
                    Section {
                        ForEach(nearbyCandidates) { candidate in
                            Button {
                                applyNearbyCandidate(candidate)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name)
                                        .foregroundStyle(.primary)
                                    if let address = candidate.address {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Button("Dismiss", role: .cancel) { nearbyCandidates = [] }
                    } header: {
                        Text("📍 Is it one of these nearby places?")
                    }
                }
            }
            .navigationTitle("Edit Place")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Requested once, up front, rather than gating the Upload
                // button's tap on it — so tapping Upload opens the picker
                // immediately. A no-op prompt-wise once already decided;
                // items picked before this resolves just fall back to EXIF
                // for location instead of the more reliable PHAsset lookup.
                _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
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

    /// Picking a nearby candidate is an explicit choice, so unlike the
    /// AI/reverse-geocode fallbacks above it does overwrite
    /// name/address/phone/category — including with the candidate's own
    /// (more precise) coordinate rather than the photo's raw location.
    private func applyNearbyCandidate(_ candidate: NearbyPlacesService.Candidate) {
        name = candidate.name
        address = candidate.address ?? ""
        if let candidatePhone = candidate.phone { phone = candidatePhone }
        category = candidate.category
        pendingCoordinate = CLLocationCoordinate2D(latitude: candidate.latitude, longitude: candidate.longitude)
        nearbyCandidates = []
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

            onSitePhotos.append(OnSitePhoto(displayData: jpegData, originalData: originalData, assetLocation: assetLocation, source: .upload))
        }
    }

    private func handleCameraCapture(_ data: Data?) {
        showingCamera = false
        guard let data else { return }
        onSitePhotos.append(OnSitePhoto(displayData: data, originalData: Data(), assetLocation: nil, source: .camera))
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
        nearbyCandidates = []

        // A photo captured live through the camera isn't itself tagged
        // with a location — it was taken right now, right here, so a live
        // GPS fix stands in for the per-photo asset/EXIF lookup that
        // uploaded photos use instead.
        let hasCameraPhoto = photos.contains { $0.source == .camera }

        var coordinate: CLLocationCoordinate2D?
        if hasCameraPhoto {
            coordinate = await LocationService.currentLocation()
        }
        for photo in photos where photo.source == .upload {
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
                    images: photos.map { (data: $0.displayData, mediaType: "image/jpeg") },
                    isOnSitePhoto: true
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

        // AI extraction only reads text visible in the photo — a photo of
        // a storefront often has none — so a blank address is filled in
        // (never overwritten) from reverse-geocoding the coordinate
        // itself.
        if let coordinate {
            pendingCoordinate = coordinate
            if address.trimmingCharacters(in: .whitespaces).isEmpty,
               let reverse = await GeocodingService.reverseGeocode(latitude: coordinate.latitude, longitude: coordinate.longitude) {
                address = reverse.address
                filledSomething = true
            }

            // Offer real nearby places to pick from, as a step up from
            // the bare reverse-geocode above.
            let candidates = await NearbyPlacesService.search(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if !candidates.isEmpty { nearbyCandidates = candidates }
        }

        let locationSourceLabel = hasCameraPhoto ? "your current location" : "your photos"
        // `filledSomething` can be true even without an API key (the
        // address may have come from reverse-geocoding the photo's own
        // location, not AI extraction) — checked before the "no API key"
        // message so that case isn't hidden behind it.
        if let extractionFailureMessage {
            photoErrorMessage = extractionFailureMessage
        } else if filledSomething, coordinate != nil {
            photoResultMessage = aiSettings.activeAPIKey != nil
                ? "✨ Filled in details and captured a location from \(locationSourceLabel) — review before saving."
                : "📍 Filled in the address from \(locationSourceLabel) — add an AI extraction API key in Settings to also read other details from your photos."
        } else if filledSomething {
            photoResultMessage = "✨ Filled in details from your photos — review before saving."
        } else if coordinate != nil {
            photoResultMessage = aiSettings.activeAPIKey != nil
                ? "📍 Captured a location from \(locationSourceLabel) — review before saving."
                : "📍 Location captured from \(locationSourceLabel) — add an AI extraction API key in Settings to also read details from your photos."
        } else if aiSettings.activeAPIKey == nil {
            photoResultMessage = "Add an AI extraction API key in Settings to read details from your photos."
        } else {
            photoResultMessage = "Didn't find any new details in those photos."
        }
    }
}
