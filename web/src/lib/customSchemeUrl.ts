/**
 * Launches a custom-scheme URL (nmap://, tmap://, ...) through a hidden
 * iframe rather than a direct top-level navigation (`<a href>` or
 * `location.href =`) — the standard workaround Korean sites use for a
 * specific problem: confirmed on a real iPhone that a direct link tap to
 * an app-only scheme with no installed handler pops Safari's own "Safari
 * cannot open the page because the address is invalid" alert. A failed
 * iframe navigation to the same unhandled scheme doesn't trigger that
 * alert. Not guaranteed on every iOS/Safari version (Apple has tightened
 * custom scheme handling over time) — if the app is installed this still
 * opens it normally, but if the alert still appears on some devices, this
 * is the ceiling of what's fixable purely from the web side; these
 * schemes have no documented web fallback of their own.
 */
export function openCustomSchemeUrl(url: string): void {
  const iframe = document.createElement("iframe");
  iframe.style.display = "none";
  document.body.appendChild(iframe);
  iframe.src = url;
  window.setTimeout(() => {
    iframe.remove();
  }, 2000);
}
