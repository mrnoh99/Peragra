import SwiftUI

enum PlaceSortMode: String, CaseIterable, Identifiable {
    case defaultOrder = "By Category"
    case name = "Name"
    case distance = "Distance"
    var id: String { rawValue }
}

/// The category/visited/favorites/sort controls, shared by the Listing and
/// Map tabs (via TripDetailView, which owns the filter state and computes
/// the filtered+sorted place list both tabs render) so switching tabs
/// doesn't reset what you were looking at, and the map can be narrowed
/// down the same way the list can.
struct PlaceFilterBar: View {
    @Binding var categoryFilter: PlaceCategory?
    let categoryCounts: [PlaceCategory: Int]
    let totalCount: Int
    @Binding var hideVisited: Bool
    @Binding var favoritesOnly: Bool
    @Binding var sortMode: PlaceSortMode
    @Binding var referencePlaceID: UUID?
    /// Places with a resolved coordinate, offered as choices for "Distance from…".
    let locatablePlaces: [Place]

    private var referencePlace: Place? {
        guard let referencePlaceID else { return nil }
        return locatablePlaces.first { $0.id == referencePlaceID }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All (\(totalCount))", isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach(PlaceCategory.allCases) { category in
                    FilterChip(title: "\(category.label) (\(categoryCounts[category] ?? 0))", isSelected: categoryFilter == category) {
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
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(PlaceSortMode.allCases) { mode in
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
            ForEach(locatablePlaces) { place in
                Button(place.name) { referencePlaceID = place.id }
            }
        } label: {
            FilterChipLabel(
                title: referencePlace.map { "From: \($0.name)" } ?? "Choose a place…",
                isSelected: referencePlace != nil
            )
        }
        .disabled(locatablePlaces.isEmpty)
    }
}

struct FilterChip: View {
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
struct FilterChipLabel: View {
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
