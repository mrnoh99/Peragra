import { useMapSettingsStore } from "../store/useMapSettingsStore";
import { geocodeWithGoogle, reverseGeocodeWithGoogle } from "./googleGeocode";
import { geocodeWithNaver, reverseGeocodeWithNaver } from "./naverGeocode";

export interface GeocodeResult {
  lat: number;
  lng: number;
  displayName: string;
}

// Nominatim's usage policy caps unauthenticated use at roughly one request
// per second — saving several places at once (each geocoded in its own
// sequential await) can otherwise fire requests closer together than
// that, and every request past the cap comes back blocked. Tracked at
// module scope so it throttles across every Nominatim call (forward and
// reverse alike), not per call.
let lastNominatimRequestAt = 0;
const NOMINATIM_MIN_INTERVAL_MS = 1100;

async function waitForNominatimSlot(): Promise<void> {
  const waitFor = lastNominatimRequestAt + NOMINATIM_MIN_INTERVAL_MS - Date.now();
  if (waitFor > 0) {
    await new Promise((resolve) => setTimeout(resolve, waitFor));
  }
  lastNominatimRequestAt = Date.now();
}

async function geocodeWithNominatim(
  query: string,
): Promise<GeocodeResult | null> {
  await waitForNominatimSlot();

  const url = new URL("https://nominatim.openstreetmap.org/search");
  url.searchParams.set("q", query);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("limit", "1");

  try {
    const response = await fetch(url.toString(), {
      headers: { Accept: "application/json" },
    });
    if (!response.ok) {
      // Logged rather than surfaced in the UI (the caller just treats
      // this as "couldn't locate") — but genuinely useful for spotting a
      // rate limit (429) or block versus a real "no such place".
      console.warn(`Nominatim geocoding failed: HTTP ${response.status}`);
      return null;
    }

    const results: Array<{ lat: string; lon: string; display_name: string }> =
      await response.json();
    const first = results[0];
    if (!first) return null;

    return {
      lat: Number.parseFloat(first.lat),
      lng: Number.parseFloat(first.lon),
      displayName: first.display_name,
    };
  } catch (error) {
    console.warn("Nominatim geocoding request failed:", error);
    return null;
  }
}

/**
 * Free-text geocoding, turning a place name/address into map coordinates.
 * Uses the Google Geocoding API when the user has opted into Google Maps
 * in Settings with their own API key, or Naver's when opted into Naver
 * Maps with their own Client ID (the most accurate for Korean addresses);
 * otherwise falls back to OpenStreetMap's Nominatim (no API key required
 * — the default).
 */
export async function geocodePlace(
  query: string,
  contextHint?: string,
): Promise<GeocodeResult | null> {
  const trimmed = query.trim();
  if (!trimmed) return null;
  const fullQuery = contextHint ? `${trimmed}, ${contextHint}` : trimmed;

  const { mapProvider, googleMapsApiKey, naverClientId } = useMapSettingsStore.getState();
  if (mapProvider === "google" && googleMapsApiKey) {
    const result = await geocodeWithGoogle(fullQuery, googleMapsApiKey);
    return result ? { ...result, displayName: fullQuery } : null;
  }
  if (mapProvider === "naver" && naverClientId) {
    return geocodeWithNaver(fullQuery, naverClientId);
  }

  return geocodeWithNominatim(fullQuery);
}

export interface ReverseGeocodeResult {
  address: string;
  // Best-effort — only set when the coordinate resolved to an actual
  // named place (a POI/establishment) rather than just a street address.
  name: string | null;
}

async function reverseGeocodeWithNominatim(lat: number, lng: number): Promise<ReverseGeocodeResult | null> {
  await waitForNominatimSlot();

  const url = new URL("https://nominatim.openstreetmap.org/reverse");
  url.searchParams.set("lat", String(lat));
  url.searchParams.set("lon", String(lng));
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("namedetails", "1");

  try {
    const response = await fetch(url.toString(), {
      headers: { Accept: "application/json" },
    });
    if (!response.ok) {
      console.warn(`Nominatim reverse geocoding failed: HTTP ${response.status}`);
      return null;
    }

    const result: {
      display_name?: string;
      namedetails?: { name?: string };
      address?: { amenity?: string; shop?: string; tourism?: string; leisure?: string };
    } = await response.json();
    if (!result.display_name) return null;

    const name =
      result.namedetails?.name ??
      result.address?.amenity ??
      result.address?.shop ??
      result.address?.tourism ??
      result.address?.leisure ??
      null;
    return { address: result.display_name, name };
  } catch (error) {
    console.warn("Nominatim reverse geocoding request failed:", error);
    return null;
  }
}

/**
 * Reverse geocoding (coordinate -> address/name), for turning a GPS fix
 * read off an on-site photo into something readable to fill in a place's
 * address (and, best-effort, its name) automatically.
 */
export async function reverseGeocode(lat: number, lng: number): Promise<ReverseGeocodeResult | null> {
  const { mapProvider, googleMapsApiKey, naverClientId } = useMapSettingsStore.getState();
  if (mapProvider === "google" && googleMapsApiKey) {
    return reverseGeocodeWithGoogle(lat, lng, googleMapsApiKey);
  }
  if (mapProvider === "naver" && naverClientId) {
    return reverseGeocodeWithNaver(lat, lng, naverClientId);
  }

  return reverseGeocodeWithNominatim(lat, lng);
}
