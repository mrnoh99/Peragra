import type { Place } from "../types";

/** Lowercases and strips everything but letters/digits, so "Blue Bottle
 *  Coffee", "blue-bottle coffee!", and "BlueBottleCoffee" all compare
 *  equal — the differences that actually show up between the same place
 *  typed twice (spacing, punctuation, case) rather than real distinctions. */
function normalize(text: string): string {
  return text.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
}

const EARTH_RADIUS_METERS = 6371000;

function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return EARTH_RADIUS_METERS * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** Places within this distance of each other, with matching names, are
 *  treated as the same real-world place — loose enough to cover a
 *  geocoder snapping to a slightly different point on the same building
 *  or block, tight enough that two different branches of the same chain
 *  don't get merged. */
const DUPLICATE_DISTANCE_METERS = 150;

/**
 * Whether two places look like the same real-world place saved twice:
 * their names must match (after normalizing away case/spacing/
 * punctuation), AND either their coordinates are close together, their
 * addresses match/overlap, or — only when neither place has any
 * coordinate or address to compare — the name match stands on its own,
 * since there's nothing else available to check.
 */
export function placesLikelyDuplicate(a: Place, b: Place): boolean {
  if (!a.name.trim() || !b.name.trim()) return false;
  if (normalize(a.name) !== normalize(b.name)) return false;

  if (a.lat !== null && a.lng !== null && b.lat !== null && b.lng !== null) {
    return haversineMeters(a.lat, a.lng, b.lat, b.lng) <= DUPLICATE_DISTANCE_METERS;
  }

  const addrA = normalize(a.address);
  const addrB = normalize(b.address);
  if (addrA && addrB) {
    return addrA === addrB || addrA.includes(addrB) || addrB.includes(addrA);
  }

  // Neither has a coordinate, and at least one has no address either —
  // nothing left to compare but the name, which already matched.
  return true;
}

/**
 * Groups a board's places into duplicate clusters — union-find over
 * placesLikelyDuplicate so A-matches-B and B-matches-C still group all
 * three together even if A and C weren't compared as a close enough
 * pair directly. Only groups of 2+ are returned; places with no
 * duplicate are simply omitted rather than returned as singleton groups.
 */
export function findDuplicateGroups(places: Place[]): Place[][] {
  const parent = new Map<string, string>();
  function find(id: string): string {
    let root = id;
    while (parent.get(root) !== undefined && parent.get(root) !== root) {
      root = parent.get(root)!;
    }
    parent.set(id, root);
    return root;
  }
  function union(a: string, b: string) {
    const rootA = find(a);
    const rootB = find(b);
    if (rootA !== rootB) parent.set(rootA, rootB);
  }

  for (const place of places) parent.set(place.id, place.id);

  for (let i = 0; i < places.length; i++) {
    for (let j = i + 1; j < places.length; j++) {
      if (placesLikelyDuplicate(places[i], places[j])) {
        union(places[i].id, places[j].id);
      }
    }
  }

  const groups = new Map<string, Place[]>();
  for (const place of places) {
    const root = find(place.id);
    const group = groups.get(root);
    if (group) group.push(place);
    else groups.set(root, [place]);
  }

  return [...groups.values()].filter((group) => group.length > 1);
}
