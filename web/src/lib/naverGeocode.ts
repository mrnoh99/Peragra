import { loadNaverMapsScript } from "./naverMapsLoader";

/**
 * Free-text geocoding via the NAVER Maps JS API's Geocoder submodule, for
 * people who've opted into Naver Maps in Settings with their own NCP
 * Client ID — see naverMapsLoader.ts for why this goes through the loaded
 * SDK rather than a plain fetch.
 */
export async function geocodeWithNaver(
  query: string,
  clientId: string,
): Promise<{ lat: number; lng: number; displayName: string } | null> {
  try {
    await loadNaverMapsScript(clientId);
  } catch (error) {
    // A bad/unconfigured Client ID, a blocked network, or a timeout all
    // reject here — never let that become an uncaught rejection, since
    // every call site treats this the same as "couldn't geocode" and
    // falls back accordingly (an uncaught throw here has previously
    // broken the whole on-site-photo capture flow silently — see
    // AddPlaceModal.tsx's captureOnSitePlace, which has no top-level
    // catch of its own).
    console.warn("Failed to load Naver Maps:", error);
    return null;
  }
  const naverMaps = window.naver?.maps;
  if (!naverMaps) return null;

  return new Promise((resolve) => {
    naverMaps.Service.geocode({ query }, (status, response) => {
      if (status === naverMaps.Service.Status.ERROR) {
        console.warn("Naver geocoding failed: request error");
        resolve(null);
        return;
      }
      const first = response.v2.addresses[0];
      if (!first) {
        resolve(null);
        return;
      }
      const lat = Number.parseFloat(first.y);
      const lng = Number.parseFloat(first.x);
      if (Number.isNaN(lat) || Number.isNaN(lng)) {
        resolve(null);
        return;
      }
      resolve({ lat, lng, displayName: first.roadAddress || first.jibunAddress });
    });
  });
}

/** Builds a single readable address string out of a reverse-geocode region/land result. */
function formatReverseGeocodeResult(result: naver.maps.Service.ReverseGeocodeResult): string {
  const { region, land } = result;
  const parts = [region.area1?.name, region.area2?.name, region.area3?.name, region.area4?.name].filter(
    (part): part is string => !!part,
  );
  if (land) {
    if (land.name) parts.push(land.name);
    if (land.number1) parts.push(land.number2 ? `${land.number1}-${land.number2}` : land.number1);
    if (land.addition0?.value) parts.push(land.addition0.value);
  }
  return parts.join(" ");
}

/**
 * Reverse geocoding (coordinate -> address/name), for turning a GPS fix
 * read off an on-site photo into something readable. Prefers the
 * road-name address ("roadaddr") over the older lot-number one ("addr")
 * when both come back, since that's what Naver's own apps show by
 * default; `name` comes from a building/complex name in the road address
 * result when Naver has one (its closest notion of "the name of this
 * spot" — unlike Google's Geocoding API, there's no POI/establishment
 * type to key off here).
 */
export async function reverseGeocodeWithNaver(
  lat: number,
  lng: number,
  clientId: string,
): Promise<{ address: string; name: string | null } | null> {
  try {
    await loadNaverMapsScript(clientId);
  } catch (error) {
    // See the matching comment in geocodeWithNaver above — this must
    // never reject, since it's called unconditionally as a Korea-wide
    // name-lookup fallback (geocode.ts's reverseGeocode) whenever any
    // Naver Client ID is set, valid or not.
    console.warn("Failed to load Naver Maps:", error);
    return null;
  }
  const naverMaps = window.naver?.maps;
  if (!naverMaps) return null;

  return new Promise((resolve) => {
    naverMaps.Service.reverseGeocode(
      {
        coords: new naverMaps.LatLng(lat, lng),
        orders: [naverMaps.Service.OrderType.ROAD_ADDR, naverMaps.Service.OrderType.ADDR].join(","),
      },
      (status, response) => {
        if (status === naverMaps.Service.Status.ERROR) {
          console.warn("Naver reverse geocoding failed: request error");
          resolve(null);
          return;
        }
        const results = response.v2.results;
        if (!results || results.length === 0) {
          resolve(null);
          return;
        }
        const roadResult = results.find((r) => r.name === "roadaddr") ?? results[0];
        const address = formatReverseGeocodeResult(roadResult);
        if (!address) {
          resolve(null);
          return;
        }
        resolve({ address, name: roadResult.land?.addition0?.value ?? null });
      },
    );
  });
}
