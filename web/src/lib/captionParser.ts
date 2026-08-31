export interface ParsedCaption {
  name: string | null;
  address: string | null;
}

// Labels people commonly use in Korean/English caption text to call out a
// place's name or address explicitly.
const NAME_LABEL = /^(?:상호명?|가게\s*이름|매장명|카페명|식당명|이름|name)\s*[:：]\s*(.+)$/i;
const ADDRESS_LABEL = /^(?:주소|위치|location|address)\s*[:：]\s*(.+)$/i;

// An optional leading province/city name, so a Korean address match
// captures the whole thing (e.g. "서울 강남구 ...") rather than starting
// mid-string at the district — matters for splitting "Name - Address"
// lines, where whatever isn't part of the address match becomes the name.
const CITY_PREFIX =
  "(?:서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)(?:특별시|광역시|특별자치시|도|특별자치도)?\\s?";

// Korean road-name/land-lot address: e.g. "서울 강남구 테헤란로 123",
// "경기도 성남시 분당구 판교역로 235-1", "마포구 새창로2길 20" (road name
// followed by a numbered sub-"길", then the building number), or just
// "부산 영도구 청학동" (동-level only, no street number — common for
// landmarks/trailheads that don't have one). The trailing building number
// is optional for exactly that reason.
const KOREAN_ADDRESS = new RegExp(
  `(?:${CITY_PREFIX})?[가-힣]+(?:시|군|구)\\s?[가-힣0-9]+(?:읍|면|동|로|길)(?:\\s?[0-9]+길)?(?:\\s?[0-9]+(?:-[0-9]+)?)?`,
);

// A generic Western-style street address: a number followed by a street
// name, optionally with a comma-separated city/state/zip tail.
const WESTERN_ADDRESS =
  /\b\d{1,5}\s+[A-Za-z][A-Za-z0-9.'\s]*\b(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Boulevard|Dr|Drive|Ln|Lane|Way|Pl|Place|Ct|Court)\b\.?,?.*/i;

// Numbered/bulleted list markers ("1.", "1)", "①", "1️⃣", ...) that mark
// the start of a new place in a "recommend N spots" style caption.
const NUMBERED_MARKER =
  /^(?:\d{1,2}[.)]|[①②③④⑤⑥⑦⑧⑨⑩]|[❶❷❸❹❺❻❼❽❾❿]|\d{1,2}️?⃣)\s*/;

// Strips leading emoji/bullets/hashtags off a line before treating it as a
// name/address candidate. The hyphen sits at the very end of the class (and
// away from the full-width space) so it can never be read as a Unicode
// range with a neighboring char — an unescaped `-` between two literals in
// a character class is a range, and an earlier version of this regex
// accidentally ranged U+0020 through U+3000, matching almost every
// printable character and blanking out whole lines.
const LEADING_DECORATION = /^[\s\p{Extended_Pictographic}️*·•・#　-]+/u;

// Same idea, anchored at the end — strips a trailing separator/emoji run
// (e.g. the pin emoji before an inline address: "봉래산 📍 부산 ...", or a
// "Name - Address" dash) when extracting whatever precedes an address
// match on the same line.
const TRAILING_DECORATION = /[\s\p{Extended_Pictographic}️*·•・#　\-–—:：|]+$/u;

// A trailing Instagram handle mention in parentheses, e.g.
// "모모스커피 본점 (@momos_coffee)" — common in "📍 Name (@handle)" style
// listing captions. Stripped from the resolved name.
const TRAILING_HANDLE = /\s*\([@＠][^\s()]+\)\s*$/;

function cleanLine(line: string): string {
  return line.replace(LEADING_DECORATION, "").trim();
}

function cleanTrailing(line: string): string {
  return line.replace(TRAILING_DECORATION, "").trim();
}

function stripHandle(name: string): string {
  return name.replace(TRAILING_HANDLE, "").trim();
}

function isHashtagLine(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed) return true;
  const words = trimmed.split(/\s+/);
  const hashtags = words.filter((w) => w.startsWith("#"));
  return hashtags.length > 0 && hashtags.length >= words.length * 0.6;
}

function isListMarkerLine(line: string): boolean {
  return NUMBERED_MARKER.test(line);
}

function stripListMarker(line: string): string {
  return line.replace(NUMBERED_MARKER, "").trim();
}

function findAddressMatch(line: string): RegExpMatchArray | null {
  return line.match(KOREAN_ADDRESS) ?? line.match(WESTERN_ADDRESS);
}

/**
 * Parses a single place out of a block of caption lines (all the lines
 * believed to describe just one place). Handles both "Name" then "Address"
 * on separate lines, and "Name - Address" on the same line.
 */
function parsePlaceBlock(lines: string[]): ParsedCaption {
  let name: string | null = null;
  let address: string | null = null;

  // Pass 1: explicit "label: value" lines anywhere in the block.
  for (const line of lines) {
    const nameMatch = line.match(NAME_LABEL);
    if (nameMatch && !name) name = cleanLine(nameMatch[1]);

    const addressLabelMatch = line.match(ADDRESS_LABEL);
    if (addressLabelMatch && !address) address = cleanLine(addressLabelMatch[1]);
  }

  // Pass 2: address-shaped text, when no label found. Remember which line
  // and where in it, so a "Name - Address" line can still yield a name.
  let addressLineIndex = -1;
  let addressMatch: RegExpMatchArray | null = null;
  if (!address) {
    for (let i = 0; i < lines.length; i++) {
      const match = findAddressMatch(lines[i]);
      if (match) {
        address = cleanLine(match[0]);
        addressLineIndex = i;
        addressMatch = match;
        break;
      }
    }
  }

  // Pass 3: name. Try, in order: splitting the address line itself ("Name
  // - Address"); the nearest non-hashtag line immediately before the
  // address (closest wins, so an unrelated intro line earlier in a
  // multi-address block doesn't get picked over the actual name); then
  // any other usable, non-hashtag line in the block.
  if (!name) {
    if (addressLineIndex >= 0 && addressMatch?.index !== undefined) {
      const line = lines[addressLineIndex];
      const before = cleanTrailing(line.slice(0, addressMatch.index));
      const cleanedBefore = cleanLine(before);
      if (cleanedBefore) name = cleanedBefore;
    }
    if (!name && addressLineIndex > 0) {
      for (let i = addressLineIndex - 1; i >= 0; i--) {
        if (isHashtagLine(lines[i])) continue;
        const cleaned = cleanLine(lines[i]);
        if (cleaned.length > 0 && cleaned.length <= 60) {
          name = cleaned;
          break;
        }
      }
    }
    if (!name) {
      for (let i = 0; i < lines.length; i++) {
        if (i === addressLineIndex) continue;
        if (isHashtagLine(lines[i])) continue;
        const cleaned = cleanLine(lines[i]);
        if (cleaned.length > 0 && cleaned.length <= 60) {
          name = cleaned;
          break;
        }
      }
    }
  }

  return { name: name ? stripHandle(name) : name, address };
}

/**
 * Best-effort extraction of place name(s) and address(es) from Instagram
 * caption text the user provides (pasted, or OCR'd from a screenshot).
 * Instagram doesn't expose caption text via any client-accessible API, so
 * this only ever sees text the person brings over themselves — always
 * treat the result as a starting point the person can edit, not a
 * guaranteed-correct parse. Handles both a caption describing a single
 * place and one listing several — a "recommend N spots" numbered list, or
 * several distinct address-shaped lines without numbering — returning a
 * single-item list (or an empty one) when the caption only describes one
 * place.
 */
export function parsePlaces(caption: string): ParsedCaption[] {
  const lines = caption
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0);
  if (lines.length === 0) return [];

  // Group into blocks split at each numbered-list marker line. Anything
  // before the first marker (an intro line like "3 spots I loved!") is
  // discarded rather than treated as its own place.
  const blocks: string[][] = [];
  let current: string[] = [];
  let sawMarker = false;
  for (const line of lines) {
    if (isListMarkerLine(line)) {
      if (sawMarker && current.length > 0) blocks.push(current);
      sawMarker = true;
      current = [stripListMarker(line)];
    } else if (sawMarker) {
      current.push(line);
    }
  }
  if (sawMarker && current.length > 0) blocks.push(current);

  if (sawMarker && blocks.length > 1) {
    return blocks.map(parsePlaceBlock).filter((p) => p.name || p.address);
  }

  // No numbered list: look for multiple distinct address-shaped lines,
  // each paired with whatever precedes it (back to the previous address,
  // or the start of the caption) as its block.
  const addressLineIndexes = lines
    .map((line, i) => (findAddressMatch(line) ? i : -1))
    .filter((i) => i >= 0);

  if (addressLineIndexes.length <= 1) {
    const single = parsePlaceBlock(lines);
    return single.name || single.address ? [single] : [];
  }

  const results: ParsedCaption[] = [];
  let previousIndex = -1;
  for (const idx of addressLineIndexes) {
    const blockLines = lines.slice(previousIndex + 1, idx + 1);
    results.push(parsePlaceBlock(blockLines));
    previousIndex = idx;
  }
  return results;
}
