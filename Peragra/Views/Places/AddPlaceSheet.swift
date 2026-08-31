import SwiftUI
import SwiftData
import PhotosUI
import UIKit

private struct CandidateRow: Identifiable {
    let id = UUID()
    var selected = true
    var name = ""
    var address = ""
    var category: PlaceCategory = .restaurant
}

struct AddPlaceSheet: View {
    let trip: Trip
    var defaultCollection: PlaceCollection?

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
    @State private var isReadingScreenshot = false
    @State private var isAILoading = false
    @State private var extractErrorMessage: String?

    private var aiSettings = AISettings.shared

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

                Section {
                    TextField("Paste the post's caption here…", text: $captionText, axis: .vertical)
                        .lineLimit(3...6)

                    PhotosPicker(selection: $screenshotItem, matching: .images) {
                        if isReadingScreenshot {
                            Label("Reading text…", systemImage: "text.viewfinder")
                        } else {
                            Label(screenshotFileName == nil ? "Upload a screenshot" : "Replace screenshot", systemImage: "camera")
                        }
                    }
                    .disabled(isReadingScreenshot)

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

                    if let extractErrorMessage {
                        Text(extractErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Caption text (optional)")
                } footer: {
                    Text("If a post recommends one place or several, paste the caption — or upload a screenshot — and extract them into the list below to review before saving.")
                }

                Section {
                    ForEach($rows) { $row in
                        candidateRowView($row)
                    }
                    .onDelete { indices in rows.remove(atOffsets: indices) }

                    Button("+ Add Place") { rows.append(CandidateRow()) }
                } header: {
                    Text("Places to Save (\(selectedCount) selected)")
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
            }
        }
    }

    private func replaceRows(with places: [(name: String?, address: String?)]) {
        let usable = places.filter { $0.name != nil }
        guard !usable.isEmpty else {
            extractErrorMessage = "Couldn't find any places in that text."
            return
        }
        rows = usable.map { place in
            CandidateRow(name: place.name ?? "", address: place.address ?? "")
        }
    }

    private func runPatternExtraction() {
        extractErrorMessage = nil
        let results = CaptionParser.parseMultiple(captionText)
        replaceRows(with: results.map { ($0.name, $0.address) })
    }

    private func runAIExtraction() async {
        guard let apiKey = aiSettings.apiKey else { return }
        extractErrorMessage = nil
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
            replaceRows(with: results.map { (name: $0.name as String?, address: $0.address) })
        } catch {
            extractErrorMessage = (error as? LocalizedError)?.errorDescription ?? "AI extraction failed."
        }
    }

    private func loadScreenshot(_ item: PhotosPickerItem) async {
        isReadingScreenshot = true
        extractErrorMessage = nil
        defer { isReadingScreenshot = false }

        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data),
                let jpegData = image.jpegData(compressionQuality: 0.85)
            else {
                extractErrorMessage = "Couldn't read that image."
                return
            }
            screenshotData = jpegData
            screenshotFileName = "screenshot.jpg"

            let text = try await CaptionOCR.recognizeText(in: image)
            captionText = captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? text
                : captionText + "\n" + text
        } catch let error as CaptionOCR.OCRError {
            // OCR is just a convenience for the free pattern-match path;
            // AI extraction can still use the image directly via vision.
            if error != .noText {
                extractErrorMessage = error.errorDescription
            }
        } catch {
            extractErrorMessage = "Couldn't read text from that image — try pasting the caption instead."
        }
    }

    private func save() async {
        isSaving = true
        let toSave = rows.filter { $0.selected && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }

        for row in toSave {
            let place = Place(
                name: row.name.trimmingCharacters(in: .whitespaces),
                category: row.category,
                address: row.address.trimmingCharacters(in: .whitespaces),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                instagramURLString: normalizedInstagramURL?.absoluteString,
                trip: trip
            )
            modelContext.insert(place)
            if let defaultCollection {
                place.collections.append(defaultCollection)
            }

            let query = row.address.trimmingCharacters(in: .whitespaces).isEmpty
                ? row.name.trimmingCharacters(in: .whitespaces)
                : row.address.trimmingCharacters(in: .whitespaces)
            if let result = await GeocodingService.geocode(query: query, contextHint: trip.destination) {
                place.latitude = result.latitude
                place.longitude = result.longitude
                place.geocodeStatus = .located
            } else {
                place.geocodeStatus = .failed
            }
        }

        isSaving = false
        dismiss()
    }
}
