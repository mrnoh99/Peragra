import type { Place } from "../types";

/**
 * A universal Google Maps link that opens the native app on mobile (when
 * installed) or maps.google.com otherwise. Centers on the geocoded
 * coordinate when we have one, falling back to a text search for
 * "name, address" so it still works for places that never geocoded.
 */
export function googleMapsUrl(place: Place): string {
  const query =
    place.lat !== null && place.lng !== null
      ? `${place.lat},${place.lng}`
      : [place.name, place.address].filter(Boolean).join(", ");
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
}
