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
