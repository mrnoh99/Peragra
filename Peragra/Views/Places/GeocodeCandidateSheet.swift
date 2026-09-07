import SwiftUI
import MapKit

/// Shown by "Retry" (PlaceRowView) when more than one map provider comes
/// back with a meaningfully different location for the same place — one
/// small map per candidate, so the person can see at a glance which one
/// is actually right and pick it, rather than the app silently trusting
/// whichever provider happened to be configured.
struct GeocodeCandidateSheet: View {
    let placeName: String
    let candidates: [GeocodingService.ProviderResult]
    let onSelect: (GeocodingService.ProviderResult) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates, id: \.provider) { candidate in
                Button {
                    onSelect(candidate)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(candidate.provider.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Map(initialPosition: .region(
                            MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: candidate.result.latitude, longitude: candidate.result.longitude),
                                latitudinalMeters: 900,
                                longitudinalMeters: 900
                            )
                        )) {
                            Marker(placeName, coordinate: CLLocationCoordinate2D(latitude: candidate.result.latitude, longitude: candidate.result.longitude))
                        }
                        .frame(height: 150)
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Choose the Right Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
