import { detectCountryFromText } from "./countryNames";
import { isInKorea } from "./koreaRegion";

interface PlaceLike {
  name: string;
  address: string;
  lat: number | null;
  lng: number | null;
}

/**
 * Determines which country a place belongs to, for the auto-created
 * "country" lists (see useStore's syncPlaceCountry): first from its own
 * address/name text mentioning a known country (works even before the
 * place has been geocoded), otherwise from its geocoded coordinate falling
 * inside Korea's bounding box — there's no polygon data for every other
 * country, so a place with neither signal is left unclassified rather than
 * guessed at.
 */
export function detectCountry(place: PlaceLike): string | null {
  const fromText = detectCountryFromText(place.address) || detectCountryFromText(place.name);
  if (fromText) return fromText;
  if (place.lat !== null && place.lng !== null && isInKorea(place.lat, place.lng)) {
    return "South Korea";
  }
  return null;
}
