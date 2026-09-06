import type { Collection, Place, Trip } from "../types";

/**
 * Backup/restore for the whole app's data — the same JSON schema the iOS
 * app's own backup uses, so a file exported from one can be restored on
 * the other. Ids are preserved on restore, so re-importing the same
 * backup twice reconstructs the same graph rather than duplicating it.
 */
export interface BackupData {
  app: "peragra";
  version: 1;
  exportedAt: number;
  trips: Trip[];
  places: Place[];
  collections: Collection[];
}

export function buildBackup(trips: Trip[], places: Place[], collections: Collection[]): BackupData {
  return { app: "peragra", version: 1, exportedAt: Date.now(), trips, places, collections };
}

function timestamp(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
}

export function backupFilename(date = new Date()): string {
  return `peragra_${timestamp(date)}.json`;
}

/** Same BackupData shape as the whole-app backup, just scoped to one
 *  board — see useStore's importBoardData for the receiving end. */
export function boardBackupFilename(tripName: string, date = new Date()): string {
  const slug = tripName
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return `peragra_board_${slug || "board"}_${timestamp(date)}.json`;
}

export function parseBackup(text: string): BackupData {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error("That doesn't look like a Peragra backup file.");
  }
  if (
    typeof data !== "object" ||
    data === null ||
    (data as { app?: unknown }).app !== "peragra" ||
    !Array.isArray((data as { trips?: unknown }).trips) ||
    !Array.isArray((data as { places?: unknown }).places) ||
    !Array.isArray((data as { collections?: unknown }).collections)
  ) {
    throw new Error("That doesn't look like a Peragra backup file.");
  }
  return data as BackupData;
}

/**
 * Saves arbitrary JSON data to a location the person picks, via the File
 * System Access API where the browser supports it (Chrome/Edge); falls
 * back to a plain download (the browser's default downloads location)
 * elsewhere — notably Safari, which has no such picker. Shared by the
 * whole-app backup below and by the "share selected places" export.
 */
export async function saveJsonFile(
  data: unknown,
  filename: string,
  description: string,
): Promise<"saved" | "cancelled" | "downloaded"> {
  const json = JSON.stringify(data, null, 2);

  const showSaveFilePicker = (
    window as unknown as {
      showSaveFilePicker?: (options: {
        suggestedName: string;
        types: { description: string; accept: Record<string, string[]> }[];
      }) => Promise<FileSystemFileHandle>;
    }
  ).showSaveFilePicker;

  if (typeof showSaveFilePicker === "function") {
    try {
      const handle = await showSaveFilePicker({
        suggestedName: filename,
        types: [{ description, accept: { "application/json": [".json"] } }],
      });
      const writable = await handle.createWritable();
      await writable.write(json);
      await writable.close();
      return "saved";
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") return "cancelled";
      throw err;
    }
  }

  const blob = new Blob([json], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  // Safari only honors a click on an <a download> that's actually in the
  // document — clicking one that was never appended silently does
  // nothing there, even though Chrome/Firefox don't require it.
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
  return "downloaded";
}

/** Saves the whole-app backup — see saveJsonFile above. */
export function saveBackupFile(data: BackupData): Promise<"saved" | "cancelled" | "downloaded"> {
  return saveJsonFile(data, backupFilename(), "Peragra backup");
}

/** Saves a single board's export — see saveJsonFile above and
 *  useStore's importBoardData for the receiving end. */
export function saveBoardFile(data: BackupData, tripName: string): Promise<"saved" | "cancelled" | "downloaded"> {
  return saveJsonFile(data, boardBackupFilename(tripName), "Peragra board");
}
