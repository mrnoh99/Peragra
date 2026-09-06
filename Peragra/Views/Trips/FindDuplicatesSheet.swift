import SwiftUI
import SwiftData

/// Scans one board's places for likely duplicates (DuplicatePlaces) and
/// lets the user review each group before merging it — picking which copy
/// stays as the "primary" (keeping its own name/category/coordinates, but
/// filling in anything only a duplicate had) and deleting the rest.
/// Mirrors web/src/components/FindDuplicatesModal.tsx.
struct FindDuplicatesSheet: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [[Place]]
    @State private var primaryIDByGroup: [Int: UUID] = [:]
    @State private var mergedGroupIndexes: Set<Int> = []

    init(trip: Trip) {
        self.trip = trip
        _groups = State(initialValue: DuplicatePlaces.findDuplicateGroups(trip.places))
    }

    private var remainingCount: Int {
        groups.indices.filter { !mergedGroupIndexes.contains($0) }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "No Duplicates Found",
                        systemImage: "checkmark.circle",
                        description: Text("Places need a matching name plus a nearby location or address to be flagged.")
                    )
                } else if remainingCount == 0 {
                    ContentUnavailableView(
                        "All Merged",
                        systemImage: "checkmark.circle",
                        description: Text("All found duplicates have been merged.")
                    )
                } else {
                    List {
                        Section {
                            Text("Found \(remainingCount) group\(remainingCount == 1 ? "" : "s") of places that look like the same spot saved more than once. Pick which one to keep, then merge — the others' notes, phone and links are folded in before they're removed.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                            if !mergedGroupIndexes.contains(groupIndex) {
                                groupSection(groupIndex: groupIndex, group: group)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Find Duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func primaryID(groupIndex: Int, group: [Place]) -> UUID {
        primaryIDByGroup[groupIndex] ?? group[0].id
    }

    private func groupSection(groupIndex: Int, group: [Place]) -> some View {
        let selectedID = primaryID(groupIndex: groupIndex, group: group)
        return Section {
            ForEach(group) { place in
                Button {
                    primaryIDByGroup[groupIndex] = place.id
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: place.id == selectedID ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(place.id == selectedID ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).foregroundStyle(.primary)
                            if !place.address.isEmpty {
                                Text(place.address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Button("Merge into \"\(group.first(where: { $0.id == selectedID })?.name ?? "")\"") {
                merge(groupIndex: groupIndex, group: group)
            }
            .font(.subheadline.weight(.medium))
        }
    }

    private func merge(groupIndex: Int, group: [Place]) {
        let primaryID = primaryID(groupIndex: groupIndex, group: group)
        guard let primary = group.first(where: { $0.id == primaryID }) else { return }
        let duplicates = group.filter { $0.id != primaryID }
        primary.merge(with: duplicates, context: modelContext)
        try? modelContext.save()
        mergedGroupIndexes.insert(groupIndex)
    }
}
