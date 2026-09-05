import { backupFilename, buildBackup, type BackupData } from "./backup";
import { clearBackupDirectoryHandle, loadBackupDirectoryHandle, saveBackupDirectoryHandle } from "./directoryHandleStore";
import { useBackupSettingsStore } from "../store/useBackupSettingsStore";

/** Whether this browser supports the File System Access API this all depends on. */
export function isAutoBackupSupported(): boolean {
  return typeof window.showDirectoryPicker === "function";
}

/**
 * Lets the person pick a folder for automatic backups, and remembers it
 * (the handle in IndexedDB, its display name in Settings) — read-write
 * permission is requested as part of the same picker call, since it
 * needs a user gesture and this button click is one.
 */
export async function chooseAutoBackupFolder(): Promise<string | null> {
  if (!window.showDirectoryPicker) return null;
  let handle: FileSystemDirectoryHandle;
  try {
    handle = await window.showDirectoryPicker({ mode: "readwrite" });
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") return null;
    throw err;
  }
  await saveBackupDirectoryHandle(handle);
  const { setBackupFolderName, setNeedsReauthorization } = useBackupSettingsStore.getState();
  setBackupFolderName(handle.name);
  setNeedsReauthorization(false);
  return handle.name;
}

export async function forgetAutoBackupFolder(): Promise<void> {
  await clearBackupDirectoryHandle();
  const { setBackupFolderName, setAutoBackupEnabled, setNeedsReauthorization } = useBackupSettingsStore.getState();
  setBackupFolderName(null);
  setAutoBackupEnabled(false);
  setNeedsReauthorization(false);
}

async function writeBackupToFolder(handle: FileSystemDirectoryHandle, data: BackupData): Promise<void> {
  const json = JSON.stringify(data, null, 2);
  const fileHandle = await handle.getFileHandle(backupFilename(new Date(data.exportedAt)), { create: true });
  const writable = await fileHandle.createWritable();
  await writable.write(json);
  await writable.close();
}

/**
 * Re-grants write access to the previously chosen folder — Chromium
 * drops a handle's permission across some browser restarts, and
 * re-requesting it needs a user gesture (this button click), so silent
 * background code can't recover from that on its own.
 */
export async function reauthorizeBackupFolder(): Promise<boolean> {
  const handle = await loadBackupDirectoryHandle();
  if (!handle) return false;
  const permission = await handle.requestPermission({ mode: "readwrite" });
  const granted = permission === "granted";
  useBackupSettingsStore.getState().setNeedsReauthorization(!granted);
  return granted;
}

/** Writes a backup to the chosen folder right now, regardless of the schedule — used by a manual "Back up now" action. */
export async function runAutoBackupNow(trips: BackupData["trips"], places: BackupData["places"], collections: BackupData["collections"]): Promise<"saved" | "no-folder" | "needs-permission"> {
  const handle = await loadBackupDirectoryHandle();
  if (!handle) return "no-folder";

  const permission = await handle.queryPermission({ mode: "readwrite" });
  if (permission !== "granted") {
    useBackupSettingsStore.getState().setNeedsReauthorization(true);
    return "needs-permission";
  }

  await writeBackupToFolder(handle, buildBackup(trips, places, collections));
  const { setLastAutoBackupAt, setNeedsReauthorization } = useBackupSettingsStore.getState();
  setLastAutoBackupAt(Date.now());
  setNeedsReauthorization(false);
  return "saved";
}

/**
 * Called once when the app opens — writes a fresh backup to the chosen
 * folder if automatic backups are on and the configured interval has
 * elapsed since the last one. There's no way to run this while the app
 * itself isn't open (a plain web page has no background execution), so
 * "regular" here means "checked every time the app is opened, and caught
 * up if overdue" rather than a true background schedule.
 */
export async function runAutoBackupIfDue(
  trips: BackupData["trips"],
  places: BackupData["places"],
  collections: BackupData["collections"],
): Promise<void> {
  const { autoBackupEnabled, autoBackupIntervalDays, lastAutoBackupAt } = useBackupSettingsStore.getState();
  if (!autoBackupEnabled) return;

  const intervalMs = autoBackupIntervalDays * 24 * 60 * 60 * 1000;
  if (lastAutoBackupAt !== null && Date.now() - lastAutoBackupAt < intervalMs) return;

  try {
    await runAutoBackupNow(trips, places, collections);
  } catch (error) {
    console.warn("Automatic backup failed:", error);
  }
}
