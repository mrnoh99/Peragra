import SwiftUI
import SwiftData

/// A single list combining every place across every trip — "Your Trips"
/// otherwise only lets you view/edit one trip at a time. Each row carries
/// its own trip as a badge, since places here don't share one destination
/// or one set of lists the way they do inside a single trip.
struct AllPlacesView: View {
    @Query(sort: \Place.createdAt, order: .reverse) private var allPlaces: [Place]
    @Environment(\.modelContext) private var modelContext

    @State private var search = ""
    @State private var categoryFilter: PlaceCategory?
    @State private var tripFilter: Trip?
    @State private var editingPlace: Place?
    @State private var placePendingDelete: Place?

    private var filtered: [Place] {
        allPlaces.filter { place in
            if let tripFilter, place.trip?.id != tripFilter.id { return false }
            if let categoryFilter, place.category != categoryFilter { return false }
            if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                let q = search.lowercased()
                let haystack = [place.name, place.address, place.notes].joined(separator: " ").lowercased()
                if !haystack.contains(q) { return false }
            }
            return true
        }
    }

    private var trips: [Trip] {
        let unique = Dictionary(grouping: allPlaces.compactMap(\.trip), by: \.id).compactMapValues(\.first)
        return unique.values.sorted { $0.name < $1.name }
    }

    var body: some View {
        Group {
            if allPlaces.isEmpty {
                ContentUnavailableView(
                    "No Places Saved Yet",
                    systemImage: "mappin.slash",
                    description: Text("Add some from within a trip.")
                )
            } else {
                List {
                    if !trips.isEmpty {
                        Section {
                            Picker("Destination", selection: $tripFilter) {
                                Text("All Destinations").tag(Trip?.none)
                                ForEach(trips) { trip in
                                    Text("\(trip.coverEmoji) \(trip.name)").tag(Trip?.some(trip))
                                }
                            }
                            Picker("Category", selection: $categoryFilter) {
                                Text("All Categories").tag(PlaceCategory?.none)
                                ForEach(PlaceCategory.allCases) { category in
                                    Text(category.label).tag(PlaceCategory?.some(category))
                                }
                            }
                        }
                    }
                    Section {
                        if filtered.isEmpty {
                            Text("No places match.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filtered) { place in
                                AllPlacesRow(place: place, onEdit: { editingPlace = place })
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            placePendingDelete = place
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    } header: {
                        Text("\(filtered.count) place\(filtered.count == 1 ? "" : "s")")
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("All Places")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search places")
        .sheet(item: $editingPlace) { place in
            EditPlaceSheet(place: place)
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
}

private struct AllPlacesRow: View {
    @Bindable var place: Place
    let onEdit: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                withAnimation { place.toggleVisited(context: modelContext) }
            } label: {
                Image(systemName: place.visited ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(place.visited ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if let trip = place.trip {
                        Text("\(trip.coverEmoji) \(trip.name)")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    Text(place.category.label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(place.name)
                    .font(.headline)
                    .foregroundStyle(place.visited ? .red : .primary)
                if !place.address.isEmpty {
                    Text(place.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Edit", action: onEdit)
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            Spacer()
            Button {
                withAnimation { place.toggleFavorite(context: modelContext) }
            } label: {
                Image(systemName: place.favorite ? "star.fill" : "star")
                    .foregroundStyle(place.favorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
