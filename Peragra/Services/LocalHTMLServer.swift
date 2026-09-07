import Foundation
import Network

/// A minimal loopback-only HTTP/1.1 server that serves a single,
/// swappable HTML page — built specifically so NaverMapWebView can load
/// its embedded map through a genuine `http://localhost:<port>/`
/// navigation instead of `WKWebView.loadHTMLString(_:baseURL:)`.
///
/// `loadHTMLString` only fakes the page's origin (for resolving relative
/// URLs); it doesn't make WKWebView send a matching Referer/Origin header
/// on the cross-origin subresource requests the page itself triggers —
/// which is exactly what Naver's map tile requests are. Naver's tile
/// servers validate those against the domain registered for the Client
/// ID (the same "Web Service URL" that gates the initial script load),
/// so with a faked origin they get silently rejected — the script loads
/// and the map object initializes fine, but no tile ever renders. A real
/// HTTP navigation to this server sidesteps that: every request WKWebView
/// makes off the resulting page carries a genuine, consistent
/// `http://localhost:<port>/` origin, matching what's registered in the
/// NCP console (the same convention it documents for native-app WebView
/// embedding).
final class LocalHTMLServer {
    static let shared = LocalHTMLServer()

    private let queue = DispatchQueue(label: "com.peragra.localhtmlserver")
    private var listener: NWListener?
    private var port: UInt16?
    private var pendingCallbacks: [(UInt16?) -> Void] = []
    private var currentHTML = "<!doctype html><html><body></body></html>"

    private init() {}

    /// Updates the served page content, starting the server on first use,
    /// and calls back on the main queue with the URL to load once the
    /// server is ready to accept that request — nil if it never managed
    /// to start (a caller should fall back to loadHTMLString in that
    /// case, even though tiles won't authenticate there).
    func serve(html: String, completion: @escaping (URL?) -> Void) {
        queue.async {
            self.currentHTML = html
            if let port = self.port {
                DispatchQueue.main.async { completion(URL(string: "http://localhost:\(port)/")) }
                return
            }
            self.pendingCallbacks.append { port in
                DispatchQueue.main.async {
                    completion(port.map { URL(string: "http://localhost:\($0)/")! })
                }
            }
            if self.listener == nil {
                self.startListening()
            }
        }
    }

    private func startListening() {
        let params = NWParameters.tcp
        // Loopback only — this process shouldn't be reachable from
        // anywhere else on the local network.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        guard let listener = try? NWListener(using: params) else {
            resolvePending(port: nil)
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let assignedPort = listener.port?.rawValue
                self.queue.async {
                    self.port = assignedPort
                    self.resolvePending(port: assignedPort)
                }
            case .failed, .cancelled:
                self.queue.async { self.resolvePending(port: nil) }
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func resolvePending(port: UInt16?) {
        let callbacks = pendingCallbacks
        pendingCallbacks.removeAll()
        callbacks.forEach { $0(port) }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Every request gets the same current page, whatever the path —
        // this only ever serves one document, never a real multi-route
        // site, so parsing the request beyond "something arrived" isn't
        // needed.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if data != nil || isComplete {
                self.respond(on: connection)
            } else if error != nil {
                connection.cancel()
            }
        }
    }

    private func respond(on connection: NWConnection) {
        let body = Data(currentHTML.utf8)
        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
        ].joined(separator: "\r\n") + "\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
