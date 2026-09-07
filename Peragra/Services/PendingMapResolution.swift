import Foundation

extension Notification.Name {
    /// Posted (by TripsListView.onOpenURL) once a share coming back from
    /// a native map app has been matched to a PendingMapResolution
    /// target and resolved — carries "rowID" (UUID) and "shared"
    /// (SharedPlaceImport) in its userInfo. AddPlaceSheet listens for
    /// this to fill in the matching row while it's still on screen.
    static let peragraMapResolutionReceived = Notification.Name("peragraMapResolutionReceived")
}

/// Tracks a single Add Places row that's waiting on the person to
/// identify it by visiting a native map app and sharing the result back
/// — set right before AddPlaceSheet opens that map app (its "Open in Map
/// to Identify" option, offered for an on-site-photo row whose GPS fix
/// resolved but whose name didn't), and consumed by TripsListView's
/// onOpenURL handler when a share comes back, instead of routing to the
/// "From Map" board the way an out-of-context share does.
///
/// In-memory only, main-app-process-local — unlike SharedPlaceImportStore,
/// ShareExtension itself never needs to read or write this, so it has no
/// need for the App Group's cross-process storage. The row identity this
/// tracks (a CandidateRow's id, which only exists for as long as its
/// AddPlaceSheet instance is alive — these rows are never persisted)
/// only means anything while the app stayed backgrounded, not
/// terminated, the whole time the map app was in front — which is
/// exactly the condition under which in-memory-only state survives
/// anyway. If the app was killed in between, this is simply empty when
/// checked again, and the share falls back to the ordinary "From Map"
/// landing instead of silently going nowhere.
enum PendingMapResolution {
    struct Target {
        let rowID: UUID
    }

    private static var current: Target?

    static func set(rowID: UUID) {
        current = Target(rowID: rowID)
    }

    /// Reads and clears in one step.
    static func take() -> Target? {
        defer { current = nil }
        return current
    }
}
