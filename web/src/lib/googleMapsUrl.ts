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

/**
 * A Google Maps directions link visiting several places in order — the
 * last one as the destination, everything before it as waypoints. Origin
 * is left unset so Google Maps starts from wherever the user currently is.
 */
export function googleMapsDirectionsUrl(places: Place[], tripDestination?: string): string {
  const queries = places.map((p) => placeQuery(p, tripDestination)).filter((q) => q.length > 0);
  if (queries.length === 0) return "https://www.google.com/maps";

  const destination = queries[queries.length - 1];
  const waypoints = queries.slice(0, -1);
  const params = new URLSearchParams({ api: "1", destination });
  if (waypoints.length > 0) {
    params.set("waypoints", waypoints.join("|"));
  }
  return `https://www.google.com/maps/dir/?${params.toString()}`;
}
