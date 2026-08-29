export interface GeocodeResult {
  lat: number;
  lng: number;
  displayName: string;
}

/**
 * Free-text geocoding via OpenStreetMap's Nominatim public API.
 * No API key required; used client-side for turning a place name/address
 * into map coordinates.
 */
export async function geocodePlace(
  query: string,
  contextHint?: string,
): Promise<GeocodeResult | null> {
  const trimmed = query.trim();
  if (!trimmed) return null;

  const fullQuery = contextHint ? `${trimmed}, ${contextHint}` : trimmed;
  const url = new URL("https://nominatim.openstreetmap.org/search");
  url.searchParams.set("q", fullQuery);
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
