import SwiftUI
import WebKit

struct ConnectBankFlow: View {
    let provider: SignuDataProviding
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
            guard case .loading = phase else { return }
            do {
                phase = .widget(try await provider.connectSession(connectionId: connectionId))
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private static let syncGrace: Duration = .seconds(20)
    private static let pollInterval: Duration = .seconds(3)

    private func register(_ itemId: String, simulated: Bool = false) {
        phase = .registering
        Task {
            do {
                try await provider.registerConnection(itemId: itemId)
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            if !simulated { await waitForFirstRows() }
            onFinished(true)
        }
    }

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
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: messageName)
    }

    private static func page(token: String) -> String {
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
        private weak var popup: WKWebView?

        init(onSuccess: @escaping (String) -> Void,
             onFailure: @escaping (String) -> Void,
             onClose: @escaping () -> Void) {
            self.onSuccess = onSuccess
            self.onFailure = onFailure
            self.onClose = onClose
        }

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

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            let popup = WKWebView(frame: webView.bounds, configuration: configuration)
            popup.uiDelegate = self
            popup.navigationDelegate = self
            popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            popup.backgroundColor = .clear
            popup.isOpaque = false
            webView.addSubview(popup)
            self.popup = popup
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            guard webView === popup else { return }
            popup?.removeFromSuperview()
            popup = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard webView !== popup else { return }
            onFailure(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            guard webView !== popup else { return }
            onFailure(error.localizedDescription)
        }
    }
}

struct ConnectTarget: Identifiable {
    let connectionId: UUID?
    var id: String { connectionId?.uuidString ?? "new" }
}

extension View {
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
                    if connected { onConnected() }
                }
            )
        }
    }
}

#Preview("Connect a bank (simulated)") {
    ConnectBankFlow(provider: MockDataProvider(), onFinished: { _ in })
}
