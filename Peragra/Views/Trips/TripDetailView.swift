import SwiftUI
import SwiftData
import CoreLocation
import UIKit

private enum DetailTab: String, CaseIterable {
    case listing = "Listing"
    case map = "Map"
}

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Query private var places: [Place]

    @Environment(\.modelContext) private var modelContext
    @State private var tab: DetailTab = .listing
    @State private var showingAddPlace = false
    @State private var showingAddList = false
    @State private var newListName = ""
    @State private var activeCollection: PlaceCollection?
    @State private var kmlShareURL: URL?
    @State private var showingShareSheet = false
    @State private var hasExportablePlaces = false

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

    // Visited is a default list — keep it pinned first, ahead of whatever
    // order the user's own lists were created in.
    private var collections: [PlaceCollection] {
        trip.collections.sorted { $0.isVisitedList && !$1.isVisitedList }
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
                    Button("Save Your First Place") { showingAddPlace = true }
                        .buttonStyle(.borderedProminent)
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
                    PlaceListingView(places: sortedPlaces, allCollections: collections, distancesByID: distancesByID, destination: trip.destination)
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
                Button { showingAddPlace = true } label: { Label("Save a Place", systemImage: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showingAddList = true } label: { Label("New List", systemImage: "folder.badge.plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { exportToGoogleMaps() } label: {
                    if let activeCollection {
                        Label("Export \"\(activeCollection.name)\"", systemImage: "square.and.arrow.up")
                    } else {
                        Label("Export to Google Maps", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(!hasExportablePlaces)
            }
        }
        .sheet(isPresented: $showingAddPlace) { AddPlaceSheet(trip: trip, defaultCollection: activeCollection) }
        .sheet(isPresented: $showingShareSheet) { if let kmlShareURL { ShareSheet(activityItems: [kmlShareURL]) } }
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
        .onAppear {
            // Trips created before the Visited-list feature don't have
            // one yet — back-fill it lazily so it always shows in the
            // list chips, not just after the first place gets marked
            // visited.
            _ = PlaceCollection.ensureVisitedList(for: trip, context: modelContext)
            refreshExportState()
        }
        .onChange(of: sortedPlaces) { _, _ in refreshExportState() }
        .onChange(of: showingAddPlace) { _, isShowing in
            if !isShowing { refreshExportState() }
        }
    }

    private func refreshExportState() {
        hasExportablePlaces = sortedPlaces.contains { $0.latitude != nil }
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
                ForEach(collections) { collection in
                    chip(
                        title: collection.isVisitedList ? "✅ \(collection.name)" : collection.name,
                        isSelected: activeCollection?.id == collection.id
                    ) {
                        activeCollection = (activeCollection?.id == collection.id) ? nil : collection
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func exportToGoogleMaps() {
        let title = activeCollection.map { "Peragra - \(trip.name) - \($0.name)" } ?? "Peragra - \(trip.name)"
        let kml = KMLService.generateKML(title: title, places: sortedPlaces)
        let safeName = title.replacingOccurrences(of: "[^\\w\\- ]+", with: "", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).kml")
        do {
            try kml.write(to: url, atomically: true, encoding: .utf8)
            kmlShareURL = url
            showingShareSheet = true
        } catch { }
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

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
