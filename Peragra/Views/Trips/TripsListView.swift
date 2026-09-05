import SwiftUI
import SwiftData

struct TripsListView: View {
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingAddTrip = false
    @State private var showingSettings = false
    @State private var tripPendingDelete: Trip?
    @State private var tripPendingEdit: Trip?

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
                                // Deleting is only offered once the board
                                // has no saved places, same as the "Delete
                                // This Board" option inside a board's own
                                // detail view.
                                if trip.places.isEmpty {
                                    Button(role: .destructive) {
                                        tripPendingDelete = trip
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    tripPendingEdit = trip
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
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
            .sheet(item: $tripPendingEdit) { trip in
                EditTripSheet(trip: trip)
            }
            .safeAreaInset(edge: .bottom) {
                Text("developed by JaiSung Noh, MD. · Version 1.0 · Build 3 · 2026")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
            .confirmationDialog(
                "Delete the empty board \"\(tripPendingDelete?.name ?? "")\"?",
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
        // Checked on cold launch (.task, which .onChange alone wouldn't
        // catch — it only fires on a transition, not the initial value)
        // and every time the app returns to the foreground after that —
        // there's no reliable way to run this while the app isn't open
        // at all without a background-refresh entitlement this app
        // doesn't have wired up.
        .task { AutoBackupService.runIfDue(context: modelContext) }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                AutoBackupService.runIfDue(context: modelContext)
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
