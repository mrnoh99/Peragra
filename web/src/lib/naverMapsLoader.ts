const LOAD_TIMEOUT_MS = 10_000;
const SERVICE_POLL_INTERVAL_MS = 100;

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
 * Naver's script usually makes `naver.maps.Service` available as soon as
 * `onload` fires, but with `submodules=geocoder` the bootstrap script can
 * kick off a further async request for the submodule itself — reported on
 * a real device as "script loaded but the API didn't initialize" even
 * with a valid Client ID, because the geocoder submodule was still a beat
 * behind the outer `<script>` tag's own `onload`. So `onload` polls
 * briefly for `naver.maps.Service` instead of checking exactly once,
 * before falling through to the same timeout used for a genuine hang.
 * A bad Client ID or an unregistered domain doesn't reject the script
 * load itself, though — Naver calls `window.navermap_authFailure` instead
 * (their documented hook), which is wired up here alongside that timeout
 * fallback used for Google, since not every failure mode is guaranteed to
 * invoke it.
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
    let settled = false;
    let pollInterval: number | null = null;

    const stopWaiting = () => {
      window.clearTimeout(timeout);
      if (pollInterval !== null) window.clearInterval(pollInterval);
    };

    const fail = (error: Error) => {
      if (settled) return;
      settled = true;
      stopWaiting();
      scriptLoadPromise = null;
      loadedForClientId = null;
      reject(error);
    };

    const succeed = () => {
      if (settled) return;
      settled = true;
      stopWaiting();
      resolve();
    };

    const timeout = window.setTimeout(() => {
      fail(new Error("Timed out loading Naver Maps — check your Client ID"));
    }, LOAD_TIMEOUT_MS);

    window.navermap_authFailure = () => {
      fail(new Error("Naver Maps rejected this Client ID — check it in Settings"));
    };

    const script = document.createElement("script");
    script.src = `https://oapi.map.naver.com/openapi/v3/maps.js?ncpKeyId=${encodeURIComponent(clientId)}&submodules=geocoder`;
    script.async = true;
    script.onload = () => {
      if (window.naver?.maps?.Service) {
        succeed();
        return;
      }
      // Not ready the instant onload fires — poll for it briefly rather
      // than failing immediately; the timeout above still catches a
      // genuine failure to ever initialize.
      pollInterval = window.setInterval(() => {
        if (window.naver?.maps?.Service) succeed();
      }, SERVICE_POLL_INTERVAL_MS);
    };
    script.onerror = () => {
      fail(new Error("Failed to load the Naver Maps script"));
    };
    document.body.appendChild(script);
  });
  return scriptLoadPromise;
}
