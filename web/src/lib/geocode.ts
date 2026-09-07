import { useMapSettingsStore, type MapProvider } from "../store/useMapSettingsStore";
import { mentionsNonKoreanCountry, normalizeTrailingCountryName } from "./countryNames";
import { geocodeWithGoogle, reverseGeocodeWithGoogle } from "./googleGeocode";
import { geocodeWithNaver, reverseGeocodeWithNaver } from "./naverGeocode";
import { isInKorea } from "./koreaRegion";
import { pickMapProvider } from "./mapProviderPolicy";

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
 *
 * The query's trailing country name is normalized to English first (see
 * normalizeTrailingCountryName) — a Korean-language source address often
 * has just the country name translated (e.g. "..., 이탈리아" for an
 * otherwise Italian address), and that one mixed-script token is enough
 * to make Nominatim in particular fail to resolve an address it would
 * otherwise handle fine.
 *
 * `providerOverride`, when given, is used in place of the globally
 * configured provider — set by geocodePlaceByAddressOrName when this
 * board has a non-Korean place and Naver (which has no useful data
 * outside Korea at all) is the global setting.
 */
export async function geocodePlace(
  query: string,
  contextHint?: string,
  providerOverride?: MapProvider,
): Promise<GeocodeResult | null> {
  const trimmed = normalizeTrailingCountryName(query.trim());
  if (!trimmed) return null;
  const fullQuery = contextHint ? `${trimmed}, ${contextHint}` : trimmed;

  const { mapProvider, googleMapsApiKey, naverClientId } = useMapSettingsStore.getState();
  const effectiveProvider = providerOverride ?? mapProvider;
  if (effectiveProvider === "google" && googleMapsApiKey) {
    const result = await geocodeWithGoogle(fullQuery, googleMapsApiKey);
    return result ? { ...result, displayName: fullQuery } : null;
  }
  if (effectiveProvider === "naver" && naverClientId) {
    return geocodeWithNaver(fullQuery, naverClientId);
  }

  return geocodeWithNominatim(fullQuery);
}

/**
 * Tries geocoding a place's own address text first (when it has one),
 * then falls back to geocoding by its name alone. An address-focused
 * geocoder (Nominatim, or Google's Geocoding API — a different, stricter
 * product than Google Maps' own consumer search) is much better at
 * matching a well-known landmark by its *name* than at parsing a vague,
 * informal, or incomplete address string — e.g. a private island's
 * garden with no real street address of its own, which the interactive
 * Google Maps app still finds by name even though the Geocoding API
 * rejects its address text outright.
 */
export async function geocodePlaceByAddressOrName(
  place: { name: string; address: string },
  contextHint?: string,
  // The board's other places (this one need not be included) — checked
  // alongside this place's own name/address for a non-Korean signal, so
  // one confirmed non-Korean place is enough to switch the whole board
  // off Naver, not just places that happen to name a country themselves.
  siblingPlaces: Array<{ lat: number | null; lng: number | null; name: string; address: string }> = [],
): Promise<GeocodeResult | null> {
  const address = place.address.trim();
  const name = place.name.trim();

  const { mapProvider, googleMapsApiKey } = useMapSettingsStore.getState();
  const providerOverride = pickMapProvider(mapProvider, googleMapsApiKey, [
    { lat: null, lng: null, name, address },
    ...siblingPlaces,
  ]);

  return geocodeSingleProvider(providerOverride, { name, address }, contextHint, siblingPlaces);
}

export interface ProviderResult {
  provider: MapProvider;
  result: GeocodeResult;
}

/**
 * Same address-then-name lookup as geocodePlaceByAddressOrName, but
 * tried against every provider with usable credentials — the free
 * Nominatim provider (always), Google (once the person has entered
 * their own API key), and Naver (once they've entered a Client ID) —
 * instead of only the one currently selected in Settings. For "retry"
 * to let a person choose when providers disagree, rather than trusting
 * whichever one happens to be configured: a short/obscure name can get
 * a confident but wrong match from one geocoder while another gets it
 * right (a real case: Naver placed one restaurant nowhere near Korea
 * while Google found it exactly). Each provider's own plausibility
 * check (see isPlausible) still applies to its own result.
 */
export async function geocodeAllProviders(
  place: { name: string; address: string },
  contextHint?: string,
  siblingPlaces: Array<{ lat: number | null; lng: number | null; name: string; address: string }> = [],
): Promise<ProviderResult[]> {
  const { googleMapsApiKey, naverClientId } = useMapSettingsStore.getState();
  const providers: MapProvider[] = ["free"];
  if (googleMapsApiKey) providers.push("google");
  if (naverClientId) providers.push("naver");

  const results: ProviderResult[] = [];
  for (const provider of providers) {
    const result = await geocodeSingleProvider(provider, place, contextHint, siblingPlaces);
    if (result) results.push({ provider, result });
  }
  return results;
}

async function geocodeSingleProvider(
  provider: MapProvider,
  place: { name: string; address: string },
  contextHint: string | undefined,
  siblingPlaces: Array<{ lat: number | null; lng: number | null; name: string; address: string }>,
): Promise<GeocodeResult | null> {
  const address = place.address.trim();
  const name = place.name.trim();

  if (address) {
    const result = await geocodePlace(address, contextHint, provider);
    if (result && isPlausible(result, { name, address }, siblingPlaces)) return result;
  }
  if (name) {
    const result = await geocodePlace(name, contextHint, provider);
    if (result && isPlausible(result, { name, address }, siblingPlaces)) return result;
  }
  return null;
}

/**
 * A geocoder can confidently return a real coordinate for an obscure/
 * short name that just happens to phonetically or partially match
 * something completely unrelated on another continent — one place ended
 * up plotted in the Gulf of Guinea for exactly this reason. Rejects a
 * result that lands outside Korea when nothing suggests it should: this
 * place's own name/address doesn't mention a non-Korean country, AND
 * this board already has another place confirmed inside Korea (so this
 * isn't just a legitimately international board/trip, where an
 * out-of-Korea result is expected and fine). A rejected result falls
 * back to the next query (name after address, or "couldn't locate")
 * rather than silently showing a wrong location.
 */
function isPlausible(
  result: GeocodeResult,
  place: { name: string; address: string },
  siblingPlaces: Array<{ lat: number | null; lng: number | null; name: string; address: string }>,
): boolean {
  if (isInKorea(result.lat, result.lng)) return true;
  if (mentionsNonKoreanCountry(place.address) || mentionsNonKoreanCountry(place.name)) return true;
  const siblingConfirmedInKorea = siblingPlaces.some(
    (sibling) => sibling.lat !== null && sibling.lng !== null && isInKorea(sibling.lat, sibling.lng),
  );
  return !siblingConfirmedInKorea;
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
 *
 * For a Korean coordinate, this always tries Naver for the *name* as a
 * final step when the primary provider didn't find one — even if Naver
 * isn't the person's chosen map provider — since Naver's own address
 * database is the most reliable at resolving "what business is actually
 * at this exact address" in Korea (a storefront photo with no legible
 * signage otherwise has no way to name itself). Only needs a Client ID
 * to have been entered in Settings, not selected as the active provider.
 */
export async function reverseGeocode(lat: number, lng: number): Promise<ReverseGeocodeResult | null> {
  const { mapProvider, googleMapsApiKey, naverClientId } = useMapSettingsStore.getState();
  let result: ReverseGeocodeResult | null;
  if (mapProvider === "google" && googleMapsApiKey) {
    result = await reverseGeocodeWithGoogle(lat, lng, googleMapsApiKey);
  } else if (mapProvider === "naver" && naverClientId) {
    result = await reverseGeocodeWithNaver(lat, lng, naverClientId);
  } else {
    result = await reverseGeocodeWithNominatim(lat, lng);
  }

  if (!result?.name && mapProvider !== "naver" && naverClientId && isInKorea(lat, lng)) {
    const naverResult = await reverseGeocodeWithNaver(lat, lng, naverClientId);
    if (naverResult?.name) {
      result = result ? { ...result, name: naverResult.name } : naverResult;
    }
  }

  return result;
}
