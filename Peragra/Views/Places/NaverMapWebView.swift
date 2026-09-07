import SwiftUI
import WebKit
import UIKit

/// Renders saved places on a Naver Map, for people who've opted into
/// Naver Maps in Settings with their own NCP Client ID. Unlike
/// GoogleMapWebView (which embeds a self-contained HTML string via
/// loadHTMLString), this navigates the WKWebView to a real page —
/// web/public/naver-map-embed.html, deployed at
/// https://mrnoh99.github.io/Peragra/naver-map-embed.html — because
/// Naver's tile-serving endpoints validate the calling page's actual
/// origin, and loadHTMLString(_:baseURL:) only fakes that origin for
/// resolving relative URLs: the map script and object initialized fine
/// against a faked one, but every tile request failed silently
/// ("Failure to load tile meta information"). This is the same origin
/// NaverMapView.tsx (the web app's own Naver map component) already
/// uses successfully, and the same one registered as this Client ID's
/// Web Service URL in the NCP console.
struct NaverMapWebView: UIViewRepresentable {
    struct MarkerPlace: Encodable, Equatable {
        let id: String
        let name: String
        let address: String
        let emoji: String
        let visited: Bool
        /// Only true when this app's own geocoding actually resolved
        /// `address` (`.located`) — an `.estimated` pin's address hasn't
        /// necessarily proven resolvable, so its "Open in Google Maps"
        /// link falls back to name + trip destination too.
        let addressTrusted: Bool
        let latitude: Double
        let longitude: Double
        /// Precomputed here (rather than in the JS below) since building
        /// these needs KoreaRegion/KakaoMapOpener/NaverMapOpener/TmapOpener,
        /// which only exist on the Swift side — nil when that service isn't
        /// available for this place (outside Korea, say).
        let kakaoMapUrlString: String?
        let naverMapUrlString: String?
        let tmapUrlString: String?
    }

    let clientId: String
    let places: [MarkerPlace]
    /// The trip's destination city — used as a fallback qualifier for a
    /// marker's "Open in Google Maps" link when that place has no address.
    let tripDestination: String
    /// Called with a place's id (its MarkerPlace.id) when a marker's
    /// "View Place Card" button is tapped, via a JS -> Swift message
    /// handler — switches to the Listing tab and scrolls to it.
    let onSelectPlace: (String) -> Void

    private static let embedURL = URL(string: "https://mrnoh99.github.io/Peragra/naver-map-embed.html")!

    private struct Payload: Encodable {
        let clientId: String
        let tripDestination: String
        let places: [MarkerPlace]
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: "selectPlace")
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSelectPlace = onSelectPlace
        // Same reload-only-when-changed guard as GoogleMapWebView — this
        // runs on every re-render of whatever contains the map, not just
        // when its own inputs change, so reloading unconditionally would
        // flash the map and lose the person's pan/zoom on every unrelated
        // update (a favorite toggled elsewhere, a filter changed, ...).
        let signature = Signature(clientId: clientId, places: places, tripDestination: tripDestination)
        guard context.coordinator.loadedSignature != signature else { return }
        context.coordinator.loadedSignature = signature
        let payload = Payload(clientId: clientId, tripDestination: tripDestination, places: places)
        context.coordinator.pendingPayloadJSON = Self.jsonString(for: payload)
        webView.load(URLRequest(url: Self.embedURL))
    }

    fileprivate struct Signature: Equatable {
        let clientId: String
        let places: [MarkerPlace]
        let tripDestination: String
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static func jsonString(for payload: Payload) -> String? {
        guard let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json.replacingOccurrences(of: "</", with: "<\\/")
    }

    /// Sends taps on an "Open in ... Map" link out to the system instead
    /// of navigating inside this WebView, which would just replace the
    /// map with a bare page and leave no way back. Also relays a marker's
    /// "View Place Card" button (a JS -> Swift message, since a WKWebView
    /// can't call back into SwiftUI any other way) to onSelectPlace, and
    /// injects the place data into the embed page once it finishes
    /// loading (window.renderNaverMap — see naver-map-embed.html).
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        fileprivate var loadedSignature: Signature?
        fileprivate var onSelectPlace: ((String) -> Void)?
        fileprivate var pendingPayloadJSON: String?
        private var contentProcessCrashCount = 0

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "selectPlace", let placeID = message.body as? String else { return }
            onSelectPlace?(placeID)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let json = pendingPayloadJSON else { return }
            webView.evaluateJavaScript("window.renderNaverMap(\(json));")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportLoadFailure(error, on: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportLoadFailure(error, on: webView)
        }

        // The embed page itself failed to reach (offline, GitHub Pages
        // unreachable, ...) — none of its own JS ran, so the message is
        // built natively rather than via evaluateJavaScript against a
        // page that never loaded.
        private func reportLoadFailure(_ error: Error, on webView: WKWebView) {
            webView.loadHTMLString(
                """
                <body style="display:flex;align-items:center;justify-content:center;height:100%;margin:0;padding:24px;text-align:center;font:14px -apple-system,sans-serif;color:#a3a3a3;">Couldn't reach the Naver Map page — check your internet connection.</body>
                """,
                baseURL: nil
            )
        }

        // A one-off content-process kill (memory pressure, say) recovers
        // with a reload — didFinish fires again and re-injects the last
        // payload — past that, leave it rather than risk a silent loop
        // against something genuinely crashing the process.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            contentProcessCrashCount += 1
            guard contentProcessCrashCount <= 1 else { return }
            webView.reload()
        }
    }
}
