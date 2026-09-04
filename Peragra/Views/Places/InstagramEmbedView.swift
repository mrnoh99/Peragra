import SwiftUI
import WebKit

/// Renders an Instagram post/reel inline using Instagram's public embed
/// script (the same technique any website uses to embed a post — no API
/// key or app review required). Instagram does not expose a user's Saved
/// collection through any API, so this only works from a link the person
/// brings over themselves.
struct InstagramEmbedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // SwiftUI calls this on every body re-evaluation of whatever
        // contains this view (e.g. typing anywhere else in
        // AddPlaceSheet's Form), not just when `url` itself changes —
        // reloading unconditionally re-fetches Instagram's embed script
        // and flashes the content on every unrelated keystroke, and
        // floods WKWebView with back-to-back loads (the likely source of
        // "Failed to terminate process" BrowserEngineKit log noise), so
        // only reload when the URL actually changed.
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.loadHTMLString(Self.html(for: url), baseURL: URL(string: "https://www.instagram.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedURL: URL?
    }

    private static func html(for url: URL) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body { margin: 0; background: transparent; }
          </style>
        </head>
        <body>
          <blockquote class="instagram-media" data-instgrm-permalink="\(url.absoluteString)" data-instgrm-version="14" style="margin:0; width:100%;">
            <a href="\(url.absoluteString)">View this post on Instagram</a>
          </blockquote>
          <script async src="https://www.instagram.com/embed.js"></script>
        </body>
        </html>
        """
    }
}

#Preview {
    InstagramEmbedView(url: URL(string: "https://www.instagram.com/p/CxampleId/")!)
        .frame(height: 420)
}
