/**
 * A rough bounding box for South Korea (including Jeju and the east-sea
 * islands). Kakao Map and Naver Map have essentially no useful data
 * outside Korea, unlike Google Maps, so their "open in..." links only
 * make sense for a place actually located here.
 */
export function isInKorea(lat: number, lng: number): boolean {
  return lat >= 33.0 && lat <= 38.9 && lng >= 124.5 && lng <= 132.0;
}
