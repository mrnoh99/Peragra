import Foundation

/// A place candidate captured by ShareExtension (see
/// ShareExtension/ShareViewController.swift) from the OS share sheet —
/// "Share" on a place in Google Maps, Naver Map, Kakao Map, or any other
/// app — and handed off to the main app. Shared by both targets (this
/// file is added to ShareExtension's build target too), since an
/// extension and its host app run as separate processes with no shared
/// memory of their own.
struct SharedPlaceImport: Codable {
    var name: String
    // Naver Map's own "Share" gives name, address, and a link as three
    // separate pieces (unlike Google Maps'/Kakao Map's, which give only
    // a link) — captured when present, left empty otherwise rather than
    // guessed at.
    var address: String
    var link: String
    // Set only by TripsListView's cold-relaunch round-trip fallback (see
    // PendingMapResolution) — the original on-site photo's own GPS fix,
    // merged back in after this candidate has already been restashed by
    // ShareExtension, so the reviewed row keeps its precise coordinate
    // instead of relying on a geocode of whatever name the map app gave
    // back. nil for every ordinary share (ShareExtension itself never
    // sets these — ordinary imports have no GPS fix of their own to
    // restore).
    var latitude: Double?
    var longitude: Double?
    // Whatever raw title/text the share sheet handed the extension,
    // untouched by parse()'s own name/address guesswork — surfaced into
    // the reviewed row's own Notes field (see AddPlaceSheet.init) so a
    // share that doesn't parse into a sensible name is still visible
    // and reviewable on-device, rather than only diagnosable by reading
    // a console log off the person's computer. Empty whenever there was
    // nothing beyond a bare link to begin with.
    var rawSource: String = ""
}

enum SharedPlaceImportStore {
    // Must exactly match the App Group entitlement both Peragra and
    // ShareExtension declare.
    private static let appGroupID = "group.com.peragra.app"
    private static let storageKey = "pendingSharedPlaceImport"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func setPending(_ candidate: SharedPlaceImport) {
        guard let data = try? JSONEncoder().encode(candidate) else { return }
        sharedDefaults?.set(data, forKey: storageKey)
        // ShareExtension calls this right before its own process
        // terminates (see ShareViewController.finish()) — synchronize()
        // is officially unnecessary on modern iOS (writes are supposed
        // to flush on their own), but in practice a write from a
        // short-lived extension process racing its own termination
        // against the main app's read (launched by the very next line,
        // extensionContext?.open) is exactly the case that benefits from
        // forcing an immediate flush instead of trusting the OS's normal
        // background timer to win that race.
        sharedDefaults?.synchronize()
    }

    /// Reads and clears in one step — meant to be read exactly once, by
    /// the main app right after it opens the "peragra://share-import" URL
    /// the extension hands off with (see TripDetailView.onAppear). Retries
    /// briefly rather than giving up on the first empty read: even with
    /// setPending's own synchronize(), the write still has to propagate
    /// from the extension's process to this one via cfprefsd, which isn't
    /// instantaneous — and this is called right as the main app is being
    /// freshly launched/foregrounded by that same extension, the least
    /// forgiving timing for that propagation to have already finished.
    static func takePending() async -> SharedPlaceImport? {
        for attempt in 0..<5 {
            if let data = sharedDefaults?.data(forKey: storageKey) {
                sharedDefaults?.removeObject(forKey: storageKey)
                return try? JSONDecoder().decode(SharedPlaceImport.self, from: data)
            }
            if attempt < 4 {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        return nil
    }

    /// Turns whatever the OS share sheet handed the extension into a
    /// place candidate. Not tied to any one map app in code — any app's
    /// "Share" action that provides a URL or text lands here the same
    /// way, whether that's Google Maps, Naver Map, Kakao Map, or
    /// anything else — which is what the "From Map" board (see
    /// TripsListView.sharedPlacesBoard) is named for. Mirrors the web
    /// equivalent, lib/sharedPlaceImport.ts, including its rationale for
    /// not resolving the link itself into coordinates (the name gets
    /// geocoded normally; the link is kept as a reference).
    static func parse(title: String?, text: String?, url: String?) -> SharedPlaceImport? {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty || !text.isEmpty || !url.isEmpty else { return nil }

        // Naver Map's share text is "Place Name\nAddress\n<link>" — no
        // separate title field. Some other apps instead give the name as
        // its own title, with text holding just a description/address
        // line. Either way, whichever non-URL line(s) of `text` weren't
        // already claimed as the name is the closest thing to an address
        // this format offers.
        let lines = nonURLLines(in: text)
        let name = title.isEmpty ? (lines.first ?? "") : title
        let address = title.isEmpty ? (lines.count > 1 ? lines[1] : "") : (lines.first ?? "")

        let rawParts = ["title: \(title)", "text: \(text)"].filter { !$0.hasSuffix(": ") }
        let rawSource = rawParts.isEmpty ? "" : "Shared as — " + rawParts.joined(separator: " | ")

        return SharedPlaceImport(
            name: name,
            address: address,
            link: url.isEmpty ? extractURL(from: text) : url,
            rawSource: rawSource
        )
    }

    private static func extractURL(from text: String) -> String {
        guard let range = text.range(of: #"https?://\S+"#, options: .regularExpression) else { return "" }
        return String(text[range])
    }

    private static func nonURLLines(in text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.range(of: #"https?://\S+"#, options: .regularExpression) == nil }
    }
}
