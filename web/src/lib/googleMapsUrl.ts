import type { Place } from "../types";

/**
 * A search/route query for one place. Prefers "name, address" — but only
 * when this app's own geocoding actually resolved that address
 * ("located"); for anything else (no address, or a "failed"/"estimated"
 * pin that never located cleanly on our own map) the address text has
 * already proven unreliable, so it's dropped in favor of qualifying the
 * name with the trip's destination city instead. Confirmed by a real
 * "can't find a way to the specified destination" failure on a place
 * whose pin didn't show on our map either.
 *
 * When the name itself can't be trusted as search text — the "Unknown"
 * placeholder left by an on-site capture with no legible signage, or
 * truly empty — a text search has nothing real to match and Google Maps
 * reports "no results" even though this app already has a real
 * coordinate for the place. There, the query is the coordinate itself
 * ("lat,lng", which Google's search API accepts directly) so the pin
 * still resolves, at the cost of a coordinate label instead of a name.
 */
function placeQuery(place: Place, tripDestination?: string): string {
  const trimmedName = place.name.trim();
  const hasUsableName = trimmedName !== "" && trimmedName !== "Unknown";

  if (
    !hasUsableName &&
    place.lat != null &&
    place.lng != null &&
    (place.geocodeStatus === "located" || place.geocodeStatus === "estimated")
  ) {
    return `${place.lat},${place.lng}`;
  }

  if (place.geocodeStatus === "located" && place.address) {
    return [place.name, place.address].join(", ");
  }
  return [place.name, tripDestination].filter(Boolean).join(", ");
}

/**
 * A universal Google Maps link that opens the native app on mobile (when
 * installed) or maps.google.com otherwise. Always searches by "name,
 * address" rather than the geocoded lat/lng, so the map shows a readable
 * label instead of raw coordinates.
 */
export function googleMapsUrl(place: Place, tripDestination?: string): string {
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(placeQuery(place, tripDestination))}`;
}
