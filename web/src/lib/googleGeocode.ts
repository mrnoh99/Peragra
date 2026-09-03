interface GoogleGeocodeResponse {
  results: { geometry: { location: { lat: number; lng: number } } }[];
  status: string;
}

/**
 * Free-text geocoding via the Google Geocoding API, for people who've
 * opted into Google Maps in Settings with their own API key. Only called
 * from geocode.ts's dispatcher when that opt-in is active.
 */
export async function geocodeWithGoogle(
  query: string,
  apiKey: string,
): Promise<{ lat: number; lng: number } | null> {
  const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
  url.searchParams.set("address", query);
  url.searchParams.set("key", apiKey);

  const response = await fetch(url.toString());
  if (!response.ok) return null;

  const data: GoogleGeocodeResponse = await response.json();
  const location = data.results[0]?.geometry.location;
  if (!location) return null;

  return { lat: location.lat, lng: location.lng };
}
