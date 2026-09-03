import Foundation

/// KML export/import — the closest thing to a "send this list to Google
/// Maps" feature that's actually possible: Google has no public API for a
/// user's personal Saved-places lists, but Google My Maps
/// (mymaps.google.com) can import a KML file as a new named map, and export
/// one back out. So "syncing with Google Maps" here means: generate a KML
/// file titled "Peragra - <trip>" for the user to import into My Maps, and
/// parse a KML file (one they exported from My Maps) back into candidate
/// places to review before saving — same flow as caption/AI extraction.
/// Mirrors web/src/lib/kml.ts.
enum KMLService {
    struct KmlPlace {
        let name: String?
        let address: String?
        let latitude: Double?
        let longitude: Double?
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func generateKML(title: String, places: [Place]) -> String {
        let located = places.filter { $0.latitude != nil && $0.longitude != nil }

        let placemarks = located.map { place -> String in
            let descriptionParts = [place.address, place.notes].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let description = descriptionParts.joined(separator: " — ")
            let descriptionLine = description.isEmpty ? "" : "\n      <description>\(escapeXML(description))</description>"
            // KML coordinate order is longitude,latitude[,altitude] — the
            // reverse of how this app (and most UIs) writes lat/lng.
            return """
                <Placemark>
                  <name>\(escapeXML(place.name))</name>\(descriptionLine)
                  <Point><coordinates>\(place.longitude ?? 0),\(place.latitude ?? 0),0</coordinates></Point>
                </Placemark>
                """
        }.joined(separator: "\n")

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <kml xmlns="http://www.opengis.net/kml/2.2">
              <Document>
                <name>\(escapeXML(title))</name>
                <Folder>
                  <name>\(escapeXML(title))</name>
            \(placemarks)
                </Folder>
              </Document>
            </kml>

            """
    }

    static func parsePlaces(from data: Data) -> [KmlPlace] {
        let parser = XMLParser(data: data)
        let delegate = KMLParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.places.filter { $0.name != nil || ($0.latitude != nil && $0.longitude != nil) }
    }
}

private final class KMLParserDelegate: NSObject, XMLParserDelegate {
    var places: [KMLService.KmlPlace] = []

    private var currentElement = ""
    private var currentText = ""
    private var inPlacemark = false

    private var name: String?
    private var description: String?
    private var coordinates: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "Placemark" {
            inPlacemark = true
            name = nil
            description = nil
            coordinates = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inPlacemark {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard inPlacemark else { return }

        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "name":
            if name == nil { name = trimmed }
        case "description":
            if description == nil { description = trimmed }
        case "coordinates":
            if coordinates == nil { coordinates = trimmed }
        case "Placemark":
            var latitude: Double?
            var longitude: Double?
            // "lng,lat[,alt]" — Placemarks can list multiple whitespace-
            // separated coordinate tuples (for lines/polygons); a Point
            // only ever has one, which is all this app imports.
            if let coordinates {
                let parts = coordinates.split(separator: ",")
                if parts.count >= 2, let lng = Double(parts[0]), let lat = Double(parts[1]) {
                    longitude = lng
                    latitude = lat
                }
            }
            places.append(
                KMLService.KmlPlace(
                    name: (name?.isEmpty ?? true) ? nil : name,
                    address: (description?.isEmpty ?? true) ? nil : description,
                    latitude: latitude,
                    longitude: longitude
                )
            )
            inPlacemark = false
        default:
            break
        }
        currentText = ""
    }
}
