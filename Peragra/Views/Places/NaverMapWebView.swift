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
        webView.loadHTMLString(
            Self.html(clientId: clientId, places: places, tripDestination: tripDestination),
            baseURL: URL(string: "https://oapi.map.naver.com")
        )
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
          </style>
        </head>
        <body>
          <div id="map"></div>
          <script>
            const places = \(placesJSON);
            const tripDestination = \(tripDestinationJSON);
            let mapReady = false;

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
            // GoogleMapWebView uses for its own failure mode.
            setTimeout(() => showLoadError("Couldn\\'t load Naver Map — check your Client ID in Settings."), 10000);
            window.navermap_authFailure = function() {
              showLoadError("Naver Map rejected this Client ID — check it in Settings.");
            };

            function initMap() {
              mapReady = true;
              const first = places[0];
              const map = new naver.maps.Map(document.getElementById("map"), {
                center: new naver.maps.LatLng(first ? first.latitude : 37.5665, first ? first.longitude : 126.978),
                zoom: 13,
              });

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
