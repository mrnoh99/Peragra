import { mentionsNonKoreanCountry } from "./countryNames";
import { isInKorea } from "./koreaRegion";
import { type MapProvider } from "../store/useMapSettingsStore";

interface PlaceLike {
  lat: number | null;
  lng: number | null;
  name: string;
  address: string;
}

/**
 * Whether this place is (or almost certainly is) outside Korea — from its
 * own geocoded coordinate when it has one, otherwise from its name/address
 * text mentioning a known non-Korean country (see countryNames.ts). A
 * place with neither signal returns false — "not confirmed non-Korea",
 * not "confirmed Korea".
 */
export function isPlaceOutsideKorea(place: PlaceLike): boolean {
  if (place.lat !== null && place.lng !== null) {
    return !isInKorea(place.lat, place.lng);
  }
  return mentionsNonKoreanCountry(place.address) || mentionsNonKoreanCountry(place.name);
}

/**
 * Naver Map has essentially no useful data outside Korea — its map tiles
 * are blank there and its geocoder simply can't resolve a non-Korean
 * address at all. If Naver is the globally selected provider but this
 * board's own places include one outside Korea (checked across every
 * place passed in — a brand new place being added counts too, via its
 * own address/name text, not just already-geocoded siblings), fall back
 * to Google for this board specifically — or, with no Google key
 * available, to the free provider — rather than silently failing.
 * Google and the free provider are left as-is either way, since both
 * already work fine worldwide.
 */
export function pickMapProvider(
  mapProvider: MapProvider,
  googleMapsApiKey: string | null,
  places: PlaceLike[],
): MapProvider {
  if (mapProvider !== "naver") return mapProvider;
  if (!places.some(isPlaceOutsideKorea)) return "naver";
  return googleMapsApiKey ? "google" : "free";
}
