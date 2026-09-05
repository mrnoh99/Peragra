/**
 * Android package name for each custom scheme that's confirmed to need
 * (and support) the `intent://` wrapping below — see
 * `toAndroidIntentUrl` for why. Not every scheme this app opens is
 * listed: only add one here once its Android package name and behavior
 * are actually confirmed, since wrapping a scheme incorrectly is worse
 * than leaving it as a bare `scheme://` link.
 */
const ANDROID_PACKAGE_BY_SCHEME: Record<string, string> = {
  nmap: "com.nhn.android.nmap",
};

/**
 * A bare custom-scheme URL (nmap://...) opened via a direct top-level
 * navigation is unreliable specifically on Android Chrome: unlike iOS
 * Safari (which reliably launches the installed app, or shows its own
 * "address is invalid" alert otherwise), Chrome's scheme-navigation
 * handling for a scheme with no registered Web Intent Filter often just
 * does nothing at all, or launches the target app without actually
 * passing its own query parameters through — reported as "opens Naver
 * Map, but the place isn't shown". Android's own documented fix is its
 * `intent://` URL syntax, which explicitly names the target app's
 * package so Chrome resolves it as a real Android Intent instead of an
 * ordinary (and, for these schemes, unregistered) URL scheme.
 * Returns null for a scheme with no known package (see
 * ANDROID_PACKAGE_BY_SCHEME) — callers fall back to the plain URL then.
 */
function toAndroidIntentUrl(schemeUrl: string): string | null {
  const match = schemeUrl.match(/^([a-z][a-z0-9+.-]*):\/\/(.*)$/i);
  if (!match) return null;
  const [, scheme, rest] = match;
  const packageName = ANDROID_PACKAGE_BY_SCHEME[scheme];
  if (!packageName) return null;
  return `intent://${rest}#Intent;scheme=${scheme};action=android.intent.action.VIEW;category=android.intent.category.BROWSABLE;package=${packageName};end`;
}

/**
 * Launches a custom-scheme URL (nmap://, tmap://, ...) — wrapped in
 * Android's `intent://` syntax first when both on Android and the scheme
 * has a known package (see toAndroidIntentUrl).
 *
 * Two earlier approaches were tried and ruled out here:
 * - A hidden iframe, to avoid Safari's own "Safari cannot open the page
 *   because the address is invalid" alert that a direct link tap pops
 *   when no app is installed. Confirmed on a real iPhone with Naver Map
 *   installed that this approach doesn't switch to the app at all —
 *   modern iOS Safari appears to block cross-origin iframe navigation to
 *   non-http(s) schemes outright, regardless of whether a handler exists.
 * - Assigning `window.location.href` directly, which did switch to the
 *   app on that same test at the time — but was later reported to
 *   silently do nothing at all (no app switch, no alert either) with the
 *   Naver Map app installed. iOS Safari appears to treat a script setting
 *   `location.href` to a non-http(s) scheme with more suspicion than an
 *   actual `<a href>` element being clicked, even from the same
 *   synchronous click handler.
 *
 * This creates a real (invisible) anchor element and dispatches a click
 * on it instead — the one mechanism that's consistently treated as a
 * genuine, user-initiated link navigation regardless of scheme. Still
 * accepts Safari's own alert as the cost when the app isn't installed —
 * these schemes have no documented web fallback of their own either way.
 */
export function openCustomSchemeUrl(url: string): void {
  const isAndroid = /android/i.test(navigator.userAgent);
  const intentUrl = isAndroid ? toAndroidIntentUrl(url) : null;
  const link = document.createElement("a");
  link.href = intentUrl ?? url;
  link.style.display = "none";
  document.body.appendChild(link);
  link.click();
  link.remove();
}

/**
 * Builds a query string for a custom-scheme URL (nmap://, tmap://, ...)
 * using plain percent-encoding (spaces as %20) instead of
 * `URLSearchParams`/`application/x-www-form-urlencoded` encoding (spaces
 * as +). Tmap (with a real place name, which almost always has a space)
 * failed to launch at all with the `URLSearchParams`-built URL on a real
 * iPhone with the app installed — every working Tmap/Naver Map
 * integration example found elsewhere encodes with the equivalent of
 * `encodeURIComponent`, never `+`-for-space form encoding, which points
 * at these app-only schemes expecting the former and choking on (or
 * simply not decoding) the latter. Not independently confirmed by
 * isolating just this change, since the previous attempt changed the
 * launch mechanism at the same time — worth re-testing this specific
 * fix on device.
 */
export function buildCustomSchemeQuery(params: Record<string, string>): string {
  return Object.entries(params)
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
    .join("&");
}
