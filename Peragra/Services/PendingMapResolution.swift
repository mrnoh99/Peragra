import CoreLocation
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
/// Kept two ways at once, because a real trip through a native map app
/// can end either way:
///
/// - An in-memory copy, checked first — cheap, and covers the common
///   case where the app just moved to the background and stayed there.
///   Once the process that set it is gone, so is this copy; there is no
///   way to tell "still running" from "already replaced by a fresh
///   launch" other than that.
/// - A UserDefaults-persisted copy, checked when the in-memory one is
///   gone — covers the real, fairly common case (reported directly:
///   Google Maps specifically, not Naver/Kakao) where visiting a large,
///   memory-hungry map app gives iOS a reason to actually terminate the
///   backgrounded Peragra process rather than just suspend it. The
///   CandidateRow this was tracking doesn't survive that (rows are
///   in-memory view state, never persisted), so this copy carries enough
///   to reconstruct the essentials instead — which trip it belonged to,
///   and the on-site photo's own coordinate — letting TripsListView open
///   a fresh Add Places entry on the right board with that coordinate
///   already attached, rather than losing the round-trip entirely to the
///   generic "From Map" landing.
enum PendingMapResolution {
    struct Target {
        let rowID: UUID
        let tripID: UUID
        let latitude: Double
        let longitude: Double
    }

    /// .warm means the process never restarted — the AddPlaceSheet
    /// instance that called set(...) may still be on screen, so the
    /// caller can try filling it in directly via notification. .cold
    /// means the in-memory copy is gone (the process was restarted while
    /// the map app was in front) — that AddPlaceSheet instance and its
    /// row are gone with it, so the caller needs to reconstruct a fresh
    /// one instead, using just what this carries (which trip, which
    /// coordinate).
    enum Resolution {
        case warm(Target)
        case cold(Target)
    }

    private static let defaultsKey = "pendingMapResolutionTarget"

    private static var memory: Target?

    static func set(rowID: UUID, tripID: UUID, coordinate: CLLocationCoordinate2D) {
        let target = Target(rowID: rowID, tripID: tripID, latitude: coordinate.latitude, longitude: coordinate.longitude)
        memory = target
        persist(target)
    }

    /// Reads and clears in one step — both the in-memory copy and the
    /// persisted one, so a stale persisted copy never gets read twice.
    static func take() -> Resolution? {
        defer {
            memory = nil
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
        if let memory { return .warm(memory) }
        guard let persisted = readPersisted() else { return nil }
        return .cold(persisted)
    }

    private static func persist(_ target: Target) {
        let payload: [String: Any] = [
            "rowID": target.rowID.uuidString,
            "tripID": target.tripID.uuidString,
            "latitude": target.latitude,
            "longitude": target.longitude,
        ]
        UserDefaults.standard.set(payload, forKey: defaultsKey)
    }

    private static func readPersisted() -> Target? {
        guard
            let payload = UserDefaults.standard.dictionary(forKey: defaultsKey),
            let rowIDString = payload["rowID"] as? String, let rowID = UUID(uuidString: rowIDString),
            let tripIDString = payload["tripID"] as? String, let tripID = UUID(uuidString: tripIDString),
            let latitude = payload["latitude"] as? Double,
            let longitude = payload["longitude"] as? Double
        else { return nil }
        return Target(rowID: rowID, tripID: tripID, latitude: latitude, longitude: longitude)
    }
}
