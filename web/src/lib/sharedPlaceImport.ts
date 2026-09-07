const URL_PATTERN = /https?:\/\/\S+/i;

export interface SharedPlaceCandidate {
  name: string;
  address: string;
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
 * shortened maps.app.goo.gl or naver.me URL) into coordinates, or fetch
 * it to read its Open Graph title the way the iOS app's OpenGraphFetcher
 * does for the same "link but no name" case (Google Maps' and Kakao
 * Map's own "Share" give only a link, unlike Naver Map's, which shares
 * the name and address as plain text alongside its link) — a browser's
 * fetch() to another site is blocked by CORS, and this is a static
 * GitHub Pages site with no backend of its own to do that fetch for it.
 * Instead the link is kept as the place's reference link, and the name
 * is geocoded the same way any manually-entered place already is. When
 * there's truly no name text to use, falls back to the same "Unknown"
 * placeholder the on-site photo flow uses when it can't tell a place's
 * name either — so the row is still reviewable and savable rather than
 * silently dropped (an unnamed row never gets saved).
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

  // Naver Map's share text is "Place Name\nAddress\n<link>" — no
  // separate title field. Some other apps instead give the name as its
  // own title, with text holding just a description/address line.
  // Either way, whichever non-URL line(s) of `text` weren't already
  // claimed as the name is the closest thing to an address this format
  // offers.
  const lines = nonUrlLines(text);
  const name = title || lines[0] || "Unknown";
  const address = (title ? lines[0] : lines[1]) ?? "";

  return {
    name,
    address,
    link: url || extractUrl(text),
  };
}

function extractUrl(text: string): string {
  const match = text.match(URL_PATTERN);
  return match ? match[0] : "";
}

function nonUrlLines(text: string): string[] {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line !== "" && !URL_PATTERN.test(line));
}
