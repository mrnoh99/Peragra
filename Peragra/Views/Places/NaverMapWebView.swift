import SwiftUI
import WebKit
import UIKit

/// Renders saved places on a Naver Map, for people who've opted into
/// Naver Maps in Settings with their own NCP Client ID. Implemented as a
/// self-contained HTML page loaded into a WKWebView (same technique as
/// GoogleMapWebView) — mirrors web's NaverMapView.tsx, just as embedded
/// JS instead of a React component, since Naver has no SwiftUI-native map
/// view either. Rendering only needs the Client ID (unlike
/// NaverGeocodingService's REST API, which also needs the Client Secret
/// for request signing) — this is the JS Maps SDK, a separate product.
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
        // Naver's NCP console checks the calling page's own origin against
        // the "Web Service URL" registered for this Client ID — passing
        // Naver's own domain here (as originally written) made that check
        // compare Naver's domain against itself, which NCP correctly
        // refuses ("Naver Open API 인증에 실패하였습니다"). http://localhost
        // is NCP's documented value for a native app embedding the Web
        // Dynamic Map SDK in a WebView rather than serving it from a real
        // website — register that same value as this Client ID's Web
        // Service URL in the NCP console (Web Dynamic Map > 사용 API 관리 >
        // Web 서비스 URL) for this to authenticate.
        let html = Self.html(clientId: clientId, places: places, tripDestination: tripDestination)
        let baseURL = URL(string: "http://localhost")
        context.coordinator.lastLoadedHTML = html
        context.coordinator.lastLoadedBaseURL = baseURL
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    fileprivate struct Signature: Equatable {
        let clientId: String
        let places: [MarkerPlace]
        let tripDestination: String
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Sends taps on an "Open in ... Map" link out to the system instead
    /// of navigating inside this WebView, which would just replace the
    /// map with a bare page and leave no way back. Also relays a marker's
    /// "View Place Card" button (a JS -> Swift message, since a WKWebView
    /// can't call back into SwiftUI any other way) to onSelectPlace.
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        fileprivate var loadedSignature: Signature?
        fileprivate var onSelectPlace: ((String) -> Void)?
        /// Stashed on every load so a crashed content process can be
        /// recovered by reloading the exact same content, without needing
        /// to re-derive it from `NaverMapWebView`'s (struct, not held
        /// here) properties.
        fileprivate var lastLoadedHTML: String?
        fileprivate var lastLoadedBaseURL: URL?
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

        // Neither the 10s JS timeout nor window.onerror can catch a
        // failure at this level — if the navigation itself never commits
        // (blocked by ATS, a bad baseURL, ...), no JS ever runs, and the
        // page would otherwise sit blank forever with zero signal. Written
        // to not depend on our own page's JS having already run (document
        // may not exist yet), unlike the in-page showLoadError helper.
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportNativeFailure(error, on: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportNativeFailure(error, on: webView)
        }

        private func reportNativeFailure(_ error: Error, on webView: WKWebView) {
            let message = (error as NSError).localizedDescription
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: " ")
            let js = """
            (function() {
              var html = '<div style="display:flex;align-items:center;justify-content:center;height:100%;padding:24px;text-align:center;font:14px -apple-system,sans-serif;color:#a3a3a3;">Naver Map failed to load: \(message)</div>';
              if (document.body) { document.body.innerHTML = html; } else { document.open(); document.write(html); document.close(); }
            })();
            """
            webView.evaluateJavaScript(js)
        }

        // A blank WKWebView with no error from any other delegate method
        // (didFail, didFailProvisionalNavigation, window.onerror) usually
        // means the WebContent process itself was killed — WebKit fires
        // this instead, separately from every navigation-failure path,
        // and the page is left showing nothing until something explicitly
        // reloads it. One retry recovers a one-off kill (memory pressure,
        // say); past that, show a message instead of risking a silent
        // reload loop against a content genuinely crashing the process.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            contentProcessCrashCount += 1
            guard contentProcessCrashCount <= 1, let html = lastLoadedHTML else {
                let message = "'The Naver Map page crashed" + (contentProcessCrashCount > 1 ? " again" : "") + " — try switching maps in Settings and back.'"
                let js = """
                (function() {
                  var html = '<div style="display:flex;align-items:center;justify-content:center;height:100%;padding:24px;text-align:center;font:14px -apple-system,sans-serif;color:#a3a3a3;">' + \(message) + '</div>';
                  if (document.body) { document.body.innerHTML = html; } else { document.open(); document.write(html); document.close(); }
                })();
                """
                webView.evaluateJavaScript(js)
                return
            }
            webView.loadHTMLString(html, baseURL: lastLoadedBaseURL)
        }
    }

    private static func html(clientId: String, places: [MarkerPlace], tripDestination: String) -> String {
        let placesJSON: String
        if let data = try? JSONEncoder().encode(places), let json = String(data: data, encoding: .utf8) {
            placesJSON = json.replacingOccurrences(of: "</", with: "<\\/")
        } else {
            placesJSON = "[]"
        }
        let tripDestinationJSON: String
        if let data = try? JSONEncoder().encode(tripDestination), let json = String(data: data, encoding: .utf8) {
            tripDestinationJSON = json.replacingOccurrences(of: "</", with: "<\\/")
        } else {
            tripDestinationJSON = "\"\""
        }

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            html, body, #map { margin: 0; height: 100%; width: 100%; }
            /* TEMPORARY high-contrast diagnostic background — proves
               whether this page's own static markup paints at all,
               independent of whether Naver's SDK/tiles ever load. Revert
               once the real cause is found. */
            body { background: #ff2d55; }
          </style>
        </head>
        <body>
          <div id="map">
            <div style="display:flex;align-items:center;justify-content:center;height:100%;font:20px -apple-system,sans-serif;font-weight:700;color:#000;background:#ffeb3b;">DIAGNOSTIC: page loaded</div>
          </div>
          <!-- TEMPORARY: a live-updating status line that Naver's own
               Map constructor can't wipe (it only touches #map's own
               children), so we can see exactly how far JS execution
               gets even when the map itself renders blank. Remove once
               the real cause is found. -->
          <div id="status-overlay" style="position:fixed;top:0;left:0;right:0;z-index:9999;background:#000;color:#0f0;font:11px/1.4 monospace;padding:4px 8px;white-space:pre-wrap;">status: script tag inserted</div>
          <script>
            const places = \(placesJSON);
            const tripDestination = \(tripDestinationJSON);
            let mapReady = false;
            let tilesLoaded = false;

            function setStatus(text) {
              const el = document.getElementById("status-overlay");
              if (el) el.textContent = "status: " + text;
            }

            function showLoadError(message) {
              if (mapReady) return;
              document.getElementById("map").outerHTML =
                '<div style="display:flex;align-items:center;justify-content:center;' +
                'height:100%;padding:24px;text-align:center;font:14px -apple-system,sans-serif;' +
                'color:#a3a3a3;">' + message + '</div>';
            }

            // A bad/unregistered Client ID doesn't reject the script load
            // itself — Naver calls window.navermap_authFailure instead
            // (their documented hook) — so that's wired up alongside a
            // plain timeout for a genuine hang, same two-path handling
            // GoogleMapWebView uses for its own failure mode. window.onerror
            // catches everything else (a thrown exception inside initMap,
            // a parse error in a malformed response served in place of the
            // real script, ...) that would otherwise leave the page stuck
            // on the loading placeholder forever with no visible cause.
            setTimeout(() => showLoadError("Couldn\\'t load Naver Map — check your Client ID in Settings."), 10000);
            window.navermap_authFailure = function() {
              showLoadError("Naver Map rejected this Client ID — check it in Settings.");
            };
            window.onerror = function(message) {
              showLoadError("Naver Map error: " + message);
              return true;
            };

            function initMap() {
              mapReady = true;
              setStatus("initMap() called, creating map object...");
              const first = places[0];
              const map = new naver.maps.Map(document.getElementById("map"), {
                center: new naver.maps.LatLng(first ? first.latitude : 37.5665, first ? first.longitude : 126.978),
                zoom: 13,
              });
              setStatus("map object created, waiting for tiles...");
              naver.maps.Event.addListener(map, "tilesloaded", () => {
                tilesLoaded = true;
                setStatus("tiles loaded OK");
              });
              naver.maps.Event.addListener(map, "idle", () => {
                if (!tilesLoaded) setStatus("map idle fired (no tilesloaded yet)");
              });
              setTimeout(() => {
                if (!tilesLoaded) setStatus("map object created but tilesloaded never fired after 6s — tiles are failing to load silently");
              }, 6000);

              const bounds = new naver.maps.LatLngBounds();
              const infoWindow = new naver.maps.InfoWindow();

              places.forEach((place) => {
                const position = new naver.maps.LatLng(place.latitude, place.longitude);
                const marker = new naver.maps.Marker({
                  position,
                  map,
                  icon: {
                    content: '<div style="width:24px;height:24px;display:flex;align-items:center;justify-content:center;font-size:18px;line-height:1;opacity:' + (place.visited ? 0.5 : 1) + ';">' + place.emoji + '</div>',
                    size: new naver.maps.Size(24, 24),
                    anchor: new naver.maps.Point(12, 24),
                  },
                });
                naver.maps.Event.addListener(marker, "click", () => {
                  // Built as DOM nodes with textContent, not an HTML
                  // string, so a place name/address containing markup
                  // (pasted from an Instagram caption, say) can't inject
                  // into the page.
                  const content = document.createElement("div");
                  content.style.position = "relative";
                  content.style.padding = "4px 22px 4px 2px";
                  // Unlike Google's InfoWindow, Naver's has no built-in
                  // close (x) chrome at all when given custom content —
                  // it has to be added by hand.
                  const closeEl = document.createElement("button");
                  closeEl.type = "button";
                  closeEl.textContent = "\\u00d7";
                  closeEl.setAttribute("aria-label", "Close");
                  closeEl.style.position = "absolute";
                  closeEl.style.top = "0";
                  closeEl.style.right = "0";
                  closeEl.style.border = "none";
                  closeEl.style.background = "none";
                  closeEl.style.padding = "2px 6px";
                  closeEl.style.fontSize = "16px";
                  closeEl.style.lineHeight = "1";
                  closeEl.style.color = "#a3a3a3";
                  closeEl.style.cursor = "pointer";
                  closeEl.onclick = () => infoWindow.close();
                  content.appendChild(closeEl);
                  const nameEl = document.createElement("div");
                  nameEl.style.fontWeight = "600";
                  nameEl.textContent = place.name;
                  content.appendChild(nameEl);
                  if (place.address) {
                    const addressEl = document.createElement("div");
                    addressEl.style.color = "#737373";
                    addressEl.style.fontSize = "12px";
                    addressEl.textContent = place.address;
                    content.appendChild(addressEl);
                  }
                  // Only trust this place's own address text when our own
                  // geocoding actually resolved it — otherwise qualify the
                  // name with the trip's destination city instead.
                  const mapsQuery = (place.addressTrusted && place.address)
                    ? [place.name, place.address].filter(Boolean).join(", ")
                    : [place.name, tripDestination].filter(Boolean).join(", ");
                  const googleUrl = "https://www.google.com/maps/search/?api=1&query=" +
                    encodeURIComponent(mapsQuery);
                  const makeMapLink = (href, label) => {
                    const linkEl = document.createElement("a");
                    linkEl.href = href;
                    linkEl.textContent = label;
                    linkEl.style.display = "block";
                    linkEl.style.marginTop = "4px";
                    linkEl.style.fontSize = "12px";
                    return linkEl;
                  };
                  const viewCardEl = document.createElement("button");
                  viewCardEl.type = "button";
                  viewCardEl.textContent = "\\ud83d\\udccb View place card";
                  viewCardEl.style.display = "block";
                  viewCardEl.style.marginTop = "4px";
                  viewCardEl.style.fontSize = "12px";
                  viewCardEl.style.color = "#f9532c";
                  viewCardEl.style.textDecoration = "underline";
                  viewCardEl.style.background = "none";
                  viewCardEl.style.border = "none";
                  viewCardEl.style.padding = "0";
                  viewCardEl.style.cursor = "pointer";
                  viewCardEl.onclick = () => window.webkit.messageHandlers.selectPlace.postMessage(place.id);
                  content.appendChild(viewCardEl);
                  content.appendChild(makeMapLink(googleUrl, "Open in Google Maps"));
                  if (place.naverMapUrlString) content.appendChild(makeMapLink(place.naverMapUrlString, "Open in Naver Map"));
                  if (place.kakaoMapUrlString) content.appendChild(makeMapLink(place.kakaoMapUrlString, "Open in Kakao Map"));
                  if (place.tmapUrlString) content.appendChild(makeMapLink(place.tmapUrlString, "Open in Tmap"));
                  infoWindow.setContent(content);
                  infoWindow.open(map, marker);
                });
                bounds.extend(position);
              });

              if (places.length > 1) {
                map.fitBounds(bounds);
              }
            }
          </script>
          <script src="https://oapi.map.naver.com/openapi/v3/maps.js?ncpKeyId=\(clientId)" onload="initMap()" onerror="showLoadError('Failed to load the Naver Map script.')"></script>
        </body>
        </html>
        """
    }
}
