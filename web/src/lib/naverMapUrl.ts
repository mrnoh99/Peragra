import type { Place } from "../types";
import { getCurrentLocation } from "./currentLocation";
import { isInKorea } from "./koreaRegion";

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
  const params = new URLSearchParams({
    lat: `${place.lat}`,
    lng: `${place.lng}`,
    name: place.name,
    appname: APP_NAME,
  });
  return `nmap://place?${params.toString()}`;
}

/**
 * A Naver Map directions link visiting several places in order, via its
 * own car-route scheme — like kakaoMapDirectionsUrl, this requires an
 * explicit starting coordinate (no "start from wherever I am" default),
 * so this reads the browser's current position itself and returns null
 * if that's unavailable. Supports a destination plus up to 5 waypoints
 * (v1lat/v1lng/v1name … v5lat/v5lng/v5name); anything past 6 places is
 * dropped, and places outside Korea are dropped rather than failing the
 * whole route.
 */
export async function naverMapDirectionsUrl(places: Place[]): Promise<string | null> {
  const inKorea = places.filter(
    (p): p is Place & { lat: number; lng: number } =>
      p.lat !== null && p.lng !== null && isInKorea(p.lat, p.lng),
  );
  if (inKorea.length === 0) return null;

  const origin = await getCurrentLocation();
  if (!origin) return null;

  const destination = inKorea[inKorea.length - 1];
  const waypoints = inKorea.slice(0, -1).slice(0, 5);

  const params = new URLSearchParams({
    slat: `${origin.lat}`,
    slng: `${origin.lng}`,
    sname: "현재 위치",
    dlat: `${destination.lat}`,
    dlng: `${destination.lng}`,
    dname: destination.name || "목적지",
    appname: APP_NAME,
  });
  waypoints.forEach((waypoint, index) => {
    const n = index + 1;
    params.set(`v${n}lat`, `${waypoint.lat}`);
    params.set(`v${n}lng`, `${waypoint.lng}`);
    params.set(`v${n}name`, waypoint.name || `경유지 ${n}`);
  });
  return `nmap://route/car?${params.toString()}`;
}
