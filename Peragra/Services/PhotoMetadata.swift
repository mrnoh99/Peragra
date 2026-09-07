import CoreLocation
import ImageIO

/// Best-effort extraction of a photo's own embedded GPS coordinate and
/// capture time (EXIF) — the fallback source for the on-site photo flow's
/// location/time when the photo's Photos library record (read via
/// PHAsset, when the app has library access) isn't available.
enum PhotoMetadata {
    static func extract(from data: Data) -> (location: CLLocationCoordinate2D?, accuracy: CLLocationAccuracy?, capturedAt: Date?) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return (nil, nil, nil)
        }

        var location: CLLocationCoordinate2D?
        var accuracy: CLLocationAccuracy?
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
           let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
           let longitude = gps[kCGImagePropertyGPSLongitude] as? Double,
           let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
            location = CLLocationCoordinate2D(
                latitude: latitudeRef == "S" ? -latitude : latitude,
                longitude: longitudeRef == "W" ? -longitude : longitude
            )
            // Not every photo carries this — it's an optional EXIF GPS
            // tag — but the iOS Camera app does write it (derived from
            // CLLocation.horizontalAccuracy at the moment of capture).
            accuracy = gps[kCGImagePropertyGPSHPositioningError] as? Double
        }

        var capturedAt: Date?
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            capturedAt = formatter.date(from: dateString)
        }

        return (location, accuracy, capturedAt)
    }
}
