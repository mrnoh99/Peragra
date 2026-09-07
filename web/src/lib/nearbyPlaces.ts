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
 */
export async function searchNearbyPlaces(
  lat: number,
  lng: number,
  categoryHint?: PlaceCategory,
): Promise<NearbyPlaceCandidate[]> {
  const { mapProvider, googleMapsApiKey } = useMapSettingsStore.getState();
  const results =
    mapProvider === "google" && googleMapsApiKey
      ? await searchNearbyPlacesGoogle(lat, lng, googleMapsApiKey, categoryHint)
      : await searchNearbyPlacesOSM(lat, lng, categoryHint);

  const origin = { lat, lng };
  return [...results].sort((a, b) => distanceKm(origin, a) - distanceKm(origin, b));
}
