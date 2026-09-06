import type { Place } from "../types";
import { isInKorea } from "./koreaRegion";
import { buildCustomSchemeQuery } from "./customSchemeUrl";

/**
 * Tmap's own app URL scheme. Like Naver Map's nmap://, there's no
 * documented web fallback — launch via openCustomSchemeUrl
 * (customSchemeUrl.ts) rather than linking to it directly. Unlike Kakao
 * and Naver's route schemes, a starting point is optional here: Tmap
 * defaults to the device's own current location when rStX/rStY/rStName
 * are omitted, so no location permission dance is needed just to send a
 * route.
 */
export function tmapUrl(place: Place): string | null {
  if (place.lat === null || place.lng === null || !place.name) return null;
  if (!isInKorea(place.lat, place.lng)) return null;
  const query = buildCustomSchemeQuery({
    rGoName: place.name,
    rGoX: `${place.lng}`,
    rGoY: `${place.lat}`,
  });
  return `tmap://route?${query}`;
}
