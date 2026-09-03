import SwiftUI
import SwiftData
import UIKit

struct PlaceRowView: View {
    @Bindable var place: Place
    let allCollections: [PlaceCollection]
    /// Set only when the list is sorted by distance from a chosen place —
    /// shown as a "N km away" label alongside the category.
    let distanceMeters: Double?

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
                            withAnimation { place.favorite.toggle() }
                        } label: {
                            Image(systemName: place.favorite ? "star.fill" : "star")
                                .foregroundStyle(place.favorite ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)

                        Text(place.name)
                            .font(.headline)
                            .strikethrough(place.visited)
                            .foregroundStyle(place.visited ? .secondary : .primary)
                    }
                    HStack(spacing: 4) {
                        Text(place.category.label.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        if let distanceMeters {
                            Text("· \(formattedDistance(distanceMeters)) away")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !place.address.isEmpty {
                        Text(place.address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let phone = place.phone, !phone.isEmpty {
                        Text("☎ \(phone)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    withAnimation { place.visited.toggle() }
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

            if let mapsURL = GoogleMapsOpener.url(for: place) {
                Button {
                    openURL(mapsURL)
                } label: {
                    Label("Open in Google Maps", systemImage: "map")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            if let url = place.instagramURL {
                Button {
                    openURL(url)
                } label: {
                    Label("View original Instagram post", systemImage: "camera")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.pink)
                }
                .buttonStyle(.plain)
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
                        Text(collection.name)
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

    private func toggle(_ collection: PlaceCollection) {
        if isMember(collection) {
            place.collections.removeAll { $0.id == collection.id }
        } else {
            place.collections.append(collection)
        }
    }
}
