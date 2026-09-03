import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UniformTypeIdentifiers

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
    // Set only for places imported from a KML file — they already carry
    // real coordinates from Google Maps, so saving skips geocoding by
    // address/name and uses these directly.
    var latitude: Double?
    var longitude: Double?
}

struct AddPlaceSheet: View {
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
    @State private var captionText = ""
    @State private var notes = ""
    @State private var rows: [CandidateRow] = [CandidateRow()]
    @State private var isSaving = false

    @State private var screenshotItem: PhotosPickerItem?
    @State private var screenshotData: Data?
    @State private var screenshotFileName: String?
    @State private var isLoadingScreenshot = false
    @State private var isAILoading = false
    @State private var extractErrorMessage: String?
    @State private var extractResultMessage: String?
    @State private var isGuessingAddresses = false
    @State private var showingKmlImporter = false

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
                    TextField("Paste the post's caption here…", text: $captionText, axis: .vertical)
                        .lineLimit(3...6)

                    PhotosPicker(selection: $screenshotItem, matching: .images) {
                        if isLoadingScreenshot {
                            ProgressView()
                        } else {
                            Label(screenshotFileName == nil ? "Attach a screenshot" : "Replace screenshot", systemImage: "camera")
                        }
                    }
                    .disabled(isLoadingScreenshot)

                    HStack {
                        Button("🔍 Find Places (Free)") { runPatternExtraction() }
                            .disabled(captionText.trimmingCharacters(in: .whitespaces).isEmpty)
                            .buttonStyle(.bordered)

                        if aiSettings.apiKey != nil {
                            Button {
                                Task { await runAIExtraction() }
                            } label: {
                                if isAILoading {
                                    ProgressView()
                                } else {
                                    Text("✨ Find Places (AI)")
                                }
                            }
                            .disabled(isAILoading || (captionText.trimmingCharacters(in: .whitespaces).isEmpty && screenshotData == nil))
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if screenshotData != nil, aiSettings.apiKey == nil {
                        Text("Add an AI extraction API key in Settings to read this screenshot — AI reads photos completely, since on-device text recognition struggles with stylized graphics.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Caption text (optional)")
                } footer: {
                    Text("If a post recommends one place or several, paste the caption and use free pattern matching — or attach a screenshot and let AI read and organize it completely.")
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
                    Button {
                        showingKmlImporter = true
                    } label: {
                        Label("Upload a .kml file", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Import from Google Maps (optional)")
                } footer: {
                    Text("Google has no API for reading a Saved-places list directly — export one as KML from Google My Maps (mymaps.google.com) and upload it here. Imported places already carry real coordinates, so they skip geocoding entirely.")
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
                    Text("Instagram doesn't let apps read a post's info from its link, so this doesn't fill in anything above — use caption text or a screenshot for that. Paste it only if you want the original post embedded here for reference.")
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
            .onChange(of: screenshotItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await loadScreenshot(newItem)
                    screenshotItem = nil
                }
            }
            .fileImporter(
                isPresented: $showingKmlImporter,
                allowedContentTypes: [UTType(filenameExtension: "kml") ?? .xml, .xml],
                onCompletion: handleKmlImport
            )
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
            }
        }
    }

    private enum ExtractionSource: Equatable {
        case pattern
        case ai
    }

    private func applyCategoryToSelected(_ category: PlaceCategory) {
        for index in rows.indices where rows[index].selected {
            rows[index].category = category
        }
    }

    private func replaceRows(
        with places: [(name: String?, address: String?, telephone: String?, notes: String?)],
        source: ExtractionSource
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
        // map — a name-only fallback (the parser's last resort: any
        // short, non-hashtag line) can still fire on pure noise, so check
        // for at least one real address rather than just "found a name".
        let withAddress = places.filter { $0.address != nil }.count
        if usable.isEmpty || withAddress == 0 {
            extractResultMessage = nil
            switch source {
            case .pattern:
                extractErrorMessage = aiSettings.apiKey != nil
                    ? "Couldn't find a usable address in that text — try ✨ Find Places (AI) instead."
                    : "Couldn't find any places in that text."
            case .ai:
                extractErrorMessage = "AI couldn't find a usable address there — try a clearer screenshot, or edit the place below manually."
            }
        } else {
            extractErrorMessage = nil
            let label = source == .ai ? "AI" : "Pattern matching"
            let placeWord = usable.count == 1 ? "place" : "places"
            extractResultMessage = "\(label) found \(usable.count) \(placeWord) (\(withAddress) with an address) — review below before saving."
        }

        guard !usable.isEmpty, aiSettings.apiKey != nil else { return }
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
        guard let apiKey = aiSettings.apiKey, !targets.isEmpty else { return }
        isGuessingAddresses = true
        defer { isGuessingAddresses = false }

        do {
            let guesses = try await AIExtractionService.guessAddresses(
                apiKey: apiKey,
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

    private func handleKmlImport(_ result: Result<URL, Error>) {
        extractErrorMessage = nil
        extractResultMessage = nil
        guard case let .success(url) = result else {
            extractErrorMessage = "Couldn't read that file."
            return
        }

        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            extractErrorMessage = "Couldn't read that file."
            return
        }

        let places = KMLService.parsePlaces(from: data)
        let usable = places.filter { $0.name != nil }
        guard !usable.isEmpty else {
            extractErrorMessage = "Couldn't find any places in that KML file."
            return
        }

        rows = usable.map { place in
            CandidateRow(
                name: place.name ?? "",
                address: place.address ?? "",
                latitude: place.latitude,
                longitude: place.longitude
            )
        }
        let placeWord = usable.count == 1 ? "place" : "places"
        extractResultMessage = "Imported \(usable.count) \(placeWord) from KML — review below before saving."
    }

    private func runPatternExtraction() {
        extractErrorMessage = nil
        extractResultMessage = nil
        let results = CaptionParser.parseMultiple(captionText)
        replaceRows(with: results.map { ($0.name, $0.address, nil, nil) }, source: .pattern)
    }

    private func runAIExtraction() async {
        guard let apiKey = aiSettings.apiKey else { return }
        extractErrorMessage = nil
        extractResultMessage = nil
        isAILoading = true
        defer { isAILoading = false }

        do {
            let results: [AIExtractedPlace]
            if let screenshotData {
                results = try await AIExtractionService.extractPlaces(
                    apiKey: apiKey,
                    imageData: screenshotData,
                    mediaType: "image/jpeg"
                )
            } else if !captionText.trimmingCharacters(in: .whitespaces).isEmpty {
                results = try await AIExtractionService.extractPlaces(apiKey: apiKey, captionText: captionText)
            } else {
                extractErrorMessage = "Paste a caption or upload a screenshot first."
                return
            }
            replaceRows(
                with: results.map { (name: $0.name as String?, address: $0.address, telephone: $0.telephone, notes: $0.notes) },
                source: .ai
            )
        } catch {
            extractResultMessage = nil
            extractErrorMessage = (error as? LocalizedError)?.errorDescription ?? "AI extraction failed."
        }
    }

    private func loadScreenshot(_ item: PhotosPickerItem) async {
        isLoadingScreenshot = true
        extractErrorMessage = nil
        extractResultMessage = nil
        defer { isLoadingScreenshot = false }

        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data),
            let jpegData = image.jpegData(compressionQuality: 0.85)
        else {
            extractErrorMessage = "Couldn't read that image."
            return
        }
        screenshotData = jpegData
        screenshotFileName = "screenshot.jpg"
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
            if let defaultCollection {
                place.collections.append(defaultCollection)
            }

            if let latitude = row.latitude, let longitude = row.longitude {
                // Imported from KML — already has real coordinates from
                // Google Maps, so there's nothing to geocode.
                place.latitude = latitude
                place.longitude = longitude
                place.geocodeStatus = .located
                continue
            }

            await geocodeAndStore(place, row: row)
        }

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
    private func geocodeAndStore(_ place: Place, row: CandidateRow) async {
        let trimmedAddress = row.address.trimmingCharacters(in: .whitespaces)
        let trimmedName = row.name.trimmingCharacters(in: .whitespaces)
        let query = trimmedAddress.isEmpty ? trimmedName : trimmedAddress

        if let result = await GeocodingService.geocode(query: query, contextHint: trip.destination) {
            place.latitude = result.latitude
            place.longitude = result.longitude
            place.geocodeStatus = .located
            return
        }

        if let apiKey = aiSettings.apiKey {
            do {
                let guessedAddress = try await AIExtractionService.guessNearestAddress(
                    apiKey: apiKey,
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
