import Foundation
import Observation

/// Reactive wrapper around the automatic-backup folder choice (a
/// security-scoped bookmark, since a plain URL stops being usable once
/// this app relaunches) and schedule preferences — all in UserDefaults,
/// none of it sensitive. Lets SwiftUI views (SettingsSheet) update
/// automatically when any of it changes.
@Observable
final class BackupFolderSettings {
    static let shared = BackupFolderSettings()

    private static let bookmarkDefaultsKey = "auto-backup-folder-bookmark"
    private static let folderNameDefaultsKey = "auto-backup-folder-name"
    private static let enabledDefaultsKey = "auto-backup-enabled"
    private static let intervalDaysDefaultsKey = "auto-backup-interval-days"
    private static let lastBackupDefaultsKey = "auto-backup-last-at"

    private(set) var folderBookmark: Data?
    private(set) var folderDisplayName: String?
    private(set) var autoBackupEnabled: Bool
    private(set) var autoBackupIntervalDays: Int
    private(set) var lastAutoBackupAt: Date?
    /// Set when resolving the stored bookmark fails (the folder was
    /// moved, deleted, or access was revoked) — surfaced in Settings so
    /// the person knows to re-choose it; can't be silently recovered
    /// from since choosing a folder needs a user gesture.
    private(set) var needsReauthorization = false

    private init() {
        folderBookmark = UserDefaults.standard.data(forKey: Self.bookmarkDefaultsKey)
        folderDisplayName = UserDefaults.standard.string(forKey: Self.folderNameDefaultsKey)
        autoBackupEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        let storedInterval = UserDefaults.standard.integer(forKey: Self.intervalDaysDefaultsKey)
        autoBackupIntervalDays = storedInterval > 0 ? storedInterval : 1
        let storedLastBackup = UserDefaults.standard.double(forKey: Self.lastBackupDefaultsKey)
        lastAutoBackupAt = storedLastBackup > 0 ? Date(timeIntervalSince1970: storedLastBackup) : nil
    }

    func setFolder(bookmark: Data, displayName: String) {
        folderBookmark = bookmark
        folderDisplayName = displayName
        needsReauthorization = false
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkDefaultsKey)
        UserDefaults.standard.set(displayName, forKey: Self.folderNameDefaultsKey)
    }

    func clearFolder() {
        folderBookmark = nil
        folderDisplayName = nil
        autoBackupEnabled = false
        needsReauthorization = false
        UserDefaults.standard.removeObject(forKey: Self.bookmarkDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.folderNameDefaultsKey)
        UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
    }

    func setAutoBackupEnabled(_ value: Bool) {
        autoBackupEnabled = value
        UserDefaults.standard.set(value, forKey: Self.enabledDefaultsKey)
    }

    func setAutoBackupIntervalDays(_ value: Int) {
        autoBackupIntervalDays = value
        UserDefaults.standard.set(value, forKey: Self.intervalDaysDefaultsKey)
    }

    func setLastAutoBackupAt(_ value: Date) {
        lastAutoBackupAt = value
        UserDefaults.standard.set(value.timeIntervalSince1970, forKey: Self.lastBackupDefaultsKey)
    }

    func setNeedsReauthorization(_ value: Bool) {
        needsReauthorization = value
    }
}
