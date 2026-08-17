import SwiftUI
import WebKit

/// Connecting a bank (and re-authenticating one) — the flow every "Connect a
/// bank" button in the app has been pointing at since the empty state was
/// designed, and which nothing supplied until now. The one existing connection
/// was made by hand through Pluggy's hosted widget and transcribed into the
/// database by a seed script that described itself as a stopgap.
///
/// Three steps, one screen:
///
///  1. **Mint a token.** Pluggy Connect runs client-side and cannot hold the API
///     secret, so `connect-token` issues a short-lived token scoped to the single
///     item this session produces.
///  2. **Run the widget.** It is JavaScript, so it runs in a `WKWebView`. There is
///     no native SDK to adopt instead.
///  3. **Register what it produced.** The widget hands back an item id;
///     `register-connection` verifies the item carries this user's `clientUserId`,
///     writes the `connection` row and runs the first sync — so the user comes
///     back to cards, transactions and detected subscriptions rather than an empty
///     row waiting for tomorrow's cron.
///
/// `connectionId` re-opens an existing link instead of adding a new one, which is
/// what 12b's Reconnect button and Home's needs-action banner need. Pluggy
/// requires the item id on the token itself for that; a create-mode token cannot
/// update an item.
struct ConnectBankFlow: View {
    let provider: SignuDataProviding
    /// nil = add a bank; non-nil = re-authenticate that one.
    var connectionId: UUID?
    var onFinished: (Bool) -> Void

    @State private var phase = Phase.loading

    private enum Phase {
        case loading
        case widget(ConnectSession)
        case registering
        case failed(String)
    }

    var body: some View {
        ZStack {
            SignuColor.paper.ignoresSafeArea()

            switch phase {
            case .loading:
                status("Getting things ready…")
            case .widget(let session):
                if session.simulated {
                    simulated
                } else {
                    PluggyConnectWebView(
                        token: session.accessToken,
                        onSuccess: { itemId in register(itemId) },
                        onFailure: { phase = .failed($0) },
                        onClose: { onFinished(false) }
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
            case .registering:
                status(connectionId == nil ? "Reading your accounts…" : "Reconnecting…")
            case .failed(let message):
                failure(message)
            }

            VStack {
                HStack {
                    ChromeButton(systemName: "xmark") { onFinished(false) }
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, SignuMetric.screenPadding)
            .padding(.top, 4)
        }
        .task {
            // Only once: `.task` re-runs if the view identity changes, and a
            // second token would abandon a widget session mid-flow.
            guard case .loading = phase else { return }
            do {
                phase = .widget(try await provider.connectSession(connectionId: connectionId))
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// How long to hold the screen while the first sync runs, and how often to
    /// look. The server returns as soon as the link exists and keeps scanning
    /// behind the response, so this is a courtesy wait rather than a dependency:
    /// most syncs land inside it, and the ones that do not stop blocking the user
    /// on a spinner. Home's watching state takes it from there — it was designed
    /// for exactly this ("Updated just now · Nubank connected").
    private static let syncGrace: Duration = .seconds(20)
    private static let pollInterval: Duration = .seconds(3)

    private func register(_ itemId: String, simulated: Bool = false) {
        phase = .registering
        Task {
            do {
                try await provider.registerConnection(itemId: itemId)
            } catch {
                // The link exists at Pluggy either way — what failed is our record
                // of it. Saying "couldn't connect" would send the user round the
                // widget again to create a second item.
                phase = .failed(error.localizedDescription)
                return
            }
            // Nothing is syncing behind a simulated link, so waiting for rows
            // would be waiting for a sync that was never started.
            if !simulated { await waitForFirstRows() }
            onFinished(true)
        }
    }

    /// Polls our own reads until the sync's rows show up, or the grace runs out.
    ///
    /// Polling rather than waiting on the server: the sync now outlives its own
    /// response, so there is nothing left to await. `refresh()` answers whether
    /// the re-read found anything, which is the only signal available and the
    /// honest one — it reports what the app can actually see.
    private func waitForFirstRows() async {
        let deadline = ContinuousClock.now + Self.syncGrace
        while ContinuousClock.now < deadline {
            if (try? await provider.refresh()) == true { return }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private func status(_ text: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().tint(SignuColor.ink)
            Text(text)
                .font(.signuBody)
                .foregroundStyle(SignuColor.textSecondary)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Couldn't connect")
                .font(.signuTitle)
                .foregroundStyle(SignuColor.textPrimary)
            // Signu's own functions write sentences and those pass through
            // untouched — v30's rule that the server's own words beat a generic
            // apology. Pluggy writes ENUMS, and `ITEM_USER_ALREADY_EXISTS` reached a
            // user verbatim (v53), so the codes we can defend are translated and
            // anything unrecognised is kept rather than replaced. See
            // `ConnectErrorCopy`.
            Text(ConnectErrorCopy.message(for: message))
                .font(.signuBody)
                .foregroundStyle(SignuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { phase = .loading }
                .buttonStyle(.signuPrimary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Mock-provider stand-in. Labelled as simulated on purpose: a fake bank that
    /// looked real in a preview is how a demo becomes a claim.
    private var simulated: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Simulated connection")
                .font(.signuTitle)
                .foregroundStyle(SignuColor.textPrimary)
            Text("This build runs on mock data, so there is no bank to sign in to. Continuing adds a simulated bank with one card.")
                .font(.signuBody)
                .foregroundStyle(SignuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Simulate success") { register("mock-item", simulated: true) }
                .buttonStyle(.signuPrimary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hosts Pluggy Connect, which ships as a browser widget and has no native SDK.
///
/// Three details are load-bearing and each was a decision:
///
///  * **The script version is pinned.** `…/latest/pluggy-connect.js` would let a
///    third party change what this screen runs, in a build already shipped.
///  * **The page is given a real https origin** via `baseURL`. HTML loaded with no
///    base gets an opaque origin, and the widget's calls to `api.pluggy.ai` are
///    cross-origin requests that an opaque origin cannot make. The host is one we
///    do not resolve and never fetch — it only has to be *ours* and stable, which
///    is why it is not pointed at a Pluggy domain we do not own.
///  * **Popups load in place.** Some connectors open their OAuth screen with
///    `target="_blank"`; with no `uiDelegate` a `WKWebView` silently drops those,
///    and the flow dead-ends on a button that appears to do nothing.
struct PluggyConnectWebView: UIViewRepresentable {
    let token: String
    var onSuccess: (String) -> Void
    var onFailure: (String) -> Void
    var onClose: () -> Void

    private static let widgetScript = "https://cdn.pluggy.ai/pluggy-connect/v2.8.2/pluggy-connect.js"
    private static let origin = URL(string: "https://connect.signu.local/")!
    static let messageName = "signu"

    func makeCoordinator() -> Coordinator {
        Coordinator(onSuccess: onSuccess, onFailure: onFailure, onClose: onClose)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Self.messageName)
        // The widget opens bank OAuth pages; without this they are blocked.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.loadHTMLString(Self.page(token: token), baseURL: Self.origin)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // The token is minted once per presentation; reloading here would restart
        // a session the user is part-way through.
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // The handler holds the coordinator, which holds the closures; without
        // this the web view outlives the screen.
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: messageName)
    }

    private static func page(token: String) -> String {
        // JSON-encoded rather than interpolated raw. A connect token is a JWT and
        // its alphabet is safe, but "the value happens to be safe" is not the same
        // property as "the value is escaped".
        let literal = String(data: (try? JSONEncoder().encode(token)) ?? Data(), encoding: .utf8) ?? "\"\""
        return """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
          html, body { margin: 0; height: 100%; background: #FBFAF7; }
        </style>
        <script src="\(widgetScript)"></script>
        </head>
        <body>
        <script>
          function send(message) {
            window.webkit.messageHandlers.\(messageName).postMessage(message);
          }
          try {
            var connect = new PluggyConnect({
              connectToken: \(literal),
              includeSandbox: false,
              onSuccess: function (data) {
                var id = data && data.item && data.item.id;
                if (id) { send({ event: 'success', itemId: id }); }
                else { send({ event: 'error', message: 'Pluggy returned no item id' }); }
              },
              onError: function (error) {
                send({ event: 'error', message: (error && (error.message || error.code)) || 'Pluggy Connect failed' });
              },
              onClose: function () { send({ event: 'close' }); }
            });
            connect.init();
          } catch (e) {
            send({ event: 'error', message: String(e) });
          }
        </script>
        </body>
        </html>
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
        private let onSuccess: (String) -> Void
        private let onFailure: (String) -> Void
        private let onClose: () -> Void

        init(onSuccess: @escaping (String) -> Void,
             onFailure: @escaping (String) -> Void,
             onClose: @escaping () -> Void) {
            self.onSuccess = onSuccess
            self.onFailure = onFailure
            self.onClose = onClose
        }

        /// `nonisolated`, because the protocol requirement is — and therefore the
        /// message cannot be read here. `WKScriptMessage.body` is main-actor
        /// isolated in the iOS 18.5 SDK that CI compiles against, where reading it
        /// from this context is an error; the iOS 26 SDK is laxer, so the local
        /// build said nothing. Third instance of that gap.
        ///
        /// `assumeIsolated` rather than a `Task`: WebKit delivers script messages
        /// on the main thread already, so this is stating a fact rather than
        /// scheduling a hop — and it traps loudly if the fact ever stops holding,
        /// which is better than a silent reordering of success and close.
        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            MainActor.assumeIsolated { handle(message.body) }
        }

        private func handle(_ body: Any) {
            let fields = body as? [String: Any]
            switch fields?["event"] as? String {
            case "success":
                if let itemId = fields?["itemId"] as? String { onSuccess(itemId) }
                else { onFailure("Pluggy returned no item id") }
            case "error":
                onFailure(fields?["message"] as? String ?? "Pluggy Connect failed")
            case "close":
                onClose()
            default:
                break
            }
        }

        /// `target="_blank"` in the same view. Returning nil — the default — drops
        /// the navigation and the connector's sign-in never opens.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFailure(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            // The widget script is a subresource of a page with no network origin,
            // so a failure here means the CDN or the network is unreachable — which
            // is worth saying rather than leaving a blank screen.
            onFailure(error.localizedDescription)
        }
    }
}

/// What the connect flow is being opened for. A bare `UUID?` cannot say
/// "presented, adding a new bank" — nil reads as "not presented" to
/// `.fullScreenCover(item:)`.
struct ConnectTarget: Identifiable {
    /// nil = add a bank; non-nil = re-authenticate that one.
    let connectionId: UUID?
    var id: String { connectionId?.uuidString ?? "new" }
}

extension View {
    /// Presents the connect flow.
    ///
    /// A modifier rather than one cover on the shell, because **the screen the
    /// user is looking at has to be the one presenting**: SwiftUI will not put a
    /// second full-screen cover over a first, so Reconnect on 12b — itself a
    /// cover — asked the shell to present and silently got nothing. Caught by a
    /// UI test that tapped the button and waited for a screen that never came.
    func connectBankCover(
        provider: SignuDataProviding,
        target: Binding<ConnectTarget?>,
        onConnected: @escaping () -> Void
    ) -> some View {
        fullScreenCover(item: target) { it in
            ConnectBankFlow(
                provider: provider,
                connectionId: it.connectionId,
                onFinished: { connected in
                    target.wrappedValue = nil
                    // Only on success: a cancelled flow changed nothing, and
                    // reloading would throw away scroll position to show the user
                    // exactly what they were already looking at.
                    if connected { onConnected() }
                }
            )
        }
    }
}

#Preview("Connect a bank (simulated)") {
    ConnectBankFlow(provider: MockDataProvider(), onFinished: { _ in })
}
