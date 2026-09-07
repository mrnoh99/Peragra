import Foundation

/// A place candidate captured by ShareExtension (see
/// ShareExtension/ShareViewController.swift) from the OS share sheet —
/// typically triggered by "Share" on a place in the Google Maps app — and
/// handed off to the main app. Shared by both targets (this file is added
/// to ShareExtension's build target too), since an extension and its host
/// app run as separate processes with no shared memory of their own.
struct SharedPlaceImport: Codable {
    var name: String
    var link: String
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
    }

    /// Reads and clears in one step — meant to be read exactly once, by
    /// the main app right after it opens the "peragra://share-import" URL
    /// the extension hands off with (see TripDetailView.onAppear).
    static func takePending() -> SharedPlaceImport? {
        guard let data = sharedDefaults?.data(forKey: storageKey) else { return nil }
        sharedDefaults?.removeObject(forKey: storageKey)
        return try? JSONDecoder().decode(SharedPlaceImport.self, from: data)
    }

    /// Turns whatever the OS share sheet handed the extension into a
    /// place candidate. Not Google-specific in code — any app's "Share"
    /// action that provides a URL or text lands here the same way — but
    /// in practice this is overwhelmingly triggered by "Share" on a place
    /// in the Google Maps app, which is what the "From Google" board (see
    /// TripsListView.sharedPlacesBoard) is named for. Mirrors the web
    /// equivalent, lib/sharedPlaceImport.ts, including its rationale for
    /// not resolving the link itself into coordinates (the name gets
    /// geocoded normally; the link is kept as a reference).
    static func parse(title: String?, text: String?, url: String?) -> SharedPlaceImport? {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty || !text.isEmpty || !url.isEmpty else { return nil }

        return SharedPlaceImport(
            name: title.isEmpty ? nameFromText(text) : title,
            link: url.isEmpty ? extractURL(from: text) : url
        )
    }

    private static func extractURL(from text: String) -> String {
        guard let range = text.range(of: #"https?://\S+"#, options: .regularExpression) else { return "" }
        return String(text[range])
    }

    private static func nameFromText(_ text: String) -> String {
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return firstLine.range(of: #"https?://\S+"#, options: .regularExpression) != nil ? "" : firstLine
    }
}
