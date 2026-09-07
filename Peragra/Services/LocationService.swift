import CoreLocation

/// One-shot fetch of the device's current coordinate, for tagging a place
/// with exactly where its "Take Photo Here" photo was taken. A live GPS
/// fix like this is used only for a photo captured right now through the
/// camera — an uploaded photo wasn't necessarily taken here or now, so
/// that path reads the photo's own location (Photos library record, or
/// EXIF) instead of this.
final class LocationService: NSObject, CLLocationManagerDelegate {
    /// A coordinate alongside the fix's own reported horizontalAccuracy
    /// (meters) — used to size how wide a nearby-places search needs to
    /// be (see NearbyPlacesService.radius(for:accuracy:)) instead of
    /// assuming one fixed distance always covers whatever margin of
    /// error this particular fix actually has.
    struct Fix {
        let coordinate: CLLocationCoordinate2D
        let accuracy: CLLocationAccuracy
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Fix?, Never>?

    static func currentLocation() async -> Fix? {
        let service = LocationService()
        return await service.fetch()
    }

    private func fetch() async -> Fix? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                finish(with: nil)
            }
            // A denied/restricted authorization never calls back, and even
            // an authorized fetch can hang (poor signal, background
            // throttling) — this guarantees the caller isn't stuck
            // waiting forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            finish(with: nil)
            return
        }
        finish(with: Fix(coordinate: location.coordinate, accuracy: location.horizontalAccuracy))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }

    private func finish(with fix: Fix?) {
        continuation?.resume(returning: fix)
        continuation = nil
    }
}
