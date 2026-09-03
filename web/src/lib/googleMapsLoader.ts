declare global {
  interface Window {
    google?: typeof google;
    __peragraGoogleMapsCallbackReady?: () => void;
  }
}

const CALLBACK_NAME = "__peragraGoogleMapsCallbackReady";
const LOAD_TIMEOUT_MS = 10_000;

let scriptLoadPromise: Promise<void> | null = null;

/**
 * Loads the Maps JS API bootstrap script. `onload` firing only means that
 * small loader shim finished downloading — it does its own further async
 * work before `google.maps.*` actually exists, so readiness has to come
 * from the `callback` query param Google's loader invokes once the API is
 * really ready (their documented pattern), not from the script tag's own
 * load event. A bad/restricted key never calls that callback and doesn't
 * fire `onerror` either (the request itself succeeds, Google just logs a
 * console error), hence the timeout fallback.
 *
 * Shared by GoogleMapView (to render a map) and googleGeocode (to use
 * google.maps.Geocoder) — geocoding must go through this loaded SDK
 * rather than a plain fetch to Google's REST Geocoding endpoint, which
 * has no CORS headers and is blocked outright when called directly from
 * browser JS.
 */
export function loadGoogleMapsScript(apiKey: string): Promise<void> {
  if (window.google?.maps) return Promise.resolve();
  if (scriptLoadPromise) return scriptLoadPromise;

  scriptLoadPromise = new Promise((resolve, reject) => {
    const fail = (error: Error) => {
      // Don't cache a failed load — a corrected key (or restored network)
      // should get a fresh attempt next time, not this same rejection.
      scriptLoadPromise = null;
      reject(error);
    };

    const timeout = window.setTimeout(() => {
      fail(new Error("Timed out loading Google Maps — check your API key"));
    }, LOAD_TIMEOUT_MS);

    window[CALLBACK_NAME] = () => {
      window.clearTimeout(timeout);
      resolve();
    };

    const script = document.createElement("script");
    script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(apiKey)}&callback=${CALLBACK_NAME}`;
    script.async = true;
    script.onerror = () => {
      window.clearTimeout(timeout);
      fail(new Error("Failed to load Google Maps script"));
    };
    document.body.appendChild(script);
  });
  return scriptLoadPromise;
}
