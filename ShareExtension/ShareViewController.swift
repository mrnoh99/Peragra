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
    private let state = ShareState()

    override func viewDidLoad() {
        super.viewDidLoad()

        let hosting = UIHostingController(rootView: ShareRootView(
            state: state,
            onCancel: { [weak self] in self?.finish() },
            onOpenPeragra: { [weak self] in self?.openPeragraThenFinish() }
        ))
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
            state.message = "Nothing shareable found."
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
            state.message = "Nothing shareable found."
            return
        }

        SharedPlaceImportStore.setPending(candidate)

        // Try automatically first — this works on plenty of
        // devices/iOS versions, and when it does, this extension's
        // whole screen just disappears as the OS switches to Peragra,
        // so nothing below (readyToOpen, the button) ever becomes
        // visible. When it doesn't — a real, reproducing case on some
        // devices, where extensionContext.open()'s completion handler
        // fires but the actual app switch silently never happens — the
        // save itself already succeeded (setPending, above), so this
        // stops short of calling finish() and instead shows a manual
        // "Open Peragra" button as a guaranteed fallback, rather than
        // the extension quietly completing with nothing having actually
        // gotten the person back to their data.
        await openPeragra()
        state.readyToOpen = true
    }

    /// A confirmed, on-device fact rather than a guess: open()'s own
    /// completion handler reports `false` on at least one real device —
    /// the OS is explicitly declining the request, not losing a race.
    /// No further attempt here tries to out-guess that; TripsListView's
    /// own checkForPendingShare() is the real fallback now, checking for
    /// a pending share every time the app comes to the foreground by any
    /// means at all, including just tapping the Home Screen icon by
    /// hand — since the save itself (setPending, already done by the
    /// time this button is visible) never depended on this call
    /// succeeding to begin with. This still tries the automatic open()
    /// as a harmless bonus (works on other devices), then dismisses the
    /// extension either way.
    private func openPeragraThenFinish() {
        guard let openURL = URL(string: "peragra://share-import") else {
            finish()
            return
        }
        extensionContext?.open(openURL) { [weak self] _ in
            self?.finish()
        }
    }

    private func openPeragra() async {
        guard let openURL = URL(string: "peragra://share-import") else { return }
        await withCheckedContinuation { continuation in
            extensionContext?.open(openURL) { _ in
                continuation.resume()
            }
        }
    }

    private func loadItem(_ provider: NSItemProvider, typeIdentifier: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }
}

private final class ShareState: ObservableObject {
    @Published var readyToOpen = false
    @Published var message: String?
}

private struct ShareRootView: View {
    @ObservedObject var state: ShareState
    var onCancel: () -> Void
    var onOpenPeragra: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: state.readyToOpen ? "checkmark.circle.fill" : "mappin.and.ellipse")
                .font(.system(size: 40))
                .foregroundStyle(Color(red: 0.98, green: 0.33, blue: 0.17))
            Text(state.readyToOpen ? "Saved" : "Saving to Peragra")
                .font(.headline)
            if let message = state.message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else if state.readyToOpen {
                Text("Saved. Tap below, or open Peragra from your Home Screen \u{2014} either way it\u{2019}ll be waiting in your \u{201C}From Map\u{201D} board.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Open Peragra", action: onOpenPeragra)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            } else {
                Text("Open Peragra to finish adding this place to your \u{201C}From Map\u{201D} board.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                ProgressView()
                    .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Button("Cancel", action: onCancel)
                .padding()
        }
    }
}
