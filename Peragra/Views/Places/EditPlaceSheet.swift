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
    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]

    @State private var name: String
    @State private var category: PlaceCategory
    @State private var address: String
    @State private var phone: String
    @State private var notes: String
    @State private var selectedTrip: Trip?
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
    // The coordinate that produced nearbyCandidates — kept so picking a
    // category hint can re-run the same search narrowed to that category.
    @State private var nearbySearchCoordinate: CLLocationCoordinate2D?
    @State private var isRefiningNearbySearch = false

    // A screenshot of a map app (Google/Naver/Kakao/Apple Maps) showing
    // this place's own info card — read on demand, then shown for review
    // before applying, since (unlike the on-site-photo flow above, which
    // only ever fills in blanks) this is meant to let a wrong/outdated
    // name or address be corrected, which means it has to be allowed to
    // overwrite what's already there.
    @State private var mapScreenshotItem: PhotosPickerItem?
    @State private var mapScreenshotData: Data?
    @State private var isReadingMapScreenshot = false
    @State private var mapScreenshotErrorMessage: String?
    @State private var mapScreenshotResult: AIExtractedPlace?

    private var aiSettings: AISettings { AISettings.shared }

    init(place: Place) {
        self.place = place
        _name = State(initialValue: place.name)
        _category = State(initialValue: place.category)
        _address = State(initialValue: place.address)
        _phone = State(initialValue: place.phone ?? "")
        _notes = State(initialValue: place.notes)
        _selectedTrip = State(initialValue: place.trip)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Place name", text: $name)
                    if allTrips.count > 1 {
                        Picker("Board", selection: $selectedTrip) {
                            ForEach(allTrips) { trip in
                                Text("\(trip.coverEmoji) \(trip.name)").tag(Trip?.some(trip))
                            }
                        }
                    }
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
                    } else if !onSitePhotos.isEmpty, aiSettings.activeAPIKey == nil {
                        Text("Add an AI extraction API key in Settings to read these photos — AI reads photos completely, since on-device text recognition struggles with stylized graphics.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Add Info From a Photo")
                } footer: {
                    Text("Take a photo here or upload one of this place (a sign, a menu, ...) and AI reads it to fill in whatever's still blank above — it never overwrites what you've already entered. A location read from the photo (or your current location) is queued to apply when you save.")
                }

                Section {
                    PhotosPicker(selection: $mapScreenshotItem, matching: .images) {
                        Label(
                            mapScreenshotData == nil ? "Upload Map Screenshot" : "Change Map Screenshot",
                            systemImage: "map"
                        )
                    }
                    .disabled(isReadingMapScreenshot)

                    if let mapScreenshotData, let uiImage = UIImage(data: mapScreenshotData) {
                        HStack {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text("Map screenshot")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                dismissMapScreenshotResult()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if mapScreenshotResult == nil {
                            Button {
                                Task { await readMapScreenshot() }
                            } label: {
                                if isReadingMapScreenshot {
                                    ProgressView()
                                } else {
                                    Text("🗺️ Read Map Screenshot")
                                }
                            }
                            .disabled(isReadingMapScreenshot)
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if let mapScreenshotErrorMessage {
                        Text(mapScreenshotErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let mapScreenshotResult {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mapScreenshotResult.name)
                                .foregroundStyle(.primary)
                            if let address = mapScreenshotResult.address {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let telephone = mapScreenshotResult.telephone {
                                Text(telephone)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Button("Apply") { applyMapScreenshotResult() }
                                .buttonStyle(.borderedProminent)
                            Button("Dismiss", role: .cancel) { dismissMapScreenshotResult() }
                        }
                    }
                } header: {
                    Text("Correct Info From a Map Screenshot")
                } footer: {
                    Text("Upload a screenshot of this place's info card from a map app (Google Maps, Naver Map, Kakao Map, ...) and AI reads its name, address, and phone off the screen — unlike the photo above, this can correct a name or address that's already filled in, not just add to a blank one, so review the result before applying it.")
                }

                if nearbySearchCoordinate != nil {
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text(nearbyCandidates.isEmpty ? "No matches — not sure what it is? Narrow by type:" : "Not the right one? Narrow by type:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(PlaceCategory.allCases) { hintCategory in
                                        FilterChip(title: hintCategory.label, isSelected: false) {
                                            Task { await refineNearbySearch(hintCategory) }
                                        }
                                        .disabled(isRefiningNearbySearch)
                                    }
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                        Button("Dismiss", role: .cancel) {
                            nearbyCandidates = []
                            nearbySearchCoordinate = nil
                        }
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
            .onChange(of: mapScreenshotItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadMapScreenshot(newItem) }
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
        nearbySearchCoordinate = nil
    }

    /// When the plain nearby list is too ambiguous to tell which result
    /// is the right one, narrowing by a category the person supplies
    /// re-runs the same search scoped to it.
    private func refineNearbySearch(_ hintCategory: PlaceCategory) async {
        guard let coordinate = nearbySearchCoordinate else { return }
        isRefiningNearbySearch = true
        defer { isRefiningNearbySearch = false }
        nearbyCandidates = await NearbyPlacesService.search(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            categoryHint: hintCategory
        )
    }

    private func save() async {
        isSaving = true

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressChanged = trimmedAddress != place.address
        let boardChanged = selectedTrip?.id != place.trip?.id

        place.name = trimmedName
        place.category = category
        place.address = trimmedAddress
        place.phone = trimmedPhone.isEmpty ? nil : trimmedPhone
        place.notes = trimmedNotes

        if boardChanged, let newTrip = selectedTrip {
            // Custom-list membership doesn't carry over (those lists
            // belong to the old board), but visited/favorite status is
            // preserved and re-synced against the new board's own
            // Visited/Favorites lists.
            place.trip = newTrip
            var newCollections: [PlaceCollection] = []
            if place.visited {
                newCollections.append(PlaceCollection.ensureVisitedList(for: newTrip, context: modelContext))
            }
            if place.favorite {
                newCollections.append(PlaceCollection.ensureFavoritesList(for: newTrip, context: modelContext))
            }
            place.collections = newCollections
        }

        // A coordinate captured from a photo (its Photos library record,
        // or EXIF) is already a real fix — more trustworthy than geocoding
        // an address — so it's used directly instead of the
        // address-change geocode.
        if let pendingCoordinate {
            place.latitude = pendingCoordinate.latitude
            place.longitude = pendingCoordinate.longitude
            place.geocodeStatus = .located
        } else if addressChanged || boardChanged {
            // Re-geocode when the address changed, or the place moved to
            // a different board — the same address text can resolve
            // differently once it's disambiguated against a new
            // destination. Otherwise leave the existing coordinates (and
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

    private func loadMapScreenshot(_ item: PhotosPickerItem) async {
        mapScreenshotResult = nil
        mapScreenshotErrorMessage = nil
        guard
            let originalData = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: originalData),
            let jpegData = image.jpegData(compressionQuality: 0.85)
        else {
            mapScreenshotErrorMessage = "Couldn't read that screenshot."
            return
        }
        mapScreenshotData = jpegData
    }

    /// Reads a map app screenshot via AI and shows what it found for
    /// review — applying it is a separate, explicit step
    /// (applyMapScreenshotResult) since this is the one AI-extraction
    /// source in this form that's meant to be able to correct an
    /// existing name/address rather than just fill in blanks, so it
    /// shouldn't happen silently.
    private func readMapScreenshot() async {
        guard let mapScreenshotData else { return }
        guard aiSettings.activeAPIKey != nil else {
            mapScreenshotErrorMessage = "Add an AI extraction API key in Settings to read a map screenshot."
            return
        }
        isReadingMapScreenshot = true
        mapScreenshotErrorMessage = nil
        mapScreenshotResult = nil
        defer { isReadingMapScreenshot = false }

        do {
            let extracted = try await AIExtractionService.extractPlaces(
                images: [(data: mapScreenshotData, mediaType: "image/jpeg")],
                photoKind: .mapScreenshot
            )
            guard let found = extracted.first else {
                mapScreenshotErrorMessage = "Couldn't find a place's info in that screenshot."
                return
            }
            mapScreenshotResult = found
        } catch {
            mapScreenshotErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong reading that screenshot."
        }
    }

    private func applyMapScreenshotResult() {
        guard let mapScreenshotResult else { return }
        name = mapScreenshotResult.name
        if let resultAddress = mapScreenshotResult.address { address = resultAddress }
        if let resultPhone = mapScreenshotResult.telephone { phone = resultPhone }
        if let resultNotes = mapScreenshotResult.notes {
            notes = [notes.trimmingCharacters(in: .whitespacesAndNewlines), resultNotes]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }
        dismissMapScreenshotResult()
    }

    private func dismissMapScreenshotResult() {
        mapScreenshotItem = nil
        mapScreenshotData = nil
        mapScreenshotResult = nil
        mapScreenshotErrorMessage = nil
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
        nearbySearchCoordinate = nil

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
                    photoKind: .onSite
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
            // the bare reverse-geocode above — seeded with the category
            // above only if it's been changed from the place's original
            // one, since that's the signal the person actually set it as
            // a hint rather than it just sitting at whatever the place
            // already was.
            nearbySearchCoordinate = coordinate
            nearbyCandidates = await NearbyPlacesService.search(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                categoryHint: category != place.category ? category : nil
            )
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
