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
 */
export async function searchNearbyPlaces(
  lat: number,
  lng: number,
  categoryHint?: PlaceCategory,
): Promise<NearbyPlaceCandidate[]> {
  const { mapProvider, googleMapsApiKey } = useMapSettingsStore.getState();
  if (mapProvider === "google" && googleMapsApiKey) {
    return searchNearbyPlacesGoogle(lat, lng, googleMapsApiKey, categoryHint);
  }
  return searchNearbyPlacesOSM(lat, lng, categoryHint);
}
