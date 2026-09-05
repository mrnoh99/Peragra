const LOAD_TIMEOUT_MS = 10_000;

let scriptLoadPromise: Promise<void> | null = null;
let loadedForClientId: string | null = null;

/**
 * Loads the NAVER Maps JS API v3 bootstrap script with the geocoder
 * submodule, for people who've opted into Naver Maps in Settings with
 * their own NCP (Naver Cloud Platform) Client ID — the most accurate
 * geocoder for Korean addresses, since OpenStreetMap/Nominatim's Korean
 * coverage is thin and Google's Geocoding API has weak support for
 * Korean road-name addresses.
 *
 * Unlike Google's loader script (which does further async setup after its
 * own `onload` fires, requiring a documented `callback` query param to
 * know when it's really ready), Naver's script is a single synchronous
 * bundle — `naver.maps.Service` exists as soon as `onload` fires. A bad
 * Client ID or an unregistered domain doesn't reject the script load
 * itself, though — Naver calls `window.navermap_authFailure` instead
 * (their documented hook), which is wired up here alongside the same
 * timeout fallback used for Google, since not every failure mode is
 * guaranteed to invoke it.
 *
 * Shared by NaverMapView (to render a map) and naverGeocode (to use
 * naver.maps.Service) — geocoding must go through this loaded SDK rather
 * than a plain fetch to Naver's REST geocoding endpoint, which (like
 * Google's) isn't meant to be called directly from browser JS.
 */
export function loadNaverMapsScript(clientId: string): Promise<void> {
  if (window.naver?.maps?.Service && loadedForClientId === clientId) return Promise.resolve();
  if (scriptLoadPromise && loadedForClientId === clientId) return scriptLoadPromise;

  // A different Client ID than whatever's already loaded (or loading) —
  // Naver's API has no documented way to swap keys on an already-loaded
  // script, so this only ever matters if the user changes their key
  // mid-session; a full page reload is the practical way to pick that up,
  // but starting a fresh load attempt here is still more correct than
  // silently reusing the old key's script.
  loadedForClientId = clientId;
  scriptLoadPromise = new Promise((resolve, reject) => {
    const fail = (error: Error) => {
      scriptLoadPromise = null;
      loadedForClientId = null;
      reject(error);
    };

    const timeout = window.setTimeout(() => {
      fail(new Error("Timed out loading Naver Maps — check your Client ID"));
    }, LOAD_TIMEOUT_MS);

    window.navermap_authFailure = () => {
      window.clearTimeout(timeout);
      fail(new Error("Naver Maps rejected this Client ID — check it in Settings"));
    };

    const script = document.createElement("script");
    script.src = `https://oapi.map.naver.com/openapi/v3/maps.js?ncpKeyId=${encodeURIComponent(clientId)}&submodules=geocoder`;
    script.async = true;
    script.onload = () => {
      window.clearTimeout(timeout);
      if (window.naver?.maps?.Service) {
        resolve();
      } else {
        fail(new Error("Naver Maps script loaded but the API didn't initialize"));
      }
    };
    script.onerror = () => {
      window.clearTimeout(timeout);
      fail(new Error("Failed to load the Naver Maps script"));
    };
    document.body.appendChild(script);
  });
  return scriptLoadPromise;
}
