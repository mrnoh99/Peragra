import Foundation
import SwiftData

/// Automatically keeps a snapshot of the whole app's data in this app's
/// own iCloud container — distinct from AutoBackupService's user-picked
/// Files folder, whose security-scoped bookmark lives in UserDefaults and
/// is wiped along with everything else when the app is deleted. This
/// snapshot survives a delete + reinstall, since finding it again only
/// needs the iCloud entitlement and the person's iCloud account, not any
/// state this app itself stored on the device.
///
/// Requires the "iCloud Documents" capability enabled in Xcode's Signing
/// & Capabilities (with a real Apple Developer team) so the container id
/// in Peragra.entitlements is actually provisioned — without that, every
/// call here is a silent no-op (FileManager returns nil for the
/// container URL), which is also exactly what happens on a simulator/
/// device with no iCloud account signed in.
enum CloudBackupService {
    private static let filename = "peragra_auto_backup.json"

    private static var containerDocumentsURL: URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }

    private static var backupFileURL: URL? {
        containerDocumentsURL?.appendingPathComponent(filename)
    }

    /// Writes the current data to iCloud, overwriting any previous
    /// snapshot. Cheap and safe to call often (app launch, foreground,
    /// background) — it's a plain file write, not a network round trip;
    /// iOS itself handles actually syncing the file to iCloud afterward.
    static func backup(context: ModelContext) {
        guard let fileURL = backupFileURL, let data = try? BackupService.exportData(context: context) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// True only when the iCloud snapshot exists and actually contains at
    /// least one trip — an empty or unwritten snapshot isn't worth
    /// restoring over a legitimately empty fresh install.
    static func hasRestorableBackup() -> Bool {
        guard let fileURL = backupFileURL, let data = try? Data(contentsOf: fileURL) else { return false }
        guard let decoded = try? JSONDecoder().decode(BackupService.BackupData.self, from: data) else { return false }
        return !decoded.trips.isEmpty
    }

    /// Restores from the iCloud snapshot into `context`. Only meant to be
    /// called when the local store is empty (see TripsListView's launch
    /// check) — restore's own "replace everything" semantics would
    /// otherwise clobber data the person already has on this device.
    @discardableResult
    static func restoreIfAvailable(context: ModelContext) -> Bool {
        guard let fileURL = backupFileURL, let data = try? Data(contentsOf: fileURL) else { return false }
        return (try? BackupService.restore(from: data, context: context)) != nil
    }
}
