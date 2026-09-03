import type { Place } from "../types";

/**
 * A universal Google Maps link that opens the native app on mobile (when
 * installed) or maps.google.com otherwise. Always searches by "name,
 * address" rather than the geocoded lat/lng, so the map shows a readable
 * label instead of raw coordinates.
 */
export function googleMapsUrl(place: Place): string {
  const query = [place.name, place.address].filter(Boolean).join(", ");
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
}
