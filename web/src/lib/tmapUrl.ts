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

/**
 * A Tmap directions link visiting several places in order — the last one
 * as the destination, up to 2 more before it as waypoints (rV1.../rV2...,
 * the scheme's own cap; anything past 2 is dropped). No explicit starting
 * coordinate needed (see tmapUrl above), so unlike
 * kakaoMapDirectionsUrl/naverMapDirectionsUrl this isn't async and never
 * needs the browser's location. Places outside Korea are dropped rather
 * than failing the whole route.
 */
export function tmapDirectionsUrl(places: Place[]): string | null {
  const inKorea = places.filter(
    (p): p is Place & { lat: number; lng: number } =>
      p.lat !== null && p.lng !== null && isInKorea(p.lat, p.lng),
  );
  if (inKorea.length === 0) return null;

  const destination = inKorea[inKorea.length - 1];
  const waypoints = inKorea.slice(0, -1).slice(0, 2);

  const query: Record<string, string> = {
    rGoName: destination.name || "목적지",
    rGoX: `${destination.lng}`,
    rGoY: `${destination.lat}`,
  };
  waypoints.forEach((waypoint, index) => {
    const n = index + 1;
    query[`rV${n}Name`] = waypoint.name || `경유지 ${n}`;
    query[`rV${n}X`] = `${waypoint.lng}`;
    query[`rV${n}Y`] = `${waypoint.lat}`;
  });
  return `tmap://route?${buildCustomSchemeQuery(query)}`;
}
