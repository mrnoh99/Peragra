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
 * Launches a custom-scheme URL (nmap://, tmap://, ...) via a direct
 * top-level navigation — wrapped in Android's `intent://` syntax first
 * when both on Android and the scheme has a known package (see
 * toAndroidIntentUrl).
 *
 * This used to go through a hidden iframe instead, to avoid Safari's own
 * "Safari cannot open the page because the address is invalid" alert that
 * a direct link tap pops when no app is installed to handle the scheme.
 * That traded away the one thing that actually matters: confirmed on a
 * real iPhone with Naver Map installed that the iframe approach no longer
 * switches to the app at all — modern iOS Safari appears to block
 * cross-origin iframe navigation to non-http(s) schemes outright,
 * regardless of whether a handler exists. Direct navigation is the one
 * mechanism confirmed to actually launch an installed app, so this is
 * back to that, accepting the alert as the cost when the app isn't
 * installed — these schemes have no documented web fallback of their own
 * either way.
 */
export function openCustomSchemeUrl(url: string): void {
  const isAndroid = /android/i.test(navigator.userAgent);
  const intentUrl = isAndroid ? toAndroidIntentUrl(url) : null;
  window.location.href = intentUrl ?? url;
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
