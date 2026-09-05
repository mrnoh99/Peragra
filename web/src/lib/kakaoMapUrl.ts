import type { Place } from "../types";

/**
 * Kakao Map's own public "share a route" link — no API key needed, unlike
 * Kakao Navi's own app-launch scheme. Opens the native app on mobile (when
 * installed) or map.kakao.com otherwise; from inside the app, "길찾기" hands
 * off to Kakao Navi. Unlike googleMapsUrl's name/address text search, this
 * format takes a real numeric coordinate, so it's only available once this
 * app's own geocoding has actually located the place.
 */
export function kakaoMapUrl(place: Place): string | null {
  if (place.lat === null || place.lng === null || !place.name) return null;
  const name = encodeURIComponent(place.name);
  return `https://map.kakao.com/link/to/${name},${place.lat},${place.lng}`;
}
