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
 */
function placeQuery(place: Place, tripDestination?: string): string {
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
