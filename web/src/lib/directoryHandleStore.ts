/**
 * Persists a single FileSystemDirectoryHandle (the folder the person
 * picked for automatic backups) across page reloads. A handle can't go in
 * localStorage — it isn't JSON-serializable — but it IS structured-clone
 * serializable, which IndexedDB supports directly, so this is a tiny
 * dedicated IndexedDB store just for the one value rather than a real
 * dependency.
 */
const DB_NAME = "peragra-file-handles";
const STORE_NAME = "handles";
const KEY = "auto-backup-dir";

function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore(STORE_NAME);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("Failed to open IndexedDB"));
  });
}

export async function saveBackupDirectoryHandle(handle: FileSystemDirectoryHandle): Promise<void> {
  const db = await openDB();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, "readwrite");
    tx.objectStore(STORE_NAME).put(handle, KEY);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error ?? new Error("Failed to save directory handle"));
  });
  db.close();
}

export async function loadBackupDirectoryHandle(): Promise<FileSystemDirectoryHandle | null> {
  const db = await openDB();
  const handle = await new Promise<FileSystemDirectoryHandle | null>((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, "readonly");
    const request = tx.objectStore(STORE_NAME).get(KEY);
    request.onsuccess = () => resolve((request.result as FileSystemDirectoryHandle | undefined) ?? null);
    request.onerror = () => reject(request.error ?? new Error("Failed to load directory handle"));
  });
  db.close();
  return handle;
}

export async function clearBackupDirectoryHandle(): Promise<void> {
  const db = await openDB();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, "readwrite");
    tx.objectStore(STORE_NAME).delete(KEY);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error ?? new Error("Failed to clear directory handle"));
  });
  db.close();
}
