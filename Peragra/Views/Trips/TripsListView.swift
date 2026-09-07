import SwiftUI
import SwiftData
import UIKit

struct TripsListView: View {
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingAddTrip = false
    @State private var showingSettings = false
    @State private var tripPendingDelete: Trip?
    @State private var tripPendingEdit: Trip?
    @State private var showingCloudRestoreAlert = false
    @State private var showingImportBoard = false

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
                                ExportBoardMenu(trip: trip)
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
                    Menu {
                        Button {
                            showingAddTrip = true
                        } label: {
                            Label("New Board", systemImage: "plus")
                        }
                        Button {
                            showingImportBoard = true
                        } label: {
                            Label("Import Board", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
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
            .sheet(isPresented: $showingImportBoard) {
                ImportBoardSheet()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet()
            }
            .sheet(item: $tripPendingEdit) { trip in
                EditTripSheet(trip: trip)
            }
            .safeAreaInset(edge: .bottom) {
                Text("developed by JaiSung Noh, MD. · Version 1.0 · Build 4 · 2026")
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
            .alert("Restored From iCloud", isPresented: $showingCloudRestoreAlert) {
                Button("OK") {}
            } message: {
                Text("Found a previous backup in iCloud and restored your boards and places automatically.")
            }
        }
        // Checked on cold launch (.task, which .onChange alone wouldn't
        // catch — it only fires on a transition, not the initial value)
        // and every time the app returns to the foreground after that —
        // there's no reliable way to run this while the app isn't open
        // at all without a background-refresh entitlement this app
        // doesn't have wired up. The iCloud restore check runs first, so
        // a legitimately empty fresh install doesn't get immediately
        // overwritten by the backup call that follows it.
        .task {
            AutoBackupService.runIfDue(context: modelContext)
            await restoreFromCloudIfNeeded()
            // Backfills country-list membership for every place, not just
            // ones that go through an add/edit/geocode/board-move from here
            // on — syncCountryList only ever ran on those events, so a
            // place already geocoded before country lists existed (or
            // before its own last edit) was never going to get classified
            // on its own.
            Place.syncAllCountryLists(context: modelContext)
            await CloudBackupService.backup(context: modelContext)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                AutoBackupService.runIfDue(context: modelContext)
                Task { await CloudBackupService.backup(context: modelContext) }
            } else if newPhase == .background {
                // The most likely moment to be uninstalled next — worth
                // one more up-to-date snapshot in iCloud right before
                // that could happen.
                Task { await CloudBackupService.backup(context: modelContext) }
            }
        }
    }

    /// If this device has no local data at all — most likely because the
    /// app was just deleted and reinstalled — and a previous snapshot
    /// exists in iCloud, restores it automatically rather than leaving
    /// the person to notice everything is gone and dig through Settings
    /// for the manual restore flow.
    private func restoreFromCloudIfNeeded() async {
        guard trips.isEmpty, await CloudBackupService.hasRestorableBackup() else { return }
        if await CloudBackupService.restoreIfAvailable(context: modelContext) {
            showingCloudRestoreAlert = true
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

/// A board's whole-board export — every place and list, with real
/// coordinates and visited/favorite status intact (unlike sharing a
/// handful of place cards, which strips all of that as
/// sender-board-specific). Its own small view (rather than inline in
/// TripRow) so each row's export file only gets generated once its
/// swipe actions actually get revealed, not for every row up front.
private struct ExportBoardMenu: View {
    let trip: Trip

    @State private var fileURL: URL?
    @State private var message: String?

    var body: some View {
        Menu {
            Button {
                copyAsText()
            } label: {
                Label("Copy as Text", systemImage: "doc.on.doc")
            }
            if let fileURL {
                ShareLink(item: fileURL) {
                    Label("Share as File", systemImage: "doc")
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .tint(.gray)
        .onAppear { refresh() }
        .alert("Board Shared", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    private func refresh() {
        guard let data = try? BackupService.exportBoard(trip) else {
            fileURL = nil
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(BackupService.boardFilename(for: trip))
        fileURL = (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    private func copyAsText() {
        guard let data = try? BackupService.exportBoard(trip), let text = String(data: data, encoding: .utf8) else {
            message = "Couldn't prepare this board for copying."
            return
        }
        UIPasteboard.general.string = text
        message = "Copied \"\(trip.name)\" — paste it anywhere to share."
    }
}

#Preview {
    TripsListView()
        .modelContainer(for: [Trip.self, Place.self, PlaceCollection.self], inMemory: true)
}
