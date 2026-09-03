import { useMapSettingsStore } from "../store/useMapSettingsStore";
import { geocodeWithGoogle } from "./googleGeocode";

export interface GeocodeResult {
  lat: number;
  lng: number;
  displayName: string;
}

async function geocodeWithNominatim(
  query: string,
): Promise<GeocodeResult | null> {
  const url = new URL("https://nominatim.openstreetmap.org/search");
  url.searchParams.set("q", query);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("limit", "1");

  const response = await fetch(url.toString(), {
    headers: { Accept: "application/json" },
  });
  if (!response.ok) return null;

  const results: Array<{ lat: string; lon: string; display_name: string }> =
    await response.json();
  const first = results[0];
  if (!first) return null;

  return {
    lat: Number.parseFloat(first.lat),
    lng: Number.parseFloat(first.lon),
    displayName: first.display_name,
  };
}

/**
 * Free-text geocoding, turning a place name/address into map coordinates.
 * Uses the Google Geocoding API when the user has opted into Google Maps
 * in Settings with their own API key; otherwise falls back to
 * OpenStreetMap's Nominatim (no API key required — the default).
 */
export async function geocodePlace(
  query: string,
  contextHint?: string,
): Promise<GeocodeResult | null> {
  const trimmed = query.trim();
  if (!trimmed) return null;
  const fullQuery = contextHint ? `${trimmed}, ${contextHint}` : trimmed;

  const { mapProvider, googleMapsApiKey } = useMapSettingsStore.getState();
  if (mapProvider === "google" && googleMapsApiKey) {
    const result = await geocodeWithGoogle(fullQuery, googleMapsApiKey);
    return result ? { ...result, displayName: fullQuery } : null;
  }

  return geocodeWithNominatim(fullQuery);
}
