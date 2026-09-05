// TypeScript's bundled DOM lib already types FileSystemDirectoryHandle,
// FileSystemFileHandle, and FileSystemWritableFileStream (the File System
// Access API's core shapes) — just not the still-non-standard bits this
// app needs on top: the showDirectoryPicker() entry point, and the
// permission-query/request methods every handle actually has in
// Chromium (used to check whether a persisted directory handle can still
// be written to across sessions without re-prompting).
export {};

declare global {
  type FileSystemPermissionMode = "read" | "readwrite";

  interface FileSystemHandlePermissionDescriptor {
    mode?: FileSystemPermissionMode;
  }

  interface FileSystemHandle {
    queryPermission(descriptor?: FileSystemHandlePermissionDescriptor): Promise<PermissionState>;
    requestPermission(descriptor?: FileSystemHandlePermissionDescriptor): Promise<PermissionState>;
  }

  interface DirectoryPickerOptions {
    id?: string;
    mode?: FileSystemPermissionMode;
    startIn?: FileSystemHandle | string;
  }

  interface Window {
    showDirectoryPicker?: (options?: DirectoryPickerOptions) => Promise<FileSystemDirectoryHandle>;
  }
}
