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

    /// `FileManager.url(forUbiquityContainerIdentifier:)` talks to the
    /// iCloud daemon and, per Apple's own docs, can block for a long time
    /// on its first call — calling it on the main thread was freezing the
    /// whole app (including unrelated UI like the "New Board" sheet) right
    /// at launch. Resolved once off the main actor and cached, since the
    /// container URL doesn't change while the app is running.
    private static var cachedContainerDocumentsURL: URL??

    @MainActor
    private static func resolveContainerDocumentsURL() async -> URL? {
        if let cached = cachedContainerDocumentsURL { return cached }
        let resolved = await Task.detached(priority: .utility) { () -> URL? in
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            return documents
        }.value
        cachedContainerDocumentsURL = resolved
        return resolved
    }

    /// Writes the current data to iCloud, overwriting any previous
    /// snapshot. Safe to call often (app launch, foreground, background) —
    /// exporting reads the model context on the caller's actor, then the
    /// actual file write happens off the main thread.
    ///
    /// @MainActor is required, not decorative: this function awaits
    /// resolveContainerDocumentsURL(), which hops off-actor via
    /// Task.detached — a plain nonisolated `async func` isn't guaranteed
    /// to resume back on the main actor after that, so the exportData(context:)
    /// call right after it could run concurrently with this same
    /// ModelContext being used from the UI (board creation, editing, ...)
    /// on the main actor. ModelContext isn't safe for that — it silently
    /// produced a save() that didn't throw but never actually persisted,
    /// which is exactly how "New Board" creation went missing. @MainActor
    /// here forces the continuation back onto the main actor, so this
    /// function's own context access is always properly serialized with
    /// the rest of the app's.
    @MainActor
    static func backup(context: ModelContext) async {
        guard let documentsURL = await resolveContainerDocumentsURL(),
              let data = try? BackupService.exportData(context: context) else { return }
        let fileURL = documentsURL.appendingPathComponent(filename)
        await Task.detached(priority: .utility) {
            try? data.write(to: fileURL, options: .atomic)
        }.value
    }

    /// True only when the iCloud snapshot exists and actually contains at
    /// least one trip — an empty or unwritten snapshot isn't worth
    /// restoring over a legitimately empty fresh install.
    @MainActor
    static func hasRestorableBackup() async -> Bool {
        guard let documentsURL = await resolveContainerDocumentsURL() else { return false }
        let fileURL = documentsURL.appendingPathComponent(filename)
        return await Task.detached(priority: .utility) { () -> Bool in
            guard let data = try? Data(contentsOf: fileURL) else { return false }
            guard let decoded = try? JSONDecoder().decode(BackupService.BackupData.self, from: data) else { return false }
            return !decoded.trips.isEmpty
        }.value
    }

    /// Restores from the iCloud snapshot into `context`. Only meant to be
    /// called when the local store is empty (see TripsListView's launch
    /// check) — restore's own "replace everything" semantics would
    /// otherwise clobber data the person already has on this device.
    ///
    /// @MainActor for the same reason as backup(context:) above — this
    /// also touches `context` (via BackupService.restore) after awaiting
    /// resolveContainerDocumentsURL(), which is not safe to do off the
    /// main actor.
    @discardableResult
    @MainActor
    static func restoreIfAvailable(context: ModelContext) async -> Bool {
        guard let documentsURL = await resolveContainerDocumentsURL() else { return false }
        let fileURL = documentsURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        return (try? BackupService.restore(from: data, context: context)) != nil
    }
}
