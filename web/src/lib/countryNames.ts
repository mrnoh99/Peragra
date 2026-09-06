/**
 * Korean country names mapped to their canonical English form, used only
 * to normalize a trailing country name in an address before geocoding —
 * see normalizeTrailingCountryName below. Not exhaustive (adding a wrong
 * mapping is worse than omitting a rare country), but covers the
 * countries a Korean-language travel post is actually likely to name.
 */
const KOREAN_TO_ENGLISH_COUNTRY: Record<string, string> = {
  대한민국: "South Korea",
  한국: "South Korea",
  일본: "Japan",
  중국: "China",
  대만: "Taiwan",
  홍콩: "Hong Kong",
  마카오: "Macau",
  태국: "Thailand",
  베트남: "Vietnam",
  필리핀: "Philippines",
  인도네시아: "Indonesia",
  인도: "India",
  싱가포르: "Singapore",
  말레이시아: "Malaysia",
  캄보디아: "Cambodia",
  라오스: "Laos",
  미얀마: "Myanmar",
  네팔: "Nepal",
  스리랑카: "Sri Lanka",
  몽골: "Mongolia",
  부탄: "Bhutan",
  방글라데시: "Bangladesh",
  파키스탄: "Pakistan",
  아프가니스탄: "Afghanistan",
  몰디브: "Maldives",
  이탈리아: "Italy",
  프랑스: "France",
  독일: "Germany",
  스페인: "Spain",
  영국: "United Kingdom",
  아일랜드: "Ireland",
  아이슬란드: "Iceland",
  그리스: "Greece",
  포르투갈: "Portugal",
  스위스: "Switzerland",
  오스트리아: "Austria",
  네덜란드: "Netherlands",
  벨기에: "Belgium",
  룩셈부르크: "Luxembourg",
  노르웨이: "Norway",
  스웨덴: "Sweden",
  덴마크: "Denmark",
  핀란드: "Finland",
  폴란드: "Poland",
  체코: "Czech Republic",
  슬로바키아: "Slovakia",
  헝가리: "Hungary",
  루마니아: "Romania",
  불가리아: "Bulgaria",
  크로아티아: "Croatia",
  슬로베니아: "Slovenia",
  세르비아: "Serbia",
  보스니아헤르체고비나: "Bosnia and Herzegovina",
  몬테네그로: "Montenegro",
  알바니아: "Albania",
  북마케도니아: "North Macedonia",
  우크라이나: "Ukraine",
  벨라루스: "Belarus",
  러시아: "Russia",
  튀르키예: "Turkey",
  터키: "Turkey",
  이스라엘: "Israel",
  요르단: "Jordan",
  레바논: "Lebanon",
  이집트: "Egypt",
  모로코: "Morocco",
  튀니지: "Tunisia",
  알제리: "Algeria",
  남아프리카공화국: "South Africa",
  케냐: "Kenya",
  탄자니아: "Tanzania",
  에티오피아: "Ethiopia",
  나이지리아: "Nigeria",
  아랍에미리트: "United Arab Emirates",
  사우디아라비아: "Saudi Arabia",
  카타르: "Qatar",
  쿠웨이트: "Kuwait",
  오만: "Oman",
  바레인: "Bahrain",
  이란: "Iran",
  이라크: "Iraq",
  카자흐스탄: "Kazakhstan",
  우즈베키스탄: "Uzbekistan",
  조지아: "Georgia",
  아르메니아: "Armenia",
  아제르바이잔: "Azerbaijan",
  키프로스: "Cyprus",
  몰타: "Malta",
  모나코: "Monaco",
  리히텐슈타인: "Liechtenstein",
  산마리노: "San Marino",
  바티칸: "Vatican City",
  안도라: "Andorra",
  에스토니아: "Estonia",
  라트비아: "Latvia",
  리투아니아: "Lithuania",
  호주: "Australia",
  오스트레일리아: "Australia",
  뉴질랜드: "New Zealand",
  피지: "Fiji",
  파푸아뉴기니: "Papua New Guinea",
  미국: "United States",
  캐나다: "Canada",
  멕시코: "Mexico",
  브라질: "Brazil",
  아르헨티나: "Argentina",
  칠레: "Chile",
  페루: "Peru",
  콜롬비아: "Colombia",
  에콰도르: "Ecuador",
  볼리비아: "Bolivia",
  우루과이: "Uruguay",
  파라과이: "Paraguay",
  베네수엘라: "Venezuela",
  쿠바: "Cuba",
  자메이카: "Jamaica",
  도미니카공화국: "Dominican Republic",
};

// Longest Korean name first, so "인도네시아" is tried before the "인도" it
// contains — otherwise the shorter name would match first and leave the
// rest of "네시아" stuck onto the replaced English name.
const SORTED_ENTRIES = Object.entries(KOREAN_TO_ENGLISH_COUNTRY).sort(
  (a, b) => b[0].length - a[0].length,
);

/**
 * If an address ends with a known Korean country name — as a Korean
 * Google/Naver Maps address commonly does, translating only the country
 * while leaving the rest of the address in its original script — this
 * replaces it with the country's canonical English name instead. Mixing
 * scripts within one free-text query is exactly the kind of address a
 * geocoder (Nominatim especially) tends to fail on; this fixes the one
 * component that's actually safe to translate; every other part of the
 * address is left untouched.
 */
export function normalizeTrailingCountryName(address: string): string {
  const trimmed = address.trim();
  if (!trimmed) return trimmed;

  for (const [korean, english] of SORTED_ENTRIES) {
    if (!trimmed.endsWith(korean)) continue;
    const precedingIndex = trimmed.length - korean.length - 1;
    const precedingChar = precedingIndex >= 0 ? trimmed[precedingIndex] : undefined;
    // Require the match to be its own token (preceded by a comma/space,
    // or be the whole string) — not a substring inside a longer Korean
    // word that happens to end the same way.
    if (precedingChar !== undefined && precedingChar !== "," && precedingChar !== " ") continue;

    const rest = trimmed.slice(0, trimmed.length - korean.length).replace(/[,\s]+$/, "");
    return rest ? `${rest}, ${english}` : english;
  }

  return trimmed;
}

/**
 * Whether a piece of text (an address or a place name) mentions a known
 * non-Korean country by its Korean name, anywhere in the string — used to
 * tell whether a place is outside Korea before it has any geocoded
 * coordinate yet (see mapProviderPolicy.ts), unlike
 * normalizeTrailingCountryName's stricter "own trailing token" match.
 */
export function mentionsNonKoreanCountry(text: string): boolean {
  return SORTED_ENTRIES.some(
    ([korean, english]) => english !== "South Korea" && text.includes(korean),
  );
}
