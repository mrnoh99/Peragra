import type { PlaceCategory } from "../types";
import type { NearbyPlaceCandidate } from "./nearbyPlaceCandidate";

// Which OSM tags count as this app's categories — used both to build the
// Overpass query (when a hint narrows the search) and to classify each
// result back (when it doesn't).
const OSM_TAGS_BY_CATEGORY: Record<PlaceCategory, { key: string; values?: string[] }[]> = {
  restaurant: [
    { key: "amenity", values: ["restaurant", "fast_food", "food_court"] },
    { key: "shop", values: ["bakery"] },
  ],
  cafe: [{ key: "amenity", values: ["cafe"] }],
  attraction: [
    { key: "tourism", values: ["attraction", "museum", "gallery", "zoo", "theme_park", "aquarium"] },
    { key: "leisure", values: ["park"] },
    { key: "amenity", values: ["place_of_worship"] },
    // Monuments, memorials, and other historic sites (a war memorial,
    // for instance) — OSM's `historic` key covers these, and neither
    // `tourism` nor any other key above does. Any value under `historic`
    // counts; unlike the other filters, this one isn't narrowed to a
    // specific list, since the tag itself already implies "attraction".
    { key: "historic" },
  ],
  shopping: [{ key: "shop" }],
  hotel: [{ key: "tourism", values: ["hotel", "guest_house", "hostel"] }],
  nightlife: [{ key: "amenity", values: ["bar", "pub", "nightclub", "casino"] }],
  other: [{ key: "amenity" }, { key: "shop" }, { key: "tourism" }, { key: "leisure" }, { key: "historic" }],
};

function categoryForTags(tags: Record<string, string>): PlaceCategory {
  for (const [category, filters] of Object.entries(OSM_TAGS_BY_CATEGORY) as [PlaceCategory, typeof OSM_TAGS_BY_CATEGORY[PlaceCategory]][]) {
    if (category === "other") continue;
    for (const filter of filters) {
      const value = tags[filter.key];
      if (!value) continue;
      if (!filter.values || filter.values.includes(value)) return category;
    }
  }
  return "other";
}

// A photo's GPS fix and a POI's own indexed coordinate rarely land in
// exactly the same spot — more so for something like a monument, where
// the "point" could be set anywhere across its own plaza — so 100m was
// cutting off real, nearby matches. 200m stays tight enough to not pull
// in places from unrelated blocks.
const SEARCH_RADIUS_METERS = 200;

function buildQuery(lat: number, lng: number, categoryHint?: PlaceCategory): string {
  const filters = categoryHint ? OSM_TAGS_BY_CATEGORY[categoryHint] : OSM_TAGS_BY_CATEGORY.other;
  const clauses = filters
    .map(({ key, values }) => {
      const tagMatch = values ? `"${key}"~"^(${values.join("|")})$"` : `"${key}"`;
      return `node(around:${SEARCH_RADIUS_METERS},${lat},${lng})[${tagMatch}]["name"];`;
    })
    .join("\n  ");
  return `[out:json][timeout:10];\n(\n  ${clauses}\n);\nout body 8;`;
}

interface OverpassElement {
  lat: number;
  lon: number;
  tags?: Record<string, string>;
}

interface OverpassResponse {
  elements: OverpassElement[];
}

/**
 * Free (no API key) nearby-place search via OpenStreetMap's public
 * Overpass API — the fallback used when Google Maps isn't configured,
 * matching the iOS app's own free/Apple-first, Google-when-opted-in
 * dispatch pattern (see nearbyPlaces.ts). Overpass has no key or account,
 * but is also a shared public service — this app queries only a small
 * radius node search per lookup (SEARCH_RADIUS_METERS), well within
 * reasonable use.
 */
export async function searchNearbyPlacesOSM(
  lat: number,
  lng: number,
  categoryHint?: PlaceCategory,
): Promise<NearbyPlaceCandidate[]> {
  try {
    const response = await fetch("https://overpass-api.de/api/interpreter", {
      method: "POST",
      headers: { "Content-Type": "text/plain" },
      body: buildQuery(lat, lng, categoryHint),
    });
    if (!response.ok) return [];
    const data = (await response.json()) as OverpassResponse;
    return data.elements
      .filter((el) => el.tags?.name)
      .slice(0, 8)
      .map((el) => {
        const tags = el.tags!;
        const addressParts = [tags["addr:housenumber"], tags["addr:street"], tags["addr:city"]].filter(Boolean);
        return {
          placeId: `osm:${el.lat},${el.lon},${tags.name}`,
          name: tags.name,
          address: addressParts.length > 0 ? addressParts.join(" ") : null,
          phone: tags["contact:phone"] ?? tags.phone ?? null,
          lat: el.lat,
          lng: el.lon,
          category: categoryHint ?? categoryForTags(tags),
        };
      });
  } catch (error) {
    console.warn("OSM nearby places search failed:", error);
    return [];
  }
}
