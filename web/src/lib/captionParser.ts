export interface ParsedCaption {
  name: string | null;
  address: string | null;
}

// Labels people commonly use in Korean/English caption text to call out a
// place's name or address explicitly.
const NAME_LABEL = /^(?:상호명?|가게\s*이름|매장명|카페명|식당명|이름|name)\s*[:：]\s*(.+)$/i;
const ADDRESS_LABEL = /^(?:주소|위치|location|address)\s*[:：]\s*(.+)$/i;

// Korean road-name/land-lot address: e.g. "서울 강남구 테헤란로 123",
// "경기도 성남시 분당구 판교역로 235-1", or "마포구 새창로2길 20" (road name
// followed by a numbered sub-"길", then the building number).
const KOREAN_ADDRESS =
  /[가-힣]+(?:시|군|구)\s?[가-힣0-9]+(?:읍|면|동|로|길)(?:\s?[0-9]+길)?\s?[0-9]+(?:-[0-9]+)?/;

// A generic Western-style street address: a number followed by a street
// name, optionally with a comma-separated city/state/zip tail.
const WESTERN_ADDRESS =
  /\b\d{1,5}\s+[A-Za-z][A-Za-z0-9.'\s]*\b(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Boulevard|Dr|Drive|Ln|Lane|Way|Pl|Place|Ct|Court)\b\.?,?.*/i;

// Strips leading emoji/bullets/hashtags off a line before treating it as a
// name/address candidate. The hyphen sits at the very end of the class (and
// away from the full-width space) so it can never be read as a Unicode
// range with a neighboring char — an unescaped `-` between two literals in
// a character class is a range, and an earlier version of this regex
// accidentally ranged U+0020 through U+3000, matching almost every
// every printable character and blanking out whole lines.
const LEADING_DECORATION = /^[\s\p{Extended_Pictographic}\uFE0F*\u00B7\u2022\u30FB#\u3000-]+/u;

function cleanLine(line: string): string {
  return line.replace(LEADING_DECORATION, "").trim();
}

function isHashtagLine(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed) return true;
  const words = trimmed.split(/\s+/);
  const hashtags = words.filter((w) => w.startsWith("#"));
  return hashtags.length > 0 && hashtags.length >= words.length * 0.6;
}

/**
 * Best-effort extraction of a place name and address from Instagram caption
 * text the user provides (pasted, or OCR'd from a screenshot). Instagram
 * doesn't expose caption text via any client-accessible API, so this only
 * ever sees text the person brings over themselves — always treat the
 * result as a starting point the person can edit, not a guaranteed-correct
 * parse.
 */
export function parseCaption(caption: string): ParsedCaption {
  const rawLines = caption.split(/\r?\n/).map((l) => l.trim());
  const lines = rawLines.filter((l) => l.length > 0);

  let name: string | null = null;
  let address: string | null = null;

  // Pass 1: explicit "label: value" lines anywhere in the caption.
  for (const line of lines) {
    const nameMatch = line.match(NAME_LABEL);
    if (nameMatch && !name) name = cleanLine(nameMatch[1]);

    const addressMatch = line.match(ADDRESS_LABEL);
    if (addressMatch && !address) address = cleanLine(addressMatch[1]);
  }

  // Pass 2: address-shaped lines (Korean or Western), when no label found.
  if (!address) {
    for (const line of lines) {
      const korean = line.match(KOREAN_ADDRESS);
      if (korean) {
        address = cleanLine(korean[0]);
        break;
      }
      const western = line.match(WESTERN_ADDRESS);
      if (western) {
        address = cleanLine(western[0]);
        break;
      }
    }
  }

  // Pass 3: name fallback — first non-hashtag, non-address line, so the
  // typical "shop name on line 1, then description/address" caption shape
  // works without any labels at all.
  if (!name) {
    for (const line of lines) {
      if (isHashtagLine(line)) continue;
      if (address && line.includes(address)) continue;
      const cleaned = cleanLine(line);
      if (cleaned.length > 0 && cleaned.length <= 60) {
        name = cleaned;
        break;
      }
    }
  }

  return { name, address };
}
