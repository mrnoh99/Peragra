import { loadGoogleMapsScript } from "./googleMapsLoader";

/**
 * Free-text geocoding via the Google Maps JavaScript API's Geocoder class,
 * for people who've opted into Google Maps in Settings with their own API
 * key. Only called from geocode.ts's dispatcher when that opt-in is active.
 *
 * Deliberately NOT a fetch() to Google's REST Geocoding endpoint
 * (maps.googleapis.com/maps/api/geocode/json) — that endpoint sends no
 * CORS headers and Google documents it as server-side only, so a direct
 * browser request to it is blocked outright (the fetch throws, not just
 * returns an empty result). Loading the JS SDK (already needed for the
 * map itself) and using its Geocoder class is the browser-side-supported
 * way to do this.
 */
export async function geocodeWithGoogle(
  query: string,
  apiKey: string,
): Promise<{ lat: number; lng: number } | null> {
  await loadGoogleMapsScript(apiKey);
  if (!window.google) return null;

  const geocoder = new window.google.maps.Geocoder();
  try {
    // The Geocoder's promise rejects for any non-OK status, including
    // ZERO_RESULTS — which isn't really a failure, just "nothing found" —
    // so that's folded into the same null return as an empty result list.
    const response = await geocoder.geocode({ address: query });
    const location = response.results[0]?.geometry.location;
    if (!location) return null;
    return { lat: location.lat(), lng: location.lng() };
  } catch (error) {
    // Surfaced to the console rather than the UI (the caller just treats
    // this as "couldn't locate") — but genuinely useful when debugging
    // why geocoding fails, e.g. REQUEST_DENIED means the Geocoding API
    // isn't enabled for this key/project (a separate toggle in Google
    // Cloud Console from the Maps JavaScript API the map itself uses).
    console.warn("Google geocoding failed:", error);
    return null;
  }
}
