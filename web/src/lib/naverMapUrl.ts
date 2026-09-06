import type { Place } from "../types";
import { isInKorea } from "./koreaRegion";
import { buildCustomSchemeQuery } from "./customSchemeUrl";

// A required identifier for the calling app/site, not a registered API key.
const APP_NAME = "com.peragra.web";

/**
 * Naver Map's own app URL scheme. Unlike Kakao Map's public web link,
 * there's no documented universal/web fallback for this one: nmap:// only
 * opens something when the Naver Map app is installed. Launch it via
 * openCustomSchemeUrl (customSchemeUrl.ts) rather than linking to it
 * directly — see that file for why.
 */
export function naverMapUrl(place: Place): string | null {
  if (place.lat === null || place.lng === null || !place.name) return null;
  if (!isInKorea(place.lat, place.lng)) return null;
  const query = buildCustomSchemeQuery({
    lat: `${place.lat}`,
    lng: `${place.lng}`,
    name: place.name,
    appname: APP_NAME,
  });
  return `nmap://place?${query}`;
}
