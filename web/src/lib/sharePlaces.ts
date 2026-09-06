import { saveJsonFile } from "./backup";
import { PLACE_CATEGORIES, type Place, type PlaceCategory } from "../types";

/**
 * A place stripped down to what's worth handing to someone else — no id,
 * board, coordinates, visited/favorite status, or collections, since
 * those are either meaningless or private outside the sender's own board.
 * The recipient's copy gets its own id and is geocoded fresh on import.
 */
export interface SharedPlace {
  name: string;
  category: PlaceCategory;
  address: string;
  phone: string | null;
  notes: string;
  linkUrl: string | null;
}

export interface SharedPlacesPayload {
  app: "peragra";
  kind: "places";
  version: 1;
  places: SharedPlace[];
}

export function buildSharedPlacesPayload(places: Place[]): SharedPlacesPayload {
  return {
    app: "peragra",
    kind: "places",
    version: 1,
    places: places.map((p) => ({
      name: p.name,
      category: p.category,
      address: p.address,
      phone: p.phone,
      notes: p.notes,
      linkUrl: p.linkUrl,
    })),
  };
}

export function sharedPlacesToText(payload: SharedPlacesPayload): string {
  return JSON.stringify(payload, null, 2);
}

export function sharedPlacesFilename(date = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  const stamp = `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
  return `peragra_places_${stamp}.json`;
}

/** Saves selected places to a location the person picks — see
 *  saveJsonFile in backup.ts for the File System Access API/download
 *  fallback behavior this shares with the whole-app backup. */
export function saveSharedPlacesFile(payload: SharedPlacesPayload): Promise<"saved" | "cancelled" | "downloaded"> {
  return saveJsonFile(payload, sharedPlacesFilename(), "Peragra places");
}

/**
 * Parses text as a Peragra "shared places" payload — pasted from another
 * person's "Copy as text" share, or read from their "Save as file". Null
 * for anything that isn't recognizably that (not JSON, wrong shape, or a
 * places array with nothing usable in it) rather than throwing, since the
 * caller just needs a yes/no to decide how to handle the input.
 */
export function parseSharedPlacesText(text: string): SharedPlace[] | null {
  const trimmed = text.trim();
  if (!trimmed) return null;

  let data: unknown;
  try {
    data = JSON.parse(trimmed);
  } catch {
    return null;
  }
  if (typeof data !== "object" || data === null) return null;
  const obj = data as Record<string, unknown>;
  if (obj.app !== "peragra" || obj.kind !== "places" || !Array.isArray(obj.places)) return null;

  const validCategories = new Set(PLACE_CATEGORIES.map((c) => c.value));
  const places: SharedPlace[] = [];
  for (const raw of obj.places) {
    if (typeof raw !== "object" || raw === null) continue;
    const p = raw as Record<string, unknown>;
    const name = typeof p.name === "string" ? p.name.trim() : "";
    if (!name) continue;
    places.push({
      name,
      category: typeof p.category === "string" && validCategories.has(p.category as PlaceCategory)
        ? (p.category as PlaceCategory)
        : "restaurant",
      address: typeof p.address === "string" ? p.address : "",
      phone: typeof p.phone === "string" && p.phone.trim() ? p.phone : null,
      notes: typeof p.notes === "string" ? p.notes : "",
      linkUrl: typeof p.linkUrl === "string" && p.linkUrl.trim() ? p.linkUrl : null,
    });
  }
  return places.length > 0 ? places : null;
}
