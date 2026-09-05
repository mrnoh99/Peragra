import { create } from "zustand";
import { persist } from "zustand/middleware";

export type AutoBackupInterval = 1 | 7;

interface BackupSettingsState {
  autoBackupEnabled: boolean;
  autoBackupIntervalDays: AutoBackupInterval;
  // Display name only — the actual FileSystemDirectoryHandle isn't
  // JSON-serializable, so it's kept separately in IndexedDB
  // (lib/directoryHandleStore.ts). This is just what Settings shows.
  backupFolderName: string | null;
  lastAutoBackupAt: number | null;
  // Set when a scheduled backup couldn't write because the browser
  // dropped write permission on the folder (happens across browser
  // restarts in some Chromium versions) — surfaced in Settings so the
  // person knows to re-grant it with one click, since silently
  // re-requesting permission needs a user gesture.
  needsReauthorization: boolean;
  setAutoBackupEnabled: (enabled: boolean) => void;
  setAutoBackupIntervalDays: (days: AutoBackupInterval) => void;
  setBackupFolderName: (name: string | null) => void;
  setLastAutoBackupAt: (timestamp: number | null) => void;
  setNeedsReauthorization: (needs: boolean) => void;
}

export const useBackupSettingsStore = create<BackupSettingsState>()(
  persist(
    (set) => ({
      autoBackupEnabled: false,
      autoBackupIntervalDays: 1,
      backupFolderName: null,
      lastAutoBackupAt: null,
      needsReauthorization: false,
      setAutoBackupEnabled: (enabled) => set({ autoBackupEnabled: enabled }),
      setAutoBackupIntervalDays: (days) => set({ autoBackupIntervalDays: days }),
      setBackupFolderName: (name) => set({ backupFolderName: name }),
      setLastAutoBackupAt: (timestamp) => set({ lastAutoBackupAt: timestamp }),
      setNeedsReauthorization: (needs) => set({ needsReauthorization: needs }),
    }),
    { name: "peragra-backup-settings" },
  ),
);
