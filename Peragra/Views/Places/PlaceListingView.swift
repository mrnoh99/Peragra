import SwiftUI
import SwiftData

struct PlaceListingView: View {
    /// Already filtered and sorted by the parent (shared with the Map tab).
    let places: [Place]
    let allCollections: [PlaceCollection]
    let distancesByID: [UUID: Double]
    let destination: String
    /// Every board except this one, for the bulk "Move to Board" menu.
    let otherBoards: [Trip]
    /// Switches to the Map tab, narrowed to just these place ids.
    let onViewSelectedOnMap: (Set<UUID>) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var placePendingDelete: Place?

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
                        .swipeActions(edge: .trailing) {
                            if !isSelecting {
                                Button(role: .destructive) {
                                    placePendingDelete = place
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                bulkActionBar
            }
        }
        .confirmationDialog(
            "Delete this place?",
            isPresented: Binding(
                get: { placePendingDelete != nil },
                set: { if !$0 { placePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let placePendingDelete {
                    modelContext.delete(placePendingDelete)
                }
                placePendingDelete = nil
            }
            Button("Cancel", role: .cancel) { placePendingDelete = nil }
        }
    }

    private var bulkActionBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            bulkActionBarControls
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var bulkActionBarControls: some View {
        HStack {
            Text(selectedIDs.isEmpty ? "Select places to edit" : "\(selectedIDs.count) selected")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                toggleSelectAll()
            } label: {
                Text(selectedIDs.count == places.count ? "Deselect All" : "Select All")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(places.isEmpty)
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

            if !otherBoards.isEmpty {
                Menu {
                    ForEach(otherBoards) { board in
                        Button {
                            moveSelected(to: board)
                        } label: {
                            Text("\(board.coverEmoji) \(board.name)")
                        }
                    }
                } label: {
                    Label("Move to Board", systemImage: "arrow.right.square")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(selectedIDs.isEmpty)
            }

            if !allCollections.isEmpty {
                Menu {
                    ForEach(allCollections) { collection in
                        Button {
                            toggleSelected(to: collection)
                        } label: {
                            let title = collectionLabel(collection)
                            if isOnAllSelected(collection) {
                                Label(title, systemImage: "checkmark")
                            } else {
                                Text(title)
                            }
                        }
                    }
                } label: {
                    Label("Send to List", systemImage: "list.bullet")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(selectedIDs.isEmpty)
            }

            Button {
                onViewSelectedOnMap(selectedIDs)
            } label: {
                Label("Show on Map", systemImage: "map")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(selectedIDs.isEmpty)
        }
    }

    private func toggleSelection(_ place: Place) {
        if selectedIDs.contains(place.id) {
            selectedIDs.remove(place.id)
        } else {
            selectedIDs.insert(place.id)
        }
    }

    /// Selects (or deselects) every place currently shown — respects
    /// whatever search/filter is already narrowing `places`.
    private func toggleSelectAll() {
        if selectedIDs.count == places.count {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(places.map { $0.id })
        }
    }

    private func applyCategory(_ category: PlaceCategory) {
        for place in places where selectedIDs.contains(place.id) {
            place.category = category
        }
        selectedIDs.removeAll()
        isSelecting = false
    }

    /// Same as EditPlaceSheet's single-place board move, applied to the
    /// whole selection: custom-list membership doesn't carry over (those
    /// lists belong to the old board), but visited/favorite status is
    /// preserved and re-synced against the new board's own
    /// Visited/Favorites lists.
    private func moveSelected(to newTrip: Trip) {
        let selectedPlaces = places.filter { selectedIDs.contains($0.id) }
        for place in selectedPlaces where place.trip?.id != newTrip.id {
            place.trip = newTrip
            var newCollections: [PlaceCollection] = []
            if place.visited {
                newCollections.append(PlaceCollection.ensureVisitedList(for: newTrip, context: modelContext))
            }
            if place.favorite {
                newCollections.append(PlaceCollection.ensureFavoritesList(for: newTrip, context: modelContext))
            }
            place.collections = newCollections
            place.syncCountryList(context: modelContext)
        }
        selectedIDs.removeAll()
        isSelecting = false
    }

    /// Tri-state: a bulk selection can mix places already in the list with
    /// ones that aren't. If every selected place is already in, this
    /// removes them all (a real "toggle off"); otherwise it adds whichever
    /// aren't in yet. Leaves the selection in place afterward (unlike
    /// applyCategory) so the same places can be sent to another list right
    /// after, since a place can belong to any number of lists at once.
    private func toggleSelected(to collection: PlaceCollection) {
        let allIn = isOnAllSelected(collection)
        for place in places where selectedIDs.contains(place.id) {
            if allIn {
                place.collections.removeAll { $0.id == collection.id }
                if collection.isVisitedList {
                    place.visited = false
                    place.visitedAt = nil
                }
                if collection.isFavoritesList {
                    place.favorite = false
                }
            } else {
                if !place.collections.contains(where: { $0.id == collection.id }) {
                    place.collections.append(collection)
                }
                if collection.isVisitedList {
                    place.visited = true
                    place.visitedAt = .now
                }
                if collection.isFavoritesList {
                    place.favorite = true
                }
            }
        }
    }

    private func collectionLabel(_ collection: PlaceCollection) -> String {
        if collection.isFavoritesList { return "⭐ \(collection.name)" }
        if collection.isVisitedList { return "✅ \(collection.name)" }
        return collection.name
    }

    /// Whether every currently-selected place already belongs to this list.
    private func isOnAllSelected(_ collection: PlaceCollection) -> Bool {
        let selected = places.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return false }
        return selected.allSatisfy { place in place.collections.contains(where: { $0.id == collection.id }) }
    }

}
