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

export function backupFilename(date = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  const stamp = `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
  return `peragra_${stamp}.json`;
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
 * Saves the backup to a location the person picks, via the File System
 * Access API where the browser supports it (Chrome/Edge); falls back to
 * a plain download (the browser's default downloads location) elsewhere
 * — notably Safari, which has no such picker.
 */
export async function saveBackupFile(data: BackupData): Promise<"saved" | "cancelled" | "downloaded"> {
  const json = JSON.stringify(data, null, 2);
  const filename = backupFilename();

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
        types: [{ description: "Peragra backup", accept: { "application/json": [".json"] } }],
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
