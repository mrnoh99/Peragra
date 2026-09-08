import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// The Share Extension's entry point — what actually runs when someone
/// taps the Peragra icon in another app's share sheet ("Share" on a place
/// in Google Maps, Naver Map, Kakao Map, or any other app, in the case
/// this exists for). Accepts any shared content (see the extension's
/// TRUEPREDICATE activation rule in Info.plist) rather than trying to
/// recognize a specific map app's URL scheme, so it isn't tied to one
/// provider. Reads whatever the sharing app provided, stashes it via
/// SharedPlaceImportStore for the main app to pick up (an extension has
/// no SwiftData access of its own), then hands off to the main app by
/// opening its "peragra://share-import" URL — mirroring the web app's PWA
/// share_target handler.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let hosting = UIHostingController(rootView: ShareRootView(onCancel: { [weak self] in
            self?.finish()
        }))
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        Task { await handleSharedItem() }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func handleSharedItem() async {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachments = item.attachments
        else {
            finish()
            return
        }

        var sharedURL: String?
        var sharedText: String?

        for provider in attachments {
            if sharedURL == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let url = await loadItem(provider, typeIdentifier: UTType.url.identifier) as? URL {
                    sharedURL = url.absoluteString
                }
            }
            if sharedText == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = await loadItem(provider, typeIdentifier: UTType.plainText.identifier) as? String {
                    sharedText = text
                }
            }
        }

        let title = item.attributedContentText?.string

        guard let candidate = SharedPlaceImportStore.parse(title: title, text: sharedText, url: sharedURL) else {
            finish()
            return
        }

        SharedPlaceImportStore.setPending(candidate)

        if let openURL = URL(string: "peragra://share-import") {
            await open(openURL)
        }

        finish()
    }

    private func loadItem(_ provider: NSItemProvider, typeIdentifier: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }

    /// Waits for the OS to actually act on the request before returning
    /// — calling finish() (completeRequest, which tears this extension's
    /// context down) right after firing open() without waiting for its
    /// own completion handler is a well-known way for the app-switch to
    /// silently never happen: completeRequest can invalidate the
    /// extension context before the OS has had a chance to process the
    /// pending open() request, so the whole hand-off just gets dropped —
    /// the extension's own small screen flickers and dismisses, but the
    /// main app never actually comes to the foreground. Passing nil as
    /// completionHandler (the previous version of this code) meant
    /// finish() ran on literally the next line, immediately, every time.
    private func open(_ url: URL) async {
        await withCheckedContinuation { continuation in
            extensionContext?.open(url) { _ in
                continuation.resume()
            }
        }
    }
}

private struct ShareRootView: View {
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 40))
                .foregroundStyle(Color(red: 0.98, green: 0.33, blue: 0.17))
            Text("Saving to Peragra")
                .font(.headline)
            Text("Open Peragra to finish adding this place to your \u{201C}From Map\u{201D} board.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            ProgressView()
                .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Button("Cancel", action: onCancel)
                .padding()
        }
    }
}
