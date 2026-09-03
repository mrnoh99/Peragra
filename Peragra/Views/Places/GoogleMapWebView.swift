import SwiftUI
import WebKit
import UIKit

/// Renders saved places on a Google Map, for people who've opted into
/// Google Maps in Settings with their own API key. Implemented as a
/// self-contained HTML page loaded into a WKWebView (same technique as
/// InstagramEmbedView) — Google doesn't offer a SwiftUI-native map view,
/// and pulling in their iOS SDK would mean an unreviewable binary
/// dependency, so the JS Maps API in a WebView keeps this consistent with
/// how the rest of this app avoids third-party SDKs.
struct GoogleMapWebView: UIViewRepresentable {
    struct MarkerPlace: Encodable {
        let id: String
        let name: String
        let address: String
        let emoji: String
        let visited: Bool
        let latitude: Double
        let longitude: Double
    }

    let apiKey: String
    let places: [MarkerPlace]

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.html(apiKey: apiKey, places: places), baseURL: URL(string: "https://maps.googleapis.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Sends taps on the "Open in Google Maps" link out to the system
    /// (Google Maps app or Safari) instead of navigating inside this
    /// WebView, which would just replace the map with a bare page and
    /// leave no way back.
    final class Coordinator: NSObject, WKNavigationDelegate {
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

    private static func html(apiKey: String, places: [MarkerPlace]) -> String {
        let placesJSON: String
        if let data = try? JSONEncoder().encode(places), let json = String(data: data, encoding: .utf8) {
            placesJSON = json.replacingOccurrences(of: "</", with: "<\\/")
        } else {
            placesJSON = "[]"
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
            let mapReady = false;

            // A bad/restricted API key never calls initMap and doesn't
            // surface any error either (Google just logs to the console),
            // so a WKWebView showing this would otherwise stay blank
            // forever with no feedback — found by testing the equivalent
            // web app code against a real key failure.
            setTimeout(() => {
              if (mapReady) return;
              document.getElementById("map").outerHTML =
                '<div style="display:flex;align-items:center;justify-content:center;' +
                'height:100%;padding:24px;text-align:center;font:14px -apple-system,sans-serif;' +
                'color:#a3a3a3;">Couldn\\'t load Google Maps — check your API key in Settings.</div>';
            }, 10000);

            function initMap() {
              mapReady = true;
              const map = new google.maps.Map(document.getElementById("map"), {
                zoom: 13,
                center: { lat: places[0]?.latitude ?? 0, lng: places[0]?.longitude ?? 0 },
              });

              const bounds = new google.maps.LatLngBounds();
              const infoWindow = new google.maps.InfoWindow();

              places.forEach((place) => {
                const position = { lat: place.latitude, lng: place.longitude };
                const marker = new google.maps.Marker({
                  position,
                  map,
                  opacity: place.visited ? 0.5 : 1,
                  label: { text: place.emoji, fontSize: "16px" },
                });
                marker.addListener("click", () => {
                  // Built as DOM nodes with textContent, not an HTML
                  // string, so a place name/address containing markup
                  // (pasted from an Instagram caption, say) can't inject
                  // into the page.
                  const content = document.createElement("div");
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
                  const mapsUrl = "https://www.google.com/maps/search/?api=1&query=" +
                    encodeURIComponent([place.name, place.address].filter(Boolean).join(", "));
                  const linkEl = document.createElement("a");
                  linkEl.href = mapsUrl;
                  linkEl.textContent = "Open in Google Maps";
                  linkEl.style.display = "block";
                  linkEl.style.marginTop = "4px";
                  linkEl.style.fontSize = "12px";
                  content.appendChild(linkEl);
                  infoWindow.setContent(content);
                  infoWindow.open(map, marker);
                });
                bounds.extend(position);
              });

              if (places.length > 1) {
                map.fitBounds(bounds, 40);
              }
            }
          </script>
          <script async src="https://maps.googleapis.com/maps/api/js?key=\(apiKey)&callback=initMap"></script>
        </body>
        </html>
        """
    }
}
