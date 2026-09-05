import type { Place } from "../types";
import { getCurrentLocation } from "./currentLocation";
import { isInKorea } from "./koreaRegion";

/**
 * Kakao Map's own public "share a route" link — no API key needed, unlike
 * Kakao Navi's own app-launch scheme. Opens the native app on mobile (when
 * installed) or map.kakao.com otherwise; from inside the app, "길찾기" hands
 * off to Kakao Navi. Unlike googleMapsUrl's name/address text search, this
 * format takes a real numeric coordinate, so it's only available once this
 * app's own geocoding has actually located the place — and, since Kakao
 * Map has essentially no useful data outside Korea, only once that
 * coordinate is actually there.
 */
export function kakaoMapUrl(place: Place): string | null {
  if (place.lat === null || place.lng === null || !place.name) return null;
  if (!isInKorea(place.lat, place.lng)) return null;
  const name = encodeURIComponent(place.name);
  return `https://map.kakao.com/link/to/${name},${place.lat},${place.lng}`;
}

/**
 * A Kakao Map directions link visiting several places in order — the last
 * one as the destination, up to 5 more before it as waypoints (the scheme's
 * own cap; anything past 5 is dropped). Unlike kakaoMapUrl and
 * googleMapsDirectionsUrl, this scheme has no "start from wherever I am"
 * default — it requires an explicit starting coordinate — so this reads the
 * browser's current position itself and returns null if that's unavailable
 * (permission denied, no geolocation) rather than the caller having to.
 *
 * This route scheme is far less documented than the single-place link
 * above and untested against a real Kakao Map install — if it turns out to
 * be wrong, the single-place "Kakao Map" button on each place is the
 * verified fallback.
 */
export async function kakaoMapDirectionsUrl(places: Place[]): Promise<string | null> {
  // Keep the given order (not reordered by distance) so the route reads
  // the same top-to-bottom order as the list it came from. Places outside
  // Korea are dropped rather than failing the whole route — this also
  // naturally hides the button for a trip that isn't in Korea at all,
  // since `coordinates` ends up empty.
  const coordinates = places
    .filter(
      (p): p is Place & { lat: number; lng: number } =>
        p.lat !== null && p.lng !== null && isInKorea(p.lat, p.lng),
    )
    .map((p) => `${p.lat},${p.lng}`);
  if (coordinates.length === 0) return null;

  const origin = await getCurrentLocation();
  if (!origin) return null;

  const destination = coordinates[coordinates.length - 1];
  const waypoints = coordinates.slice(0, -1).slice(0, 5);

  const params = new URLSearchParams({
    sp: `${origin.lat},${origin.lng}`,
    ep: destination,
    by: "car",
  });
  waypoints.forEach((waypoint, index) => {
    params.set(index === 0 ? "vp" : `vp${index + 1}`, waypoint);
  });
  return `http://m.map.kakao.com/scheme/route?${params.toString()}`;
}
