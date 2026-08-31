import SwiftUI
import SwiftData
import PhotosUI
import UIKit

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

    @State private var captionText = ""
    @State private var selectedScreenshot: PhotosPickerItem?
    @State private var isReadingScreenshot = false
    @State private var ocrErrorMessage: String?

    private var normalizedInstagramURL: URL? {
        InstagramLink.normalized(instagramInput).flatMap(URL.init(string:))
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var detected: CaptionParser.Result {
        CaptionParser.parse(captionText)
    }

    private var hasUnappliedDetection: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        let nameMatches = detected.name == nil || detected.name == trimmedName
        let addressMatches = detected.address == nil || detected.address == trimmedAddress
        return (detected.name != nil || detected.address != nil) && !(nameMatches && addressMatches)
    }

    private func applyDetected() {
        if let detectedName = detected.name, name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = detectedName
        }
        if let detectedAddress = detected.address, address.trimmingCharacters(in: .whitespaces).isEmpty {
            address = detectedAddress
        }
    }

    private var detectionSummary: String {
        var parts: [String] = []
        if let detectedName = detected.name { parts.append("name \"\(detectedName)\"") }
        if let detectedAddress = detected.address { parts.append("address \"\(detectedAddress)\"") }
        return "Detected " + parts.joined(separator: " and ") + "."
    }

    private func loadScreenshot(_ item: PhotosPickerItem) async {
        isReadingScreenshot = true
        ocrErrorMessage = nil
        defer { isReadingScreenshot = false }

        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                ocrErrorMessage = CaptionOCR.OCRError.invalidImage.errorDescription
                return
            }
            let text = try await CaptionOCR.recognizeText(in: image)
            captionText = captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? text
                : captionText + "\n" + text
        } catch let error as CaptionOCR.OCRError {
            ocrErrorMessage = error.errorDescription
        } catch {
            ocrErrorMessage = "Couldn't read text from that image — try pasting the caption instead."
        }
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

                Section {
                    TextField("Paste the post's caption here…", text: $captionText, axis: .vertical)
                        .lineLimit(3...6)

                    PhotosPicker(selection: $selectedScreenshot, matching: .images) {
                        if isReadingScreenshot {
                            Label("Reading text…", systemImage: "text.viewfinder")
                        } else {
                            Label("Upload a screenshot of the caption", systemImage: "camera")
                        }
                    }
                    .disabled(isReadingScreenshot)

                    if let ocrErrorMessage {
                        Text(ocrErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if hasUnappliedDetection {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(detectionSummary)
                                .font(.caption)
                            Button("Use this") { applyDetected() }
                                .font(.caption.weight(.semibold))
                        }
                    }
                } header: {
                    Text("Caption text (optional)")
                } footer: {
                    Text("If the shop's name and address are written in the caption, paste it here — or upload a screenshot and we'll read the text for you — and we'll try to pull them out.")
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
            .onChange(of: selectedScreenshot) { _, newItem in
                guard let newItem else { return }
                Task {
                    await loadScreenshot(newItem)
                    selectedScreenshot = nil
                }
            }
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
