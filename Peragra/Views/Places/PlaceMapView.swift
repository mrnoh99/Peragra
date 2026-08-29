import SwiftUI
import MapKit

struct PlaceMapView: View {
    let places: [Place]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedPlace: Place?

    private var located: [Place] {
        places.filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var unlocatedCount: Int { places.count - located.count }

    var body: some View {
        VStack(spacing: 0) {
            if unlocatedCount > 0 {
                Label(
                    "\(unlocatedCount) place\(unlocatedCount > 1 ? "s" : "") couldn't be placed on the map — add a more specific address.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if located.isEmpty {
                ContentUnavailableView(
                    "No Located Places Yet",
                    systemImage: "map",
                    description: Text("Save a place with an address to see it here.")
                )
                .frame(maxHeight: .infinity)
            } else {
                Map(position: $cameraPosition, selection: $selectedPlace) {
                    ForEach(located) { place in
                        Marker(place.name, systemImage: place.category.symbolName, coordinate: coordinate(for: place))
                            .tint(place.visited ? .gray : place.category.tint)
                            .tag(place)
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .safeAreaInset(edge: .bottom) {
                    if let selectedPlace {
                        SelectedPlaceCard(place: selectedPlace)
                            .padding()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .onAppear { fitCamera() }
                .onChange(of: located.map(\.id)) { _, _ in fitCamera() }
            }
        }
    }

    private func coordinate(for place: Place) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude ?? 0, longitude: place.longitude ?? 0)
    }

    private func fitCamera() {
        let coordinates = located.map(coordinate(for:))
        guard !coordinates.isEmpty else { return }
        if coordinates.count == 1 {
            cameraPosition = .region(
                MKCoordinateRegion(center: coordinates[0], latitudinalMeters: 1500, longitudinalMeters: 1500)
            )
            return
        }
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.02),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.6, 0.02)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct SelectedPlaceCard: View {
    let place: Place
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.name).font(.headline)
            if !place.address.isEmpty {
                Text(place.address).font(.subheadline).foregroundStyle(.secondary)
            }
            if let url = place.instagramURL {
                Button("View on Instagram") { openURL(url) }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.pink)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 4)
    }
}
