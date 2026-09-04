import { PLACE_CATEGORIES, type Place } from "../types";

/**
 * KML export — the closest thing to a "send this list to Google Maps"
 * feature that's actually possible: Google has no public API for a
 * user's personal Saved-places lists (no way to check whether a "Peragra"
 * list already exists there, or create/add to one), but Google My Maps
 * (mymaps.google.com) can import a KML file as a new named map. So
 * "syncing with Google Maps" here means: generate a KML file titled
 * "Peragra - <trip>" for the user to import into My Maps (once, naming
 * that map "Peragra" themselves).
 *
 * Places are grouped into one <Folder> per category — My Maps shows each
 * KML Folder as its own named, separately-colored layer, so a category
 * ("Restaurant", "Cafe", ...) survives the import instead of every pin
 * landing in one undifferentiated pile. Notes travel in the placemark
 * description, same as before.
 */

function escapeXml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function placemarkXml(p: Place): string {
  const description = [p.address, p.notes].filter((s) => s.trim()).join(" — ");
  return [
    "      <Placemark>",
    `        <name>${escapeXml(p.name)}</name>`,
    description ? `        <description>${escapeXml(description)}</description>` : null,
    // KML coordinate order is longitude,latitude[,altitude] — the
    // reverse of how this app (and most UIs) writes lat/lng.
    `        <Point><coordinates>${p.lng},${p.lat},0</coordinates></Point>`,
    "      </Placemark>",
  ]
    .filter((line) => line !== null)
    .join("\n");
}

export function generateKML(title: string, places: Place[]): string {
  const located = places.filter((p) => p.lat !== null && p.lng !== null);

  const byCategory = new Map<string, Place[]>();
  for (const p of located) {
    const list = byCategory.get(p.category) ?? [];
    list.push(p);
    byCategory.set(p.category, list);
  }

  const folders = PLACE_CATEGORIES.filter((c) => byCategory.has(c.value))
    .map((c) => {
      const placemarks = byCategory
        .get(c.value)!
        .map((p) => placemarkXml(p))
        .join("\n");
      return `    <Folder>\n      <name>${escapeXml(c.label)}</name>\n${placemarks}\n    </Folder>`;
    })
    .join("\n");

  return `<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>${escapeXml(title)}</name>
${folders}
  </Document>
</kml>
`;
}
