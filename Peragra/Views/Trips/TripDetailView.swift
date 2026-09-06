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
    /// Set by PlaceListingView's bulk "Show on Map", so the Map tab can
    /// narrow to just that selection instead of the full filtered listing —
    /// cleared whenever the Map tab is left, so a later manual switch to
    /// it starts from the full list again.
    @State private var mapFilterIDs: Set<UUID>?
    /// Set by a map marker's "View Place Card" control, so the Listing tab
    /// can scroll to and briefly highlight that place — cleared a couple
    /// seconds later, same as PlaceRowView's own transient states.
    @State private var highlightedPlaceID: UUID?
    @State private var showingAddPlace = false
    @State private var showingImportPlaces = false
    @State private var showingAddList = false
    @State private var newListName = ""
    /// A place shows up while every currently-toggled-on list contains it
    /// (AND, not OR) — several lists can be active at once.
    @State private var activeCollectionIDs: Set<UUID> = []

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
    // Visited, then the auto-created country lists, matching the sidebar
    // chip bar's fixed reading order.
    private func defaultListRank(_ collection: PlaceCollection) -> Int {
        if collection.isFavoritesList { return 0 }
        if collection.isVisitedList { return 1 }
        if collection.isCountryList { return 2 }
        return 3
    }

    private var collections: [PlaceCollection] {
        trip.collections.sorted { a, b in
            let rankDiff = defaultListRank(a) - defaultListRank(b)
            if rankDiff != 0 { return rankDiff < 0 }
            if a.isCountryList && b.isCountryList {
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return false
        }
    }

    // Auto country lists are filter-only — a place's membership is fully
    // derived from its address, so they're excluded from the manual "Add
    // to list"/"Send to List" pickers where the user assigns lists by hand.
    private var manualCollections: [PlaceCollection] {
        collections.filter { !$0.isCountryList }
    }

    private var otherBoards: [Trip] {
        allTrips.filter { $0.id != trip.id }
    }

    private var visiblePlaces: [Place] {
        guard !activeCollectionIDs.isEmpty else { return places }
        return places.filter { place in
            activeCollectionIDs.allSatisfy { id in place.collections.contains(where: { $0.id == id }) }
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
    private var mapPlaces: [Place] {
        guard let mapFilterIDs else { return sortedPlaces }
        return sortedPlaces.filter { mapFilterIDs.contains($0.id) }
    }

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
            .onChange(of: tab) { _, newValue in
                if newValue == .listing { mapFilterIDs = nil }
            }

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
                    PlaceListingView(
                        places: sortedPlaces,
                        allCollections: manualCollections,
                        distancesByID: distancesByID,
                        destination: trip.destination,
                        otherBoards: otherBoards,
                        highlightedPlaceID: highlightedPlaceID,
                        onViewSelectedOnMap: { ids in
                            mapFilterIDs = ids
                            tab = .map
                        }
                    )
                } else {
                    VStack(spacing: 0) {
                        if mapFilterIDs != nil {
                            HStack {
                                Text("Showing \(mapPlaces.count) selected place\(mapPlaces.count == 1 ? "" : "s")")
                                Spacer()
                                Button("Show All") { self.mapFilterIDs = nil }
                            }
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.1))
                        }
                        PlaceMapView(places: mapPlaces, destination: trip.destination, onSelectPlace: viewPlaceInListing)
                    }
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
                Button { showingImportPlaces = true } label: { Label("Import Shared Places", systemImage: "square.and.arrow.down") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showingAddList = true } label: { Label("New List", systemImage: "folder.badge.plus") }
            }
        }
        .sheet(isPresented: $showingAddPlace) {
            let defaultCollection = activeCollectionIDs.count == 1 ? collections.first(where: { activeCollectionIDs.contains($0.id) }) : nil
            AddPlaceSheet(trip: trip, defaultCollection: defaultCollection)
        }
        .sheet(isPresented: $showingImportPlaces) {
            ImportPlacesSheet(trip: trip)
        }
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
                chip(title: "All places", isSelected: activeCollectionIDs.isEmpty) { activeCollectionIDs.removeAll() }
                ForEach(collections) { collection in
                    let collectionChip = chip(
                        title: chipTitle(for: collection),
                        isSelected: activeCollectionIDs.contains(collection.id)
                    ) {
                        if activeCollectionIDs.contains(collection.id) {
                            activeCollectionIDs.remove(collection.id)
                        } else {
                            activeCollectionIDs.insert(collection.id)
                        }
                    }
                    // The default Favorites/Visited lists and the
                    // auto-created country lists aren't deletable, so
                    // they get no long-press menu at all.
                    if collection.isFavoritesList || collection.isVisitedList || collection.isCountryList {
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

    /// Switches to the Listing tab and briefly highlights the given place
    /// — called from a map marker's "View Place Card" control.
    private func viewPlaceInListing(_ place: Place) {
        tab = .listing
        let placeID = place.id
        highlightedPlaceID = placeID
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if highlightedPlaceID == placeID { highlightedPlaceID = nil }
        }
    }

    private func deleteCollection(_ collection: PlaceCollection) {
        guard !collection.isFavoritesList, !collection.isVisitedList, !collection.isCountryList else { return }
        activeCollectionIDs.remove(collection.id)
        modelContext.delete(collection)
    }

    private func chipTitle(for collection: PlaceCollection) -> String {
        if collection.isFavoritesList {
            return "⭐ \(collection.name) (\(places.filter(\.favorite).count))"
        }
        if collection.isVisitedList {
            return "✅ \(collection.name) (\(places.filter(\.visited).count))"
        }
        if collection.isCountryList {
            return "🌍 \(collection.name) (\(collection.places.count))"
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
