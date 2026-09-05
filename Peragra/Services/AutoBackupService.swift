import Foundation
import SwiftData

/// Writes a backup file to a folder the person picked once in Settings —
/// "regular" here means "checked whenever the app comes to the
/// foreground, and caught up if overdue" rather than a true background
/// schedule, since iOS gives a plain app (no special background-refresh
/// entitlement wired up here) no reliable way to run code while it isn't
/// open. Mirrors web's lib/autoBackup.ts.
enum AutoBackupService {
    /// Resolves the stored security-scoped bookmark to a URL, refreshing
    /// the bookmark if it's gone stale (the folder was renamed/moved but
    /// is still reachable) — returns nil, and flags
    /// BackupFolderSettings.needsReauthorization, if it can't be resolved
    /// at all (folder deleted, or access was revoked).
    private static func resolveFolderURL() -> URL? {
        guard let bookmark = BackupFolderSettings.shared.folderBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            BackupFolderSettings.shared.setNeedsReauthorization(true)
            return nil
        }
        if isStale, let refreshed = try? url.bookmarkData() {
            BackupFolderSettings.shared.setFolder(bookmark: refreshed, displayName: url.lastPathComponent)
        }
        return url
    }

    /// Writes a backup to the chosen folder right now, regardless of the
    /// schedule — used by both the "Back up now" button and
    /// `runIfDue(context:)` once it's decided a scheduled backup is due.
    @discardableResult
    static func runNow(context: ModelContext) -> Bool {
        guard let folderURL = resolveFolderURL() else { return false }

        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }

        guard let data = try? BackupService.exportData(context: context) else { return false }
        let fileURL = folderURL.appendingPathComponent(BackupService.filename() + ".json")
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Most likely cause: the folder is no longer writable (access
            // was revoked outside the app, or it lives on a provider that
            // dropped the grant) — surfaced the same way a stale/missing
            // bookmark is, since either way the person needs to re-choose
            // the folder in Settings.
            BackupFolderSettings.shared.setNeedsReauthorization(true)
            return false
        }

        BackupFolderSettings.shared.setLastAutoBackupAt(.now)
        return true
    }

    /// Called once whenever the app becomes active — writes a fresh
    /// backup if automatic backups are on and the configured interval
    /// has elapsed since the last one.
    static func runIfDue(context: ModelContext) {
        let settings = BackupFolderSettings.shared
        guard settings.autoBackupEnabled else { return }

        let intervalSeconds = TimeInterval(settings.autoBackupIntervalDays) * 24 * 60 * 60
        if let lastAutoBackupAt = settings.lastAutoBackupAt, Date.now.timeIntervalSince(lastAutoBackupAt) < intervalSeconds {
            return
        }

        runNow(context: context)
    }
}
