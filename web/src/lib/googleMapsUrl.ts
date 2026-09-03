import type { Place } from "../types";

function placeQuery(place: Place): string {
  return [place.name, place.address].filter(Boolean).join(", ");
}

/**
 * A universal Google Maps link that opens the native app on mobile (when
 * installed) or maps.google.com otherwise. Always searches by "name,
 * address" rather than the geocoded lat/lng, so the map shows a readable
 * label instead of raw coordinates.
 */
export function googleMapsUrl(place: Place): string {
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(placeQuery(place))}`;
}

/**
 * A Google Maps directions link visiting several places in order — the
 * last one as the destination, everything before it as waypoints. Origin
 * is left unset so Google Maps starts from wherever the user currently is.
 */
export function googleMapsDirectionsUrl(places: Place[]): string {
  const queries = places.map(placeQuery).filter((q) => q.length > 0);
  if (queries.length === 0) return "https://www.google.com/maps";

  const destination = queries[queries.length - 1];
  const waypoints = queries.slice(0, -1);
  const params = new URLSearchParams({ api: "1", destination });
  if (waypoints.length > 0) {
    params.set("waypoints", waypoints.join("|"));
  }
  return `https://www.google.com/maps/dir/?${params.toString()}`;
}
