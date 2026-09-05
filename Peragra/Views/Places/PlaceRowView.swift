import SwiftUI
import SwiftData
import UIKit

struct PlaceRowView: View {
    @Bindable var place: Place
    let allCollections: [PlaceCollection]
    /// Set only when the list is sorted by distance from a chosen place —
    /// shown as a "N km away" label alongside the category.
    let distanceMeters: Double?
    /// The trip's destination city — used as a fallback qualifier for the
    /// "Open in Google Maps" link when this place has no address.
    let destination: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var showingCollectionPicker = false
    @State private var showingEdit = false
    @State private var showingCopiedBadge = false

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
                Text(place.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if place.geocodeStatus == .failed {
                Label("Couldn't locate this on the map — try a more specific address.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if place.geocodeStatus == .estimated {
                Label("Approximate location — AI's best guess, since the given address couldn't be found on the map.", systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
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
                    Label("Send to Map", systemImage: "map")
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
    }

    /// Address and phone combined onto one line (when both are present)
    /// rather than two, to keep the row compact.
    private var addressAndPhoneLine: String {
        let phone = place.phone?.isEmpty == false ? "☎ \(place.phone!)" : nil
        return [place.address.isEmpty ? nil : place.address, phone]
            .compactMap { $0 }
            .joined(separator: " · ")
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
