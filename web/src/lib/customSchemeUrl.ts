/**
 * Launches a custom-scheme URL (nmap://, tmap://, ...) via a direct
 * top-level navigation.
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
  window.location.href = url;
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
