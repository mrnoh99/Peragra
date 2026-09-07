import { distanceKm } from "./distance";
import { searchNearbyPlacesGoogle } from "./googleNearbyPlaces";
import type { NearbyPlaceCandidate } from "./nearbyPlaceCandidate";
import { searchNearbyPlacesOSM } from "./osmNearbyPlaces";
import { useMapSettingsStore } from "../store/useMapSettingsStore";
import type { PlaceCategory } from "../types";

export type { NearbyPlaceCandidate };

/**
 * Finds real places near a coordinate, for presenting as pickable
 * candidates when a GPS fix (from an on-site photo) is the only
 * information available — letting the person confirm which actual place
 * it was rather than trusting a bare reverse geocode. Uses the free
 * OpenStreetMap/Overpass search by default (no key required); when the
 * user has opted into Google Maps with their own key, uses the Places
 * API (New) instead — matching the iOS app's own Apple/Google dispatch.
 * An optional category hint narrows the search, for when the plain
 * nearby list is too ambiguous to tell which result is right.
 *
 * Always returned nearest-first, regardless of provider — Google's own
 * API already ranks by distance (rankPreference: DISTANCE, see
 * googleNearbyPlaces.ts), but Overpass has no such option (results come
 * back in whatever order the query engine finds them, not by distance),
 * so this sorts every result by its actual distance from the query
 * coordinate itself rather than trusting either provider's ordering.
 *
 * @param accuracy The GPS fix's own reported accuracy (meters), when
 *   known — sizes the search radius (see nearbySearchRadius) instead of
 *   trusting one fixed distance for every situation.
 */
export async function searchNearbyPlaces(
  lat: number,
  lng: number,
  categoryHint?: PlaceCategory,
  accuracy?: number | null,
): Promise<NearbyPlaceCandidate[]> {
  const radius = nearbySearchRadius(categoryHint, accuracy);
  const { mapProvider, googleMapsApiKey } = useMapSettingsStore.getState();
  const results =
    mapProvider === "google" && googleMapsApiKey
      ? await searchNearbyPlacesGoogle(lat, lng, googleMapsApiKey, categoryHint, radius)
      : await searchNearbyPlacesOSM(lat, lng, categoryHint, radius);

  const origin = { lat, lng };
  return [...results].sort((a, b) => distanceKm(origin, a) - distanceKm(origin, b));
}

/**
 * A restaurant/cafe/shop/hotel/nightlife spot is a single building — a
 * tight radius avoids pulling in unrelated places from down the block.
 * An attraction can be spread across its own plaza or park, and so can
 * whatever's behind an unset hint (it might turn out to be an
 * attraction) — a much wider radius is worth the extra, dismissable
 * candidates it can pull in, since too narrow risks missing the real
 * match entirely rather than just showing extras.
 *
 * Sized around the GPS fix's own reported accuracy (plus a fixed buffer
 * for the ordinary case of a POI's indexed coordinate not landing
 * exactly where the fix did), clamped to a floor (accuracy alone, on a
 * great fix, would otherwise search unrealistically tight) and a
 * ceiling (a bad fix shouldn't search a whole neighborhood). No accuracy
 * at all falls back to that category's own ceiling — better to search
 * wide than assume a fix was good when it's genuinely unknown.
 */
function nearbySearchRadius(categoryHint: PlaceCategory | undefined, accuracy: number | null | undefined): number {
  const isPointLike =
    categoryHint === "restaurant" ||
    categoryHint === "cafe" ||
    categoryHint === "shopping" ||
    categoryHint === "hotel" ||
    categoryHint === "nightlife";

  const buffer = isPointLike ? 30 : 100;
  const minimum = isPointLike ? 80 : 150;
  const maximum = isPointLike ? 150 : 500;

  if (!accuracy || accuracy <= 0) return maximum;
  return Math.min(maximum, Math.max(minimum, accuracy + buffer));
}
