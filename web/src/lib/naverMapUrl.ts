import type { Place } from "../types";
import { getCurrentLocation } from "./currentLocation";
import { isInKorea } from "./koreaRegion";

// A required identifier for the calling app/site, not a registered API key.
const APP_NAME = "com.peragra.web";

/**
 * Naver Map's own app URL scheme. Unlike Kakao Map's public web link,
 * there's no documented universal/web fallback for this one: nmap:// only
 * opens something when the Naver Map app is installed — confirmed on a
 * real iPhone that navigating an `<a href>` straight to it otherwise pops
 * Safari's own "Safari cannot open the page because the address is
 * invalid" alert, not a silent no-op as originally assumed. Use
 * openNaverMap below to launch it instead of linking to this directly.
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
 * Launches a nmap:// URL through a hidden iframe rather than a direct
 * top-level navigation (`<a href>` or `location.href =`) — the standard
 * workaround Korean sites use for this exact problem, since a failed
 * iframe navigation to an unhandled custom scheme doesn't trigger
 * Safari's "address is invalid" alert the way a direct link tap does.
 * Not guaranteed on every iOS/Safari version (Apple has tightened custom
 * scheme handling over time) — if the app is installed this still opens
 * it normally, but if the alert still appears on some devices, this is
 * the ceiling of what's fixable purely from the web side; nmap:// itself
 * has no documented web fallback.
 */
export function openNaverMap(url: string): void {
  const iframe = document.createElement("iframe");
  iframe.style.display = "none";
  document.body.appendChild(iframe);
  iframe.src = url;
  window.setTimeout(() => {
    iframe.remove();
  }, 2000);
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
