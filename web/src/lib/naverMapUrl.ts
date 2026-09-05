import type { Place } from "../types";
import { isInKorea } from "./koreaRegion";

// A required identifier for the calling app/site, not a registered API key.
const APP_NAME = "com.peragra.web";

/**
 * Naver Map's own app URL scheme. Unlike Kakao Map's public web link,
 * there's no documented universal/web fallback for this one: nmap://
 * only opens something when the Naver Map app is installed, and silently
 * does nothing otherwise.
 */
export function naverMapUrl(place: Place): string | null {
  if (place.lat === null || place.lng === null || !place.name) return null;
  if (!isInKorea(place.lat, place.lng)) return null;
  const params = new URLSearchParams({
    lat: `${place.lat}`,
    lng: `${place.lng}`,
    name: place.name,
    appname: APP_NAME,
  });
  return `nmap://place?${params.toString()}`;
}
