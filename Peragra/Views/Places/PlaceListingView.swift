import SwiftUI
import SwiftData

struct PlaceListingView: View {
    let places: [Place]
    let allCollections: [PlaceCollection]

    @Environment(\.modelContext) private var modelContext
    @State private var search = ""
    @State private var categoryFilter: PlaceCategory?
    @State private var hideVisited = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []

    private var filtered: [Place] {
        places.filter { place in
            if let categoryFilter, place.category != categoryFilter { return false }
            if hideVisited && place.visited { return false }
            if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                let q = search.lowercased()
                let haystack = [place.name, place.address, place.notes].joined(separator: " ").lowercased()
                if !haystack.contains(q) { return false }
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if filtered.isEmpty {
                ContentUnavailableView(
                    "No Places Match",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try clearing a filter or the search text.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { place in
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
                            PlaceRowView(place: place, allCollections: allCollections)
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
            modelContext.delete(filtered[index])
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
