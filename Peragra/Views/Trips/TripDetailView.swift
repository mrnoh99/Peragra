import SwiftUI
import SwiftData
import UIKit

private enum DetailTab: String, CaseIterable {
    case listing = "Listing"
    case map = "Map"
}

struct TripDetailView: View {
    @Bindable var trip: Trip

    @Environment(\.modelContext) private var modelContext
    @State private var tab: DetailTab = .listing
    @State private var showingAddPlace = false
    @State private var showingAddList = false
    @State private var newListName = ""
    @State private var activeCollection: PlaceCollection?
    @State private var kmlShareURL: URL?
    @State private var showingShareSheet = false

    private var places: [Place] { trip.places }
    private var collections: [PlaceCollection] { trip.collections }

    private var visiblePlaces: [Place] {
        guard let activeCollection else { return places }
        return places.filter { place in
            place.collections.contains(where: { $0.id == activeCollection.id })
        }
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
            } else if tab == .listing {
                PlaceListingView(places: visiblePlaces, allCollections: collections)
            } else {
                PlaceMapView(places: visiblePlaces)
            }
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddPlace = true
                } label: {
                    Label("Save a Place", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingAddList = true
                } label: {
                    Label("New List", systemImage: "folder.badge.plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    exportToGoogleMaps()
                } label: {
                    if let activeCollection {
                        Label("Export \"\(activeCollection.name)\"", systemImage: "square.and.arrow.up")
                    } else {
                        Label("Export to Google Maps", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(!visiblePlaces.contains { $0.latitude != nil })
            }
        }
        .sheet(isPresented: $showingAddPlace) {
            AddPlaceSheet(trip: trip, defaultCollection: activeCollection)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let kmlShareURL {
                ShareSheet(activityItems: [kmlShareURL])
            }
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trip.destination)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(places.count) saved place\(places.count == 1 ? "" : "s") · \(places.filter(\.visited).count) visited")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var collectionFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All places", isSelected: activeCollection == nil) {
                    activeCollection = nil
                }
                ForEach(collections) { collection in
                    chip(title: collection.name, isSelected: activeCollection?.id == collection.id) {
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
        let kml = KMLService.generateKML(title: title, places: visiblePlaces)
        let safeName = title.replacingOccurrences(of: "[^\\w\\- ]+", with: "", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).kml")
        do {
            try kml.write(to: url, atomically: true, encoding: .utf8)
            kmlShareURL = url
            showingShareSheet = true
        } catch {
            // Nothing to share if the write failed — no destructive state
            // to clean up either way.
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
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

/// Wraps UIActivityViewController so exporting a KML file can use the
/// system share sheet (Files, AirDrop, Mail, ...) — SwiftUI's ShareLink
/// needs its item synchronously at view-build time, which doesn't fit
/// generating the file on demand when the export button is tapped.
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
