const INSTAGRAM_URL_PATTERN =
  /^https?:\/\/(www\.)?instagram\.com\/(p|reel|reels|tv)\/[a-zA-Z0-9_-]+\/?/i;

export function isInstagramPostUrl(value: string): boolean {
  return INSTAGRAM_URL_PATTERN.test(value.trim());
}

export function normalizeInstagramUrl(value: string): string {
  const trimmed = value.trim();
  const match = trimmed.match(INSTAGRAM_URL_PATTERN);
  return match ? match[0] : trimmed;
}
