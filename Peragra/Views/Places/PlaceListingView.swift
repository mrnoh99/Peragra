import SwiftUI
import SwiftData
import CoreLocation

private enum SortMode: String, CaseIterable, Identifiable {
    case defaultOrder = "Default"
    case name = "Name"
    case distance = "Distance"
    var id: String { rawValue }
}

struct PlaceListingView: View {
    let places: [Place]
    let allCollections: [PlaceCollection]

    @Environment(\.modelContext) private var modelContext
    @State private var search = ""
    @State private var categoryFilter: PlaceCategory?
    @State private var hideVisited = false
    @State private var favoritesOnly = false
    @State private var sortMode: SortMode = .defaultOrder
    @State private var referencePlaceID: UUID?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []

    private var filtered: [Place] {
        places.filter { place in
            if let categoryFilter, place.category != categoryFilter { return false }
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

    private var referencePlace: Place? {
        guard let referencePlaceID else { return nil }
        return places.first { $0.id == referencePlaceID }
    }

    /// Distance in meters from the chosen reference place, keyed by place
    /// id — computed once and reused for both sorting and the "N km away"
    /// label on each row, rather than recomputing per row.
    private var distancesByID: [UUID: Double] {
        guard sortMode == .distance, let refCoordinate = referencePlace?.coordinate2D else { return [:] }
        let refLocation = CLLocation(latitude: refCoordinate.latitude, longitude: refCoordinate.longitude)
        var result: [UUID: Double] = [:]
        for place in filtered {
            guard let coordinate = place.coordinate2D else { continue }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            result[place.id] = location.distance(from: refLocation)
        }
        return result
    }

    private var sorted: [Place] {
        switch sortMode {
        case .defaultOrder:
            return filtered
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .distance:
            guard !distancesByID.isEmpty else { return filtered }
            let distances = distancesByID
            return filtered.sorted {
                (distances[$0.id] ?? .greatestFiniteMagnitude) < (distances[$1.id] ?? .greatestFiniteMagnitude)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if sorted.isEmpty {
                ContentUnavailableView(
                    "No Places Match",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try clearing a filter or the search text.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(sorted) { place in
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
                            PlaceRowView(place: place, allCollections: allCollections, distanceMeters: distancesByID[place.id])
                        }
                    }
                    .onDelete(perform: isSelecting ? nil : delete)
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $search, prompt: "Search saved places")
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                bulkActionBar
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach(PlaceCategory.allCases) { category in
                    FilterChip(title: category.label, isSelected: categoryFilter == category) {
                        categoryFilter = (categoryFilter == category) ? nil : category
                    }
                }
                Divider().frame(height: 20)
                FilterChip(title: "Hide visited", isSelected: hideVisited) {
                    hideVisited.toggle()
                }
                FilterChip(title: "★ Favorites", isSelected: favoritesOnly) {
                    favoritesOnly.toggle()
                }
                Divider().frame(height: 20)
                sortMenu
                if sortMode == .distance {
                    referencePlaceMenu
                }
                Divider().frame(height: 20)
                FilterChip(title: isSelecting ? "Cancel" : "Select", isSelected: isSelecting) {
                    isSelecting.toggle()
                    if !isSelecting { selectedIDs.removeAll() }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortMode.allCases) { mode in
                Button {
                    sortMode = mode
                    if mode != .distance { referencePlaceID = nil }
                } label: {
                    if sortMode == mode {
                        Label(mode.rawValue, systemImage: "checkmark")
                    } else {
                        Text(mode.rawValue)
                    }
                }
            }
        } label: {
            FilterChipLabel(title: "Sort: \(sortMode.rawValue)", isSelected: sortMode != .defaultOrder)
        }
    }

    private var referencePlaceMenu: some View {
        Menu {
            ForEach(places.filter { $0.coordinate2D != nil }) { place in
                Button(place.name) { referencePlaceID = place.id }
            }
        } label: {
            FilterChipLabel(
                title: referencePlace.map { "From: \($0.name)" } ?? "Choose a place…",
                isSelected: referencePlace != nil
            )
        }
        .disabled(places.allSatisfy { $0.coordinate2D == nil })
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

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sorted[index])
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FilterChipLabel(title: title, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

/// Same pill styling as FilterChip, without its own tap action — for a
/// chip that's the label of something else (a Menu) rather than a plain
/// toggle button.
private struct FilterChipLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
    }
}
