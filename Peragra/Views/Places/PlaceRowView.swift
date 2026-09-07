import SwiftUI
import SwiftData
import UIKit
import CoreLocation

struct PlaceRowView: View {
    @Bindable var place: Place
    let allCollections: [PlaceCollection]
    /// Set only when the list is sorted by distance from a chosen place —
    /// shown as a "N km away" label alongside the category.
    let distanceMeters: Double?
    /// The trip's destination city — used as a fallback qualifier for the
    /// "Open in Google Maps" link when this place has no address.
    let destination: String
    /// Briefly outlined after being jumped to from a map marker's "View
    /// Place Card" control — see PlaceListingView's scroll-to-highlight.
    var highlighted: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var showingCollectionPicker = false
    @State private var showingEdit = false
    @State private var showingCopiedBadge = false
    @State private var notesExpanded = false
    @State private var isRetryingGeocode = false
    @State private var isConfirmingInternationalCall = false
    @State private var geocodeCandidates: [GeocodingService.ProviderResult] = []
    @State private var showingCandidatePicker = false

    /// Notes past this length get a "Show more" toggle instead of always
    /// stretching the row to fit — long enough that a short one-line note
    /// never shows the toggle at all.
    private static let notesCollapseThreshold = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: place.category.symbolName)
                    .foregroundStyle(place.category.tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Button {
                            withAnimation { place.toggleFavorite(context: modelContext) }
                        } label: {
                            Image(systemName: place.favorite ? "star.fill" : "star")
                                .foregroundStyle(place.favorite ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)

                        Text(place.name)
                            .font(.headline)
                            .foregroundStyle(place.visited ? .red : .primary)
                    }
                    HStack(spacing: 4) {
                        Text(place.category.label.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let distanceMeters {
                            Text("· \(formattedDistance(distanceMeters)) away")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if place.visited, let visitedAt = place.visitedAt {
                            Text("· Visited \(visitedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !place.address.isEmpty || (place.phone?.isEmpty == false) {
                        Text(addressAndPhoneLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    withAnimation { place.toggleVisited(context: modelContext) }
                } label: {
                    Image(systemName: place.visited ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(place.visited ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            if !place.notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(notesExpanded ? nil : 3)
                    if place.notes.count > Self.notesCollapseThreshold {
                        Button(notesExpanded ? "Show less" : "Show more") {
                            notesExpanded.toggle()
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.plain)
                    }
                }
            }

            if place.geocodeStatus == .failed {
                HStack(spacing: 6) {
                    Label("Couldn't locate this on the map — try a more specific address.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    retryControl
                }
            }

            if place.geocodeStatus == .estimated {
                HStack(spacing: 6) {
                    Label("Approximate location — AI's best guess, since the given address couldn't be found on the map.", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    retryControl
                }
            }

            HStack(spacing: 14) {
                if let phone = place.phone, !phone.isEmpty, let callURL = callURL(for: phone) {
                    Button {
                        let placeLike = MapProviderPolicy.PlaceLike(
                            latitude: place.latitude,
                            longitude: place.longitude,
                            name: place.name,
                            address: place.address
                        )
                        if MapProviderPolicy.isPlaceOutsideKorea(placeLike) {
                            isConfirmingInternationalCall = true
                        } else {
                            openURL(callURL)
                        }
                    } label: {
                        Label("Call", systemImage: "phone")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    .confirmationDialog(
                        "\(place.name)'s phone number looks like it's outside Korea — this may be an international call.",
                        isPresented: $isConfirmingInternationalCall,
                        titleVisibility: .visible
                    ) {
                        Button("Call") { openURL(callURL) }
                        Button("Cancel", role: .cancel) {}
                    }
                }

                Menu {
                    if let mapsURL = GoogleMapsOpener.url(for: place, tripDestination: destination) {
                        Button {
                            openURL(mapsURL)
                        } label: {
                            Label("Google Maps", systemImage: "map")
                        }
                    }
                    if let naverURL = NaverMapOpener.url(for: place) {
                        Button {
                            openURL(naverURL)
                        } label: {
                            Label("Naver Map", systemImage: "map")
                        }
                    }
                    if let kakaoURL = KakaoMapOpener.url(for: place) {
                        Button {
                            openURL(kakaoURL)
                        } label: {
                            Label("Kakao Map", systemImage: "map")
                        }
                    }
                    if let tmapURL = TmapOpener.url(for: place) {
                        Button {
                            openURL(tmapURL)
                        } label: {
                            Label("Tmap", systemImage: "map")
                        }
                    }
                } label: {
                    Label("Open in Map", systemImage: "map")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }

                if let url = place.instagramURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Instagram", systemImage: "camera")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.pink)
                    }
                    .buttonStyle(.plain)
                }

                if let url = place.linkURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label(
                            place.linkIsInstagram ? "Instagram" : "Website",
                            systemImage: place.linkIsInstagram ? "camera" : "link"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(place.linkIsInstagram ? .pink : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                Button {
                    showingEdit = true
                } label: {
                    Text("Edit")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if !allCollections.isEmpty {
                    Button {
                        showingCollectionPicker = true
                    } label: {
                        let count = place.collections.count
                        Text(count > 0 ? "In \(count) list\(count > 1 ? "s" : "")" : "Add to list")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .listRowBackground(highlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        .animation(.easeInOut(duration: 0.3), value: highlighted)
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                copyForMaps()
            }
        )
        .overlay(alignment: .topTrailing) {
            if showingCopiedBadge {
                Text("Copied for Google Maps")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingCollectionPicker) {
            CollectionPickerSheet(place: place, allCollections: allCollections)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingEdit) {
            EditPlaceSheet(place: place)
        }
        .sheet(isPresented: $showingCandidatePicker) {
            GeocodeCandidateSheet(placeName: place.name, candidates: geocodeCandidates) { chosen in
                apply(chosen.result, status: .located)
            }
        }
    }

    /// Retries against every configured map provider — shown for both a
    /// hard failure and an AI-estimated (approximate) pin, since
    /// "approximate" is really just a softer form of "not properly
    /// located" and worth another shot too, e.g. after switching/adding
    /// a map provider in Settings.
    @ViewBuilder
    private var retryControl: some View {
        if isRetryingGeocode {
            ProgressView().controlSize(.small)
        } else {
            Button("Retry") {
                Task { await retryGeocode() }
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.plain)
        }
    }

    /// Address and phone combined onto one line (when both are present)
    /// rather than two, to keep the row compact.
    private var addressAndPhoneLine: String {
        let phone = place.phone?.isEmpty == false ? "☎ \(place.phone!)" : nil
        return [place.address.isEmpty ? nil : place.address, phone]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// A "tel:" URL for calling this place's phone number — stripped down
    /// to digits and a leading "+" first, since a URL can't contain the
    /// spaces/parens/dashes a phone number is normally written with.
    private func callURL(for phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    /// Long-press copies "name, address" so it can be pasted straight into
    /// Google Maps' search bar.
    private func copyForMaps() {
        let text = place.address.isEmpty ? place.name : "\(place.name), \(place.address)"
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { showingCopiedBadge = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { showingCopiedBadge = false }
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }

    /// Tries every configured map provider (not just whichever one's
    /// selected in Settings) rather than a single geocode — one provider
    /// can confidently return a real but wrong coordinate for an
    /// obscure/short name (a real case: Naver placed a restaurant
    /// nowhere near Korea while Google found it exactly), and the
    /// person can't know which to trust without seeing them. When the
    /// providers agree there's nothing to ask about, so it applies the
    /// result directly; when they meaningfully disagree, it shows
    /// GeocodeCandidateSheet instead of guessing. Falls back to the same
    /// AI nearest-address estimate AddPlaceSheet/EditPlaceSheet already
    /// use when no provider finds anything at all.
    private func retryGeocode() async {
        isRetryingGeocode = true
        defer { isRetryingGeocode = false }
        let siblingPlaces = (place.trip?.places ?? []).filter { $0.id != place.id }.map {
            MapProviderPolicy.PlaceLike(latitude: $0.latitude, longitude: $0.longitude, name: $0.name, address: $0.address)
        }

        let candidates = await GeocodingService.geocodeAllProviders(name: place.name, address: place.address, contextHint: destination, siblingPlaces: siblingPlaces)

        if candidates.isEmpty {
            await fallBackToAIEstimate()
            return
        }

        if candidatesDisagree(candidates) {
            geocodeCandidates = candidates
            showingCandidatePicker = true
            return
        }

        // Providers agree (or only one answered) — prefer the currently
        // configured provider's own result when it's among them, since
        // that's what the rest of the app (Open in Map, etc.) is already
        // set up around.
        let chosen = candidates.first { $0.provider == MapSettings.shared.provider } ?? candidates[0]
        apply(chosen.result, status: .located)
    }

    /// Worth asking the person to pick only when the candidates actually
    /// point at different places — two providers landing a block or two
    /// apart is normal geocoder noise, not a real disagreement.
    private func candidatesDisagree(_ candidates: [GeocodingService.ProviderResult], thresholdMeters: Double = 300) -> Bool {
        for i in 0..<candidates.count {
            for j in (i + 1)..<candidates.count {
                let a = CLLocation(latitude: candidates[i].result.latitude, longitude: candidates[i].result.longitude)
                let b = CLLocation(latitude: candidates[j].result.latitude, longitude: candidates[j].result.longitude)
                if a.distance(from: b) > thresholdMeters { return true }
            }
        }
        return false
    }

    private func apply(_ result: GeocodingService.Result, status: GeocodeStatus) {
        place.latitude = result.latitude
        place.longitude = result.longitude
        place.geocodeStatus = status
        place.syncCountryList(context: modelContext)
    }

    private func fallBackToAIEstimate() async {
        if AISettings.shared.activeAPIKey != nil {
            do {
                let guessedAddress = try await AIExtractionService.guessNearestAddress(
                    destination: destination,
                    name: place.name,
                    address: place.address.isEmpty ? nil : place.address,
                    telephone: place.phone?.isEmpty == false ? place.phone : nil,
                    notes: place.notes.isEmpty ? nil : place.notes
                )
                if let guessedAddress,
                   let estimate = await GeocodingService.geocode(query: guessedAddress, contextHint: destination) {
                    apply(estimate, status: .estimated)
                    return
                }
            } catch {
                // fall through to .failed below
            }
        }

        place.geocodeStatus = .failed
        place.syncCountryList(context: modelContext)
    }
}

private struct CollectionPickerSheet: View {
    @Bindable var place: Place
    let allCollections: [PlaceCollection]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(allCollections) { collection in
                Button {
                    toggle(collection)
                } label: {
                    HStack {
                        Text(collectionLabel(collection))
                        Spacer()
                        if isMember(collection) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Add to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isMember(_ collection: PlaceCollection) -> Bool {
        place.collections.contains(where: { $0.id == collection.id })
    }

    private func collectionLabel(_ collection: PlaceCollection) -> String {
        if collection.isFavoritesList { return "⭐ \(collection.name)" }
        if collection.isVisitedList { return "✅ \(collection.name)" }
        return collection.name
    }

    // Toggling membership in the Visited/Favorites list is another way
    // of marking a place visited/favorite — keep those flags in sync so
    // either control (this picker or the row's own buttons) agrees.
    private func toggle(_ collection: PlaceCollection) {
        if isMember(collection) {
            place.collections.removeAll { $0.id == collection.id }
            if collection.isVisitedList {
                place.visited = false
                place.visitedAt = nil
            }
            if collection.isFavoritesList { place.favorite = false }
        } else {
            place.collections.append(collection)
            if collection.isVisitedList {
                place.visited = true
                place.visitedAt = .now
            }
            if collection.isFavoritesList { place.favorite = true }
        }
    }
}
