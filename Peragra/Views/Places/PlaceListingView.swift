import SwiftUI
import SwiftData

struct PlaceListingView: View {
    /// Already filtered and sorted by the parent (shared with the Map tab).
    let places: [Place]
    let allCollections: [PlaceCollection]
    let distancesByID: [UUID: Double]
    let destination: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                FilterChip(title: isSelecting ? "Cancel" : "Select", isSelected: isSelecting) {
                    isSelecting.toggle()
                    if !isSelecting { selectedIDs.removeAll() }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if places.isEmpty {
                ContentUnavailableView(
                    "No Places Match",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try clearing a filter or the search text.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(places) { place in
                        HStack(alignment: .top, spacing: 8) {
                            if isSelecting {
                                Button {
                                    toggleSelection(place)
                                } label: {
                                    Image(systemName: selectedIDs.contains(place.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedIDs.contains(place.id) ? Color.accentColor : .secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 6)
                            }
                            PlaceRowView(place: place, allCollections: allCollections, distanceMeters: distancesByID[place.id], destination: destination)
                        }
                    }
                    .onDelete(perform: isSelecting ? nil : delete)
                }
                .listStyle(.plain)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                bulkActionBar
            }
        }
    }

    private var bulkActionBar: some View {
        HStack {
            Text(selectedIDs.isEmpty ? "Select places to edit" : "\(selectedIDs.count) selected")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(PlaceCategory.allCases) { category in
                    Button {
                        applyCategory(category)
                    } label: {
                        Label(category.label, systemImage: category.symbolName)
                    }
                }
            } label: {
                Label("Change Category", systemImage: "tag")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(selectedIDs.isEmpty)

            if !allCollections.isEmpty {
                Menu {
                    ForEach(allCollections) { collection in
                        Button {
                            addSelected(to: collection)
                        } label: {
                            Text(collection.name)
                        }
                    }
                } label: {
                    Label("Send to List", systemImage: "list.bullet")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(selectedIDs.isEmpty)
            }

            Button {
                sendSelectedToGoogleMaps()
            } label: {
                Label("Send to Maps", systemImage: "map")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func toggleSelection(_ place: Place) {
        if selectedIDs.contains(place.id) {
            selectedIDs.remove(place.id)
        } else {
            selectedIDs.insert(place.id)
        }
    }

    private func applyCategory(_ category: PlaceCategory) {
        for place in places where selectedIDs.contains(place.id) {
            place.category = category
        }
        selectedIDs.removeAll()
        isSelecting = false
    }

    /// Adds rather than toggles — a bulk selection can mix places already
    /// in the list with ones that aren't, and "send to list" should only
    /// ever add, never accidentally remove someone who was already there.
    private func addSelected(to collection: PlaceCollection) {
        for place in places where selectedIDs.contains(place.id) {
            if !place.collections.contains(where: { $0.id == collection.id }) {
                place.collections.append(collection)
            }
        }
        selectedIDs.removeAll()
        isSelecting = false
    }

    private func sendSelectedToGoogleMaps() {
        // Keep the current list order (not selection-tap order) so the
        // resulting route reads top-to-bottom the way the list does.
        let selectedPlaces = places.filter { selectedIDs.contains($0.id) }
        guard let url = GoogleMapsOpener.directionsURL(for: selectedPlaces, tripDestination: destination) else { return }
        openURL(url)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(places[index])
        }
    }
}
