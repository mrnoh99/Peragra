import SwiftUI
import SwiftData

struct TripsListView: View {
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddTrip = false
    @State private var showingSettings = false
    @State private var tripPendingDelete: Trip?

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    emptyState
                } else {
                    List {
                        NavigationLink {
                            AllPlacesView()
                        } label: {
                            Label("All Places", systemImage: "list.bullet")
                        }
                        ForEach(trips) { trip in
                            NavigationLink(value: trip) {
                                TripRow(trip: trip)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    tripPendingDelete = trip
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Your Boards")
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddTrip = true
                    } label: {
                        Label("New Board", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("AI Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingAddTrip) {
                AddTripSheet()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet()
            }
            .safeAreaInset(edge: .bottom) {
                Text("developed by JaiSung Noh, MD. · Version 1.0 · Build 2 · 2026")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
            .confirmationDialog(
                "Delete this board and all its saved places?",
                isPresented: Binding(
                    get: { tripPendingDelete != nil },
                    set: { if !$0 { tripPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Board", role: .destructive) {
                    if let trip = tripPendingDelete {
                        modelContext.delete(trip)
                    }
                    tripPendingDelete = nil
                }
                Button("Cancel", role: .cancel) { tripPendingDelete = nil }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Boards Yet", systemImage: "airplane.departure")
        } description: {
            Text("Create a board for a destination, then start saving the restaurants, cafes and attractions you've saved on Instagram.")
        } actions: {
            Button("Create Your First Board") { showingAddTrip = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct TripRow: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: 14) {
            Text(trip.coverEmoji)
                .font(.system(size: 32))
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name)
                    .font(.headline)
                Text(trip.destination)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(trip.places.count) saved places")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TripsListView()
        .modelContainer(for: [Trip.self, Place.self, PlaceCollection.self], inMemory: true)
}
