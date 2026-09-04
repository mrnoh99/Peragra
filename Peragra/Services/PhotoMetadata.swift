import CoreLocation
import ImageIO

/// Best-effort extraction of a photo's own embedded GPS coordinate and
/// capture time (EXIF), for photos picked from the library via "Upload
/// Photos" rather than taken live through "Take Photo Here" — those
/// already have a live GPS fix and Date(), so this is only consulted for
/// uploaded photos, which weren't necessarily taken here or now.
enum PhotoMetadata {
    static func extract(from data: Data) -> (location: CLLocationCoordinate2D?, capturedAt: Date?) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return (nil, nil)
        }

        var location: CLLocationCoordinate2D?
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
           let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
           let longitude = gps[kCGImagePropertyGPSLongitude] as? Double,
           let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
            location = CLLocationCoordinate2D(
                latitude: latitudeRef == "S" ? -latitude : latitude,
                longitude: longitudeRef == "W" ? -longitude : longitude
            )
        }

        var capturedAt: Date?
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            capturedAt = formatter.date(from: dateString)
        }

        return (location, capturedAt)
    }
}
