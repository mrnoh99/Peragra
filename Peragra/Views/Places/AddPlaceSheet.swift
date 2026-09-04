import SwiftUI
import SwiftData
import PhotosUI
import Photos
import UIKit
import CoreLocation

private struct CandidateRow: Identifiable {
    let id = UUID()
    var selected = true
    var name = ""
    var address = ""
    var phone = ""
    // Anything else recognized about this specific place (hours, price, a
    // recommended item, why it was recommended, ...) — combined with the
    // form's own manual notes field at save time, not a replacement for it.
    var notes = ""
    var category: PlaceCategory = .restaurant
    // Set when this row came from the on-site photo flow rather than
    // AI-extracted address text — geocodeAndStore uses these directly
    // instead of geocoding, since a photo's own location is more
    // trustworthy than any address string.
    var manualLatitude: Double?
    var manualLongitude: Double?
    // The moment the on-site photo was actually taken, if this row came
    // from that flow — used as the saved place's createdAt instead of
    // whenever Save happens to be tapped, in case reviewing the row
    // (or waiting on AI extraction) took a while.
    var capturedAt: Date?
}

private struct OnSitePhoto: Identifiable {
    let id = UUID()
    // The JPEG-recompressed version used for the AI call and thumbnail, so
    // its media type is predictable regardless of what format the
    // original photo was in.
    var displayData: Data
    // The raw bytes as picked, so EXIF metadata survives — re-encoding
    // through UIImage/jpegData (which produces `displayData`) strips it.
    // Still the fallback source for location/time when `assetLocation`/
    // `assetCreationDate` below aren't available.
    var originalData: Data
    // Read straight from the Photos library's own record for this asset
    // when the app has photo library access — more reliable than EXIF,
    // since PhotosPicker strips location metadata from the image data it
    // hands back unless the app has that access.
    var assetLocation: CLLocationCoordinate2D?
    var assetCreationDate: Date?
}

struct AddPlaceSheet: View {
    /// Reading more screenshots than this in one AI pass gets slow and
    /// costly for what's still just "a few saved posts" — this caps it.
    private static let maxScreenshots = 10

    let trip: Trip
    var defaultCollection: PlaceCollection?

    // Explicit, so this view's access level never depends on Swift's
    // synthesized-memberwise-init rules around private stored properties
    // elsewhere in the type (bit us once already — see aiSettings below).
    init(trip: Trip, defaultCollection: PlaceCollection? = nil) {
        self.trip = trip
        self.defaultCollection = defaultCollection
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var instagramInput = ""
    @State private var notes = ""
    @State private var rows: [CandidateRow] = [CandidateRow()]
    @State private var isSaving = false

    @State private var screenshotItems: [PhotosPickerItem] = []
    @State private var screenshotDatas: [Data] = []
    @State private var isLoadingScreenshot = false
    /// Set while an AI extraction call is in flight; `total` > 1 when
    /// reading multiple screenshots one at a time.
    @State private var aiProgress: (current: Int, total: Int)?
    @State private var extractErrorMessage: String?
    @State private var extractResultMessage: String?
    @State private var isGuessingAddresses = false

    @State private var isCapturingOnSite = false
    @State private var uploadPhotoItems: [PhotosPickerItem] = []
    @State private var showingUploadPicker = false
    @State private var isLoadingUploadPhotos = false
    /// Photos accumulated for the place currently being logged — several
    /// angles (sign, menu, interior, ...) — before "Log This Place" sends
    /// them all to AI in one request together, so it can cross-reference
    /// them into one accurate result instead of reconciling separate
    /// per-photo guesses. Each photo's own location/capture-time data
    /// (from the Photos library, falling back to EXIF) supplies the
    /// place's location and capture time.
    @State private var onSitePhotos: [OnSitePhoto] = []
    // Real nearby places offered as pickable candidates for the blank row
    // a photo's GPS fix alone produced — set only when that search
    // actually found something, and only relevant to that one row (it's
    // the only case where the row has no AI-found name to already trust).
    @State private var nearbyCandidates: [NearbyPlacesService.Candidate] = []
    @State private var nearbyCandidateRowID: UUID?

    // Computed, not stored — a private *stored* property forces Swift's
    // synthesized memberwise init to become private too, which broke
    // AddPlaceSheet(trip:defaultCollection:) calls from other files.
    private var aiSettings: AISettings { AISettings.shared }

    private var normalizedInstagramURL: URL? {
        InstagramLink.normalized(instagramInput).flatMap(URL.init(string:))
    }

    private var selectedCount: Int {
        rows.filter { $0.selected && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    private var canSubmit: Bool { selectedCount > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if screenshotDatas.count < Self.maxScreenshots {
                        PhotosPicker(
                            selection: $screenshotItems,
                            maxSelectionCount: Self.maxScreenshots - screenshotDatas.count,
                            matching: .images
                        ) {
                            if isLoadingScreenshot {
                                ProgressView()
                            } else {
                                Label(
                                    screenshotDatas.isEmpty ? "Attach screenshots" : "Add another screenshot",
                                    systemImage: "photo.on.rectangle"
                                )
                            }
                        }
                        .disabled(isLoadingScreenshot)
                    }

                    Button {
                        Task {
                            // Requested here, before the picker opens, so
                            // the picked items' itemIdentifier (needed to
                            // resolve their PHAsset for accurate
                            // location/time) is available from this very
                            // first pick rather than only from the next
                            // one. A no-op prompt-wise once already
                            // decided; silently proceeds without it if
                            // denied.
                            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                            showingUploadPicker = true
                        }
                    } label: {
                        if isLoadingUploadPhotos {
                            ProgressView()
                        } else {
                            Label(
                                onSitePhotos.isEmpty ? "Upload On-Site Photos" : "Add More On-Site Photos",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                    }
                    .disabled(isLoadingUploadPhotos || isCapturingOnSite)
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
                            Task { await captureOnSitePlace() }
                        } label: {
                            if isCapturingOnSite {
                                ProgressView()
                            } else {
                                Text("📍 Log This Place")
                            }
                        }
                        .disabled(isCapturingOnSite)
                        .buttonStyle(.borderedProminent)
                    }

                    ForEach(Array(screenshotDatas.enumerated()), id: \.offset) { index, data in
                        HStack {
                            if let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Text("Screenshot \(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                screenshotDatas.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if aiSettings.activeAPIKey != nil {
                        Button {
                            Task { await runAIExtraction() }
                        } label: {
                            if let aiProgress, aiProgress.total > 1 {
                                Text("Reading \(min(aiProgress.current + 1, aiProgress.total))/\(aiProgress.total)…")
                            } else if aiProgress != nil {
                                ProgressView()
                            } else {
                                Text("✨ Find Places (AI)")
                            }
                        }
                        .disabled(aiProgress != nil || screenshotDatas.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }

                    if let aiProgress, aiProgress.total > 1 {
                        ProgressView(value: Double(aiProgress.current), total: Double(aiProgress.total))
                    }

                    if !screenshotDatas.isEmpty, aiSettings.activeAPIKey == nil {
                        Text("Add an AI extraction API key in Settings to read these screenshots — AI reads photos completely, since on-device text recognition struggles with stylized graphics.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Attach up to \(Self.maxScreenshots) screenshots of a post and let AI read and organize them completely. Or, for a place you want to log with its own location: upload one or more photos of it (a sign, a menu, ...) and tap Log This Place — AI cross-references them all into one result, and its location and time come from the photos' own data.")
                }

                if extractErrorMessage != nil || extractResultMessage != nil || isGuessingAddresses {
                    Section {
                        if let extractErrorMessage {
                            Text(extractErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if isGuessingAddresses {
                            Text("✨ AI is guessing addresses for places without one…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let extractResultMessage {
                            Text(extractResultMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                        Button("Dismiss", role: .cancel) { dismissNearbyCandidates() }
                    } header: {
                        Text("📍 Is it one of these nearby places?")
                    }
                }

                Section {
                    ForEach($rows) { $row in
                        candidateRowView($row)
                    }
                    .onDelete { indices in rows.remove(atOffsets: indices) }

                    Button("+ Add Place") { rows.append(CandidateRow()) }
                } header: {
                    HStack {
                        Text("Places to Save (\(selectedCount) selected)")
                        Spacer()
                        Menu {
                            ForEach(PlaceCategory.allCases) { category in
                                Button {
                                    applyCategoryToSelected(category)
                                } label: {
                                    Label(category.label, systemImage: category.symbolName)
                                }
                            }
                        } label: {
                            Label("Category", systemImage: "tag")
                                .font(.caption)
                        }
                        .disabled(selectedCount == 0)
                    }
                }

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
                    Text("Instagram post link (optional, just a reference)")
                } footer: {
                    Text("Instagram doesn't let apps read a post's info from its link, so this doesn't fill in anything above — attach a screenshot for that. Paste it only if you want the original post embedded here for reference.")
                }

                Section("Notes") {
                    TextField("What made you save this?", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Save Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save \(selectedCount)") { Task { await save() } }
                            .disabled(!canSubmit)
                    }
                }
            }
            .disabled(isSaving)
            .onChange(of: screenshotItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await loadScreenshots(newItems)
                    screenshotItems = []
                }
            }
            .onChange(of: uploadPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await loadUploadPhotos(newItems)
                    uploadPhotoItems = []
                }
            }
        }
    }

    @ViewBuilder
    private func candidateRowView(_ row: Binding<CandidateRow>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                row.wrappedValue.selected.toggle()
            } label: {
                Image(systemName: row.wrappedValue.selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.wrappedValue.selected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Place name", text: row.name)
                TextField("Address (improves map accuracy)", text: row.address)
                    .font(.subheadline)
                Picker("Category", selection: row.category) {
                    ForEach(PlaceCategory.allCases) { option in
                        Label(option.label, systemImage: option.symbolName).tag(option)
                    }
                }
                .font(.subheadline)
                .pickerStyle(.menu)
                TextField("Phone (optional)", text: row.phone)
                    .font(.subheadline)
                    .keyboardType(.phonePad)
                TextField("Other details (hours, menu, why recommended, ...)", text: row.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if row.wrappedValue.manualLatitude != nil {
                    Label("Using a captured location", systemImage: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func applyCategoryToSelected(_ category: PlaceCategory) {
        for index in rows.indices where rows[index].selected {
            rows[index].category = category
        }
    }

    /// Picking a nearby candidate is an explicit choice, so unlike the
    /// AI/reverse-geocode fallbacks above it does overwrite the row's
    /// name/address/phone/category — including with the candidate's own
    /// (more precise) coordinate rather than the photo's raw GPS fix.
    private func applyNearbyCandidate(_ candidate: NearbyPlacesService.Candidate) {
        guard let rowID = nearbyCandidateRowID, let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].name = candidate.name
        rows[index].address = candidate.address ?? ""
        rows[index].phone = candidate.phone ?? ""
        rows[index].category = candidate.category
        rows[index].manualLatitude = candidate.latitude
        rows[index].manualLongitude = candidate.longitude
        nearbyCandidates = []
        nearbyCandidateRowID = nil
    }

    private func dismissNearbyCandidates() {
        nearbyCandidates = []
        nearbyCandidateRowID = nil
    }

    private func replaceRows(
        with places: [(name: String?, address: String?, telephone: String?, notes: String?)]
    ) {
        let usable = places.filter { $0.name != nil }
        if !usable.isEmpty {
            rows = usable.map { place in
                CandidateRow(
                    name: place.name ?? "",
                    address: place.address ?? "",
                    phone: place.telephone ?? "",
                    notes: place.notes ?? ""
                )
            }
        }

        // The whole point of extraction is getting an address onto the
        // map — a name-only fallback can still fire on pure noise, so
        // check for at least one real address rather than just "found a
        // name".
        let withAddress = places.filter { $0.address != nil }.count
        if usable.isEmpty || withAddress == 0 {
            extractResultMessage = nil
            extractErrorMessage = "AI couldn't find a usable address there — try a clearer screenshot, or edit the place below manually."
        } else {
            extractErrorMessage = nil
            let placeWord = usable.count == 1 ? "place" : "places"
            extractResultMessage = "AI found \(usable.count) \(placeWord) (\(withAddress) with an address) — review below before saving."
        }

        guard !usable.isEmpty, aiSettings.activeAPIKey != nil else { return }
        let targets = rows.filter { $0.address.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { (id: $0.id, name: $0.name) }
        if !targets.isEmpty {
            Task { await fillMissingAddressesWithAI(targets) }
        }
    }

    /// Best-effort follow-up to extraction: for rows a caption named but
    /// never gave an address, ask AI to guess one from its general
    /// knowledge of the trip's destination rather than leaving the place
    /// unaddressed (and therefore hard to geocode accurately).
    private func fillMissingAddressesWithAI(_ targets: [(id: UUID, name: String)]) async {
        guard aiSettings.activeAPIKey != nil, !targets.isEmpty else { return }
        isGuessingAddresses = true
        defer { isGuessingAddresses = false }

        do {
            let guesses = try await AIExtractionService.guessAddresses(
                destination: trip.destination,
                placeNames: targets.map { $0.name }
            )
            var filledCount = 0
            for (index, target) in targets.enumerated() {
                guard index < guesses.count, let guess = guesses[index] else { continue }
                if let rowIndex = rows.firstIndex(where: { $0.id == target.id }) {
                    rows[rowIndex].address = guess
                    filledCount += 1
                }
            }
            if filledCount > 0 {
                extractErrorMessage = nil
                let placeWord = filledCount == 1 ? "place" : "places"
                extractResultMessage = "✨ AI guessed an address for \(filledCount) \(placeWord) that didn't have one — double-check before saving."
            }
        } catch {
            // Best effort — leave those rows addressless if the guess
            // call itself fails; the existing extract result/error
            // message stands.
        }
    }

    private func runAIExtraction() async {
        guard aiSettings.activeAPIKey != nil, !screenshotDatas.isEmpty else { return }
        extractErrorMessage = nil
        extractResultMessage = nil
        defer { aiProgress = nil }

        do {
            // Read one screenshot at a time (rather than in parallel) so
            // progress reflects real completions, not just requests fired.
            var allResults: [AIExtractedPlace] = []
            aiProgress = (current: 0, total: screenshotDatas.count)
            for (index, data) in screenshotDatas.enumerated() {
                let pageResults = try await AIExtractionService.extractPlaces(
                    imageData: data,
                    mediaType: "image/jpeg"
                )
                allResults.append(contentsOf: pageResults)
                aiProgress = (current: index + 1, total: screenshotDatas.count)
            }
            replaceRows(
                with: allResults.map { (name: $0.name as String?, address: $0.address, telephone: $0.telephone, notes: $0.notes) }
            )
        } catch {
            extractResultMessage = nil
            extractErrorMessage = (error as? LocalizedError)?.errorDescription ?? "AI extraction failed."
        }
    }

    private func loadUploadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingUploadPhotos = true
        extractErrorMessage = nil
        extractResultMessage = nil
        defer { isLoadingUploadPhotos = false }

        for item in items {
            guard
                let originalData = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: originalData),
                let jpegData = image.jpegData(compressionQuality: 0.85)
            else {
                extractErrorMessage = "Couldn't read one of those photos."
                continue
            }

            var assetLocation: CLLocationCoordinate2D?
            var assetCreationDate: Date?
            if let identifier = item.itemIdentifier,
               let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject {
                assetLocation = asset.location?.coordinate
                assetCreationDate = asset.creationDate
            }

            onSitePhotos.append(OnSitePhoto(
                displayData: jpegData,
                originalData: originalData,
                assetLocation: assetLocation,
                assetCreationDate: assetCreationDate
            ))
        }
    }

    /// The "Log This Place" flow: read each accumulated photo's own
    /// location/timestamp (using the first location and earliest time
    /// found across the batch — a photo may lack either), then kick off
    /// (if there's an AI key) one AI extraction call across *all* the
    /// photos together — letting the model cross-reference several angles
    /// of the same place into one accurate result — then replace the
    /// candidate rows with whatever it found (or one blank row to fill in
    /// by hand if there's no AI key configured). Every resulting row is
    /// tagged with a coordinate/time so geocodeAndStore and save() use
    /// them directly instead of geocoding an address.
    private func captureOnSitePlace() async {
        guard !onSitePhotos.isEmpty else { return }
        isCapturingOnSite = true
        extractErrorMessage = nil
        extractResultMessage = nil
        defer { isCapturingOnSite = false }

        let photos = onSitePhotos
        onSitePhotos = []

        var coordinate: CLLocationCoordinate2D?
        var capturedAt: Date?
        for photo in photos {
            // The Photos library's own record for this asset, when
            // available, is more reliable than EXIF parsed from the
            // (possibly privacy-stripped) image data — prefer it, only
            // falling back to EXIF for whichever of the two it lacks.
            let exif = (photo.assetLocation == nil || photo.assetCreationDate == nil)
                ? PhotoMetadata.extract(from: photo.originalData)
                : nil
            let location = photo.assetLocation ?? exif?.location
            let date = photo.assetCreationDate ?? exif?.capturedAt
            if coordinate == nil { coordinate = location }
            if let date, capturedAt == nil || date < capturedAt! {
                capturedAt = date
            }
        }

        var extracted: [AIExtractedPlace] = []
        var extractionFailureMessage: String?
        if aiSettings.activeAPIKey != nil {
            do {
                extracted = try await AIExtractionService.extractPlaces(
                    images: photos.map { (data: $0.displayData, mediaType: "image/jpeg") }
                )
            } catch {
                extractionFailureMessage = (error as? LocalizedError)?.errorDescription ?? "AI extraction failed — add the place details manually below."
            }
        }

        var newRows = extracted.isEmpty
            ? [CandidateRow(manualLatitude: coordinate?.latitude, manualLongitude: coordinate?.longitude, capturedAt: capturedAt)]
            : extracted.map { place in
                CandidateRow(
                    name: place.name,
                    address: place.address ?? "",
                    phone: place.telephone ?? "",
                    notes: place.notes ?? "",
                    manualLatitude: coordinate?.latitude,
                    manualLongitude: coordinate?.longitude,
                    capturedAt: capturedAt
                )
            }

        // AI extraction only reads text visible in the photo — a photo of
        // a storefront often has none — so a blank address/name is filled
        // in (never overwritten) from reverse-geocoding the coordinate
        // itself.
        var foundNameFromLocation = false
        if let coordinate, let reverse = await GeocodingService.reverseGeocode(latitude: coordinate.latitude, longitude: coordinate.longitude) {
            for index in newRows.indices {
                if newRows[index].address.trimmingCharacters(in: .whitespaces).isEmpty {
                    newRows[index].address = reverse.address
                }
                if newRows[index].name.trimmingCharacters(in: .whitespaces).isEmpty, let name = reverse.name {
                    newRows[index].name = name
                    foundNameFromLocation = true
                }
            }
        }
        rows = newRows

        // Offer real nearby places to pick from, as a step up from the
        // bare reverse-geocode above — only worth asking when AI found
        // nothing on its own (there's exactly one blank row).
        nearbyCandidates = []
        nearbyCandidateRowID = nil
        if extracted.isEmpty, let coordinate {
            let candidates = await NearbyPlacesService.search(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if !candidates.isEmpty, let firstRowID = newRows.first?.id {
                nearbyCandidates = candidates
                nearbyCandidateRowID = firstRowID
            }
        }

        if let extractionFailureMessage {
            extractErrorMessage = extractionFailureMessage
        } else if coordinate == nil {
            extractErrorMessage = "Couldn't find location info in those photos — add an address below, or upload a photo that has it."
        } else if extracted.isEmpty {
            extractResultMessage = foundNameFromLocation
                ? "📍 Found a place at your photos' location — review below before saving."
                : "📍 Read the location from your photos — fill in the place details below."
        } else {
            let placeWord = extracted.count == 1 ? "place" : "places"
            extractResultMessage = "📍 Read the location from your photos and found \(extracted.count) \(placeWord) — review below before saving."
        }
    }

    private func loadScreenshots(_ items: [PhotosPickerItem]) async {
        isLoadingScreenshot = true
        extractErrorMessage = nil
        extractResultMessage = nil
        defer { isLoadingScreenshot = false }

        for item in items {
            guard screenshotDatas.count < Self.maxScreenshots else { break }
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data),
                let jpegData = image.jpegData(compressionQuality: 0.85)
            else {
                extractErrorMessage = "Couldn't read one of those images."
                continue
            }
            screenshotDatas.append(jpegData)
        }
    }

    private func save() async {
        isSaving = true
        let toSave = rows.filter { $0.selected && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }

        for row in toSave {
            let trimmedPhone = row.phone.trimmingCharacters(in: .whitespaces)
            let combinedNotes = [
                row.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                notes.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

            let place = Place(
                name: row.name.trimmingCharacters(in: .whitespaces),
                category: row.category,
                address: row.address.trimmingCharacters(in: .whitespaces),
                phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                notes: combinedNotes,
                instagramURLString: normalizedInstagramURL?.absoluteString,
                trip: trip
            )
            modelContext.insert(place)
            if let capturedAt = row.capturedAt {
                place.createdAt = capturedAt
            }
            if let defaultCollection {
                place.collections.append(defaultCollection)
            }

            await geocodeAndStore(place, row: row)
        }

        // Explicit rather than relying on SwiftData's autosave timing —
        // views elsewhere (like TripDetailView's @Query-backed Export
        // button) need the just-set latitude/longitude actually committed
        // to be sure they see it as soon as this sheet dismisses, not
        // whenever autosave next happens to run.
        try? modelContext.save()

        isSaving = false
        dismiss()
    }

    /// Geocodes a row's own address/name; if that fails and an AI API key
    /// is configured, falls back to asking AI for its best guess at the
    /// nearest plausible real address (using the row's name, address,
    /// phone, and notes as context) and geocodes that instead — marked
    /// `.estimated` rather than `.located` so the UI can flag it as
    /// approximate. Only `.failed` once both the real geocode and the AI
    /// estimate come up empty (or there's no API key to try at all).
    ///
    /// A row from the on-site photo flow already has a real location fix,
    /// which is more trustworthy than geocoding any address text, so
    /// that's used directly instead — skipping geocoding entirely.
    private func geocodeAndStore(_ place: Place, row: CandidateRow) async {
        if let latitude = row.manualLatitude, let longitude = row.manualLongitude {
            place.latitude = latitude
            place.longitude = longitude
            place.geocodeStatus = .located
            return
        }

        let trimmedAddress = row.address.trimmingCharacters(in: .whitespaces)
        let trimmedName = row.name.trimmingCharacters(in: .whitespaces)
        let query = trimmedAddress.isEmpty ? trimmedName : trimmedAddress

        if let result = await GeocodingService.geocode(query: query, contextHint: trip.destination) {
            place.latitude = result.latitude
            place.longitude = result.longitude
            place.geocodeStatus = .located
            return
        }

        if aiSettings.activeAPIKey != nil {
            do {
                let guessedAddress = try await AIExtractionService.guessNearestAddress(
                    destination: trip.destination,
                    name: trimmedName,
                    address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                    telephone: row.phone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : row.phone,
                    notes: row.notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : row.notes
                )
                if let guessedAddress,
                   let estimate = await GeocodingService.geocode(query: guessedAddress, contextHint: trip.destination) {
                    place.latitude = estimate.latitude
                    place.longitude = estimate.longitude
                    place.geocodeStatus = .estimated
                    return
                }
            } catch {
                // fall through to .failed below
            }
        }

        place.geocodeStatus = .failed
    }
}
