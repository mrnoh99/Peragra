/**
 * A manually-typed or AI-extracted link often has no "https://" — this
 * adds one so it's actually clickable (browsers resolve a bare
 * "instagram.com/..." href as a relative path, not the address it looks
 * like) and so hostname parsing below actually works.
 */
export function normalizeLinkHref(url: string): string {
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(url) ? url : `https://${url}`;
}

/** Whether a place's manually-entered/AI-extracted link points at
 *  Instagram — used to label it "Instagram" instead of the generic
 *  "Website" wherever it's shown. */
export function isInstagramLink(url: string): boolean {
  try {
    return new URL(normalizeLinkHref(url)).hostname.replace(/^www\./, "") === "instagram.com";
  } catch {
    return false;
  }
}
