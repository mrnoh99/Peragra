import SwiftUI
import SwiftData
import CoreLocation

private enum DetailTab: String, CaseIterable {
    case listing = "Listing"
    case map = "Map"
}

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Query private var places: [Place]
    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeleteBoard = false
    @State private var tab: DetailTab = .listing
    @State private var showingAddPlace = false
    @State private var showingAddList = false
    @State private var newListName = ""
    @State private var activeCollection: PlaceCollection?
    @State private var isRenamingTrip = false
    @State private var tripNameInput = ""

    // Filter/sort state shared by the Listing and Map tabs, so switching
    // tabs doesn't reset what you were looking at and the map can be
    // narrowed down the same way the list can.
    @State private var search = ""
    @State private var categoryFilter: PlaceCategory?
    @State private var hideVisited = false
    @State private var favoritesOnly = false
    @State private var sortMode: PlaceSortMode = .defaultOrder
    @State private var referencePlaceID: UUID?

    init(trip: Trip) {
        self.trip = trip
        let tripID = trip.id
        _places = Query(filter: #Predicate<Place> { $0.trip?.id == tripID })
    }

    // Default lists are pinned ahead of whatever order the user's own
    // lists were created in — Favorites right after "All places", then
    // Visited, matching the sidebar chip bar's fixed reading order.
    private func defaultListRank(_ collection: PlaceCollection) -> Int {
        if collection.isFavoritesList { return 0 }
        if collection.isVisitedList { return 1 }
        return 2
    }

    private var collections: [PlaceCollection] {
        trip.collections.sorted { defaultListRank($0) < defaultListRank($1) }
    }

    private var otherBoards: [Trip] {
        allTrips.filter { $0.id != trip.id }
    }

    /// Where the user's own lists start, so the chip bar can draw a
    /// divider separating them from the default Favorites/Visited lists.
    private var firstCustomListIndex: Int? {
        collections.firstIndex { !$0.isFavoritesList && !$0.isVisitedList }
    }

    private var visiblePlaces: [Place] {
        guard let activeCollection else { return places }
        return places.filter { place in
            place.collections.contains(where: { $0.id == activeCollection.id })
        }
    }

    /// Everything except the category filter itself — used both to build
    /// the list and to count how many places each category chip would
    /// show, so those counts reflect the other active filters (search,
    /// favorites, ...) rather than going stale next to them.
    private var preCategoryFiltered: [Place] {
        visiblePlaces.filter { place in
            if hideVisited && place.visited { return false }
            if favoritesOnly && !place.favorite { return false }
            if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                let q = search.lowercased()
                let haystack = [place.name, place.address, place.notes].joined(separator: " ").lowercased()
                if !haystack.contains(q) { return false }
            }
            return true
        }
    }

    private var categoryCounts: [PlaceCategory: Int] {
        Dictionary(grouping: preCategoryFiltered, by: \.category).mapValues(\.count)
    }

    private var categoryFilteredPlaces: [Place] {
        guard let categoryFilter else { return preCategoryFiltered }
        return preCategoryFiltered.filter { $0.category == categoryFilter }
    }

    private var referencePlace: Place? {
        guard let referencePlaceID else { return nil }
        return visiblePlaces.first { $0.id == referencePlaceID }
    }

    /// Distance in meters from the chosen reference place, keyed by place
    /// id — computed once and reused for both sorting and the "N km away"
    /// label on each row, rather than recomputing per row.
    private var distancesByID: [UUID: Double] {
        guard sortMode == .distance, let refCoordinate = referencePlace?.coordinate2D else { return [:] }
        let refLocation = CLLocation(latitude: refCoordinate.latitude, longitude: refCoordinate.longitude)
        var result: [UUID: Double] = [:]
        for place in categoryFilteredPlaces {
            guard let coordinate = place.coordinate2D else { continue }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            result[place.id] = location.distance(from: refLocation)
        }
        return result
    }

    /// Filtered (search, category, visited, favorites) and sorted — the
    /// exact set both the Listing and Map tabs render, and what Export
    /// writes out.
    private var sortedPlaces: [Place] {
        // Favorited places float to the top no matter which sort mode is
        // active — the mode only decides ordering within/below that.
        if categoryFilteredPlaces.contains(where: \.favorite) {
            let favorites = categoryFilteredPlaces.filter(\.favorite)
            let rest = categoryFilteredPlaces.filter { !$0.favorite }
            return sortedByMode(favorites) + sortedByMode(rest)
        }
        return sortedByMode(categoryFilteredPlaces)
    }

    private func sortedByMode(_ places: [Place]) -> [Place] {
        switch sortMode {
        case .defaultOrder:
            // Grouped by category (in the app's usual category order),
            // alphabetical by name within each group.
            return places.sorted { a, b in
                if a.category != b.category {
                    let orderA = PlaceCategory.allCases.firstIndex(of: a.category) ?? 0
                    let orderB = PlaceCategory.allCases.firstIndex(of: b.category) ?? 0
                    return orderA < orderB
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        case .name:
            return places.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .distance:
            guard !distancesByID.isEmpty else { return places }
            let distances = distancesByID
            return places.sorted {
                (distances[$0.id] ?? .greatestFiniteMagnitude) < (distances[$1.id] ?? .greatestFiniteMagnitude)
            }
        }
    }

    private var locatablePlaces: [Place] {
        visiblePlaces.filter { $0.coordinate2D != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !collections.isEmpty {
                collectionFilterBar
            }
            Picker("View", selection: $tab) {
                ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if places.isEmpty {
                ContentUnavailableView {
                    Label("No Places Saved Yet", systemImage: "mappin.slash")
                } description: {
                    Text("Paste a link from a post you saved on Instagram, or add a place by hand, to start building your \(trip.destination) itinerary.")
                } actions: {
                    Button("Add Places") { showingAddPlace = true }
                        .buttonStyle(.borderedProminent)
                    Button("Delete This Board", role: .destructive) {
                        isConfirmingDeleteBoard = true
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                PlaceFilterBar(
                    categoryFilter: $categoryFilter,
                    categoryCounts: categoryCounts,
                    totalCount: preCategoryFiltered.count,
                    hideVisited: $hideVisited,
                    favoritesOnly: $favoritesOnly,
                    sortMode: $sortMode,
                    referencePlaceID: $referencePlaceID,
                    locatablePlaces: locatablePlaces
                )
                if tab == .listing {
                    PlaceListingView(places: sortedPlaces, allCollections: collections, distancesByID: distancesByID, destination: trip.destination, otherBoards: otherBoards)
                } else {
                    PlaceMapView(places: sortedPlaces, destination: trip.destination)
                }
            }
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search saved places")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddPlace = true } label: { Label("Add Places", systemImage: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showingAddList = true } label: { Label("New List", systemImage: "folder.badge.plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    tripNameInput = trip.name
                    isRenamingTrip = true
                } label: { Label("Rename Board", systemImage: "pencil") }
            }
        }
        .sheet(isPresented: $showingAddPlace) { AddPlaceSheet(trip: trip, defaultCollection: activeCollection) }
        .alert("New List", isPresented: $showingAddList) {
            TextField("List name", text: $newListName)
            Button("Add") {
                let trimmed = newListName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let collection = PlaceCollection(name: trimmed, trip: trip)
                modelContext.insert(collection)
                newListName = ""
            }
            Button("Cancel", role: .cancel) { newListName = "" }
        }
        .alert("Rename Trip", isPresented: $isRenamingTrip) {
            TextField("Board name", text: $tripNameInput)
            Button("Save") {
                let trimmed = tripNameInput.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { trip.name = trimmed }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete the empty board \"\(trip.name)\"?",
            isPresented: $isConfirmingDeleteBoard,
            titleVisibility: .visible
        ) {
            Button("Delete Board", role: .destructive) {
                modelContext.delete(trip)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            // Trips created before the Visited/Favorites-list feature
            // don't have them yet — back-fill lazily so they always show
            // in the chip bar, not just after the first place gets
            // marked visited/favorited.
            _ = PlaceCollection.ensureFavoritesList(for: trip, context: modelContext)
            _ = PlaceCollection.ensureVisitedList(for: trip, context: modelContext)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trip.destination).font(.subheadline).foregroundStyle(.secondary)
            Text("\(places.count) saved place\(places.count == 1 ? "" : "s") · \(places.filter(\.visited).count) visited")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var collectionFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All places", isSelected: activeCollection == nil) { activeCollection = nil }
                ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                    if index > 0, index == firstCustomListIndex {
                        Divider().frame(height: 20)
                    }
                    let collectionChip = chip(
                        title: chipTitle(for: collection),
                        isSelected: activeCollection?.id == collection.id
                    ) {
                        activeCollection = (activeCollection?.id == collection.id) ? nil : collection
                    }
                    // The default Favorites/Visited lists aren't
                    // deletable, so they get no long-press menu at all.
                    if collection.isFavoritesList || collection.isVisitedList {
                        collectionChip
                    } else {
                        collectionChip.contextMenu {
                            Button(role: .destructive) {
                                deleteCollection(collection)
                            } label: {
                                Label("Delete List", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func deleteCollection(_ collection: PlaceCollection) {
        guard !collection.isFavoritesList, !collection.isVisitedList else { return }
        if activeCollection?.id == collection.id {
            activeCollection = nil
        }
        modelContext.delete(collection)
    }

    private func chipTitle(for collection: PlaceCollection) -> String {
        if collection.isFavoritesList {
            return "⭐ \(collection.name) (\(places.filter(\.favorite).count))"
        }
        if collection.isVisitedList {
            return "✅ \(collection.name) (\(places.filter(\.visited).count))"
        }
        return collection.name
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
