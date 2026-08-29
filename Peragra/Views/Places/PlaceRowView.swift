import SwiftUI
import SwiftData

struct PlaceRowView: View {
    @Bindable var place: Place
    let allCollections: [PlaceCollection]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var showingCollectionPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: place.category.symbolName)
                    .foregroundStyle(place.category.tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.headline)
                        .strikethrough(place.visited)
                        .foregroundStyle(place.visited ? .secondary : .primary)
                    Text(place.category.label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    if !place.address.isEmpty {
                        Text(place.address)
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
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showingCollectionPicker) {
            CollectionPickerSheet(place: place, allCollections: allCollections)
                .presentationDetents([.medium])
        }
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
