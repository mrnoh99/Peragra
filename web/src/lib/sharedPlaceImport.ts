const URL_PATTERN = /https?:\/\/\S+/i;

export interface SharedPlaceCandidate {
  name: string;
  link: string;
}

/**
 * Turns whatever the OS share sheet handed Peragra (via the PWA's
 * share_target — see manifest.webmanifest) into a place candidate. Not
 * tied to any one map app in code — any app's "Share" action that sends a
 * URL or text lands here the same way, whether that's Google Maps, Naver
 * Map, Kakao Map, or anything else — which is what the "From Map" board
 * (see App.tsx) is named for.
 *
 * Deliberately doesn't try to resolve the shared link itself (e.g. a
 * shortened maps.app.goo.gl or naver.me URL) into coordinates — that
 * would need a server-side redirect fetch, which a static GitHub Pages
 * site has no way to do, and a cross-origin fetch from the browser is
 * blocked by CORS. Instead the link is kept as the place's reference
 * link, and the name (most map apps' share text is "Place Name\n<link>")
 * is geocoded the same way any manually-entered place already is.
 */
export function parseSharedPlace(input: {
  title?: string | null;
  text?: string | null;
  url?: string | null;
}): SharedPlaceCandidate | null {
  const title = input.title?.trim() ?? "";
  const text = input.text?.trim() ?? "";
  const url = input.url?.trim() ?? "";
  if (!title && !text && !url) return null;

  return {
    name: title || nameFromText(text),
    link: url || extractUrl(text),
  };
}

function extractUrl(text: string): string {
  const match = text.match(URL_PATTERN);
  return match ? match[0] : "";
}

function nameFromText(text: string): string {
  const firstLine = text.split("\n")[0]?.trim() ?? "";
  return URL_PATTERN.test(firstLine) ? "" : firstLine;
}
