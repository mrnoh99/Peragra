import Foundation

/// KML export — the closest thing to a "send this list to Google Maps"
/// feature that's actually possible: Google has no public API for a
/// user's personal Saved-places lists (no way to check whether a "Peragra"
/// list already exists there, or create/add to one), but Google My Maps
/// (mymaps.google.com) can import a KML file as a new named map. So
/// "syncing with Google Maps" here means: generate a KML file titled
/// "Peragra - <trip>" for the user to import into My Maps (once, naming
/// that map "Peragra" themselves).
///
/// Places are grouped into one <Folder> per category — My Maps shows each
/// KML Folder as its own named, separately-colored layer, so a category
/// ("Restaurant", "Cafe", ...) survives the import instead of every pin
/// landing in one undifferentiated pile. Notes travel in the placemark
/// description, same as before.
/// Mirrors web/src/lib/kml.ts.
enum KMLService {
    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // Built from joined arrays rather than Swift multi-line string
    // literals — a multi-line literal requires every line (interpolated
    // ones included) to be indented at least as much as the closing
    // `"""`, which broke here once when nested inside the `.compactMap`
    // closure below caused a real "Insufficient indentation" compile
    // error; arrays of lines joined by "\n" don't have that failure mode.
    private static func placemarkXML(_ place: Place) -> String {
        let descriptionParts = [place.address, place.notes].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let description = descriptionParts.joined(separator: " — ")
        // KML coordinate order is longitude,latitude[,altitude] — the
        // reverse of how this app (and most UIs) writes lat/lng.
        let lines: [String?] = [
            "      <Placemark>",
            "        <name>\(escapeXML(place.name))</name>",
            description.isEmpty ? nil : "        <description>\(escapeXML(description))</description>",
            "        <Point><coordinates>\(place.longitude ?? 0),\(place.latitude ?? 0),0</coordinates></Point>",
            "      </Placemark>",
        ]
        return lines.compactMap { $0 }.joined(separator: "\n")
    }

    static func generateKML(title: String, places: [Place]) -> String {
        let located = places.filter { $0.latitude != nil && $0.longitude != nil }

        let folders = PlaceCategory.allCases
            .compactMap { category -> String? in
                let categoryPlaces = located.filter { $0.category == category }
                guard !categoryPlaces.isEmpty else { return nil }
                let placemarks = categoryPlaces.map(placemarkXML).joined(separator: "\n")
                return [
                    "    <Folder>",
                    "      <name>\(escapeXML(category.label))</name>",
                    placemarks,
                    "    </Folder>",
                ].joined(separator: "\n")
            }
            .joined(separator: "\n")

        let lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<kml xmlns=\"http://www.opengis.net/kml/2.2\">",
            "  <Document>",
            "    <name>\(escapeXML(title))</name>",
            folders,
            "  </Document>",
            "</kml>",
            "",
        ]
        return lines.joined(separator: "\n")
    }
}
