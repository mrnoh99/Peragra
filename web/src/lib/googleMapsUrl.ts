import type { Place } from "../types";

/**
 * A search/route query for one place. Prefers "name, address"; when a
 * place has no address on file, a bare name is often too ambiguous for
 * Google Maps to resolve into an actual routable point (confirmed by a
 * real "can't find a way to the specified destination" failure on a
 * name-only waypoint) — qualifying it with the trip's destination city
 * gives Maps something to disambiguate against.
 */
function placeQuery(place: Place, tripDestination?: string): string {
  if (place.address) {
    return [place.name, place.address].filter(Boolean).join(", ");
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
