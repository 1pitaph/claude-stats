import AppKit
import SwiftUI
@preconcurrency import WebKit

struct LinuxDoWebLoginSheet: View {
    @Bindable var store: LinuxDoStore
    @Binding var isPresented: Bool
    @State private var status = "Sign in with Linux.do in this window."
    @State private var attemptedCookieSignature: String?
    @State private var isVerifying = false

    private let loginURL = URL(string: "https://linux.do/login")!

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LinuxDo Sign In")
                        .font(.sora(18, weight: .semibold))
                    Text(status)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(2)
                }
                Spacer()
                if isVerifying {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Cancel") {
                    isPresented = false
                }
                .controlSize(.small)
            }
            .padding(14)

            StxRule()

            LinuxDoWebLoginView(url: loginURL) { cookies in
                handle(cookies: cookies)
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 620, idealHeight: 680)
        .onChange(of: store.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                isPresented = false
            }
        }
    }

    @MainActor
    private func handle(cookies: [LinuxDoStoredCookie]) {
        let linuxCookies = cookies.filter(\.isLinuxDoCookie)
        let session = LinuxDoWebSession(cookies: linuxCookies)
        guard session.isAuthenticated,
              !isVerifying else {
            return
        }

        let signature = session.cookieHeader() ?? ""
        guard attemptedCookieSignature != signature else { return }
        attemptedCookieSignature = signature
        isVerifying = true
        status = "Verifying Linux.do browser session..."

        Task { @MainActor in
            let success = await store.signInWithWebSession(session)
            isVerifying = false
            if success {
                isPresented = false
            } else {
                attemptedCookieSignature = nil
                status = store.lastError ?? "Could not verify this Linux.do session yet."
            }
        }
    }
}

struct LinuxDoWebLoginView: NSViewRepresentable {
    let url: URL
    let onCookiesChanged: @MainActor @Sendable ([LinuxDoStoredCookie]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookiesChanged: onCookiesChanged)
    }

    func makeNSView(context: Context) -> LinuxDoWebLoginContainerView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        let container = LinuxDoWebLoginContainerView()
        container.installRootWebView(webView)
        context.coordinator.attach(container: container, rootWebView: webView)
        webView.load(URLRequest(url: url))
        return container
    }

    func updateNSView(_ container: LinuxDoWebLoginContainerView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, @unchecked Sendable {
        private let onCookiesChanged: @MainActor @Sendable ([LinuxDoStoredCookie]) -> Void
        private weak var container: LinuxDoWebLoginContainerView?
        private weak var rootWebView: WKWebView?

        init(onCookiesChanged: @escaping @MainActor @Sendable ([LinuxDoStoredCookie]) -> Void) {
            self.onCookiesChanged = onCookiesChanged
        }

        func attach(container: LinuxDoWebLoginContainerView, rootWebView: WKWebView) {
            self.container = container
            self.rootWebView = rootWebView
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncCookies(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            syncCookies(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow)
                return
            }

            if isBlankNavigation(url) {
                decisionHandler(navigationAction.targetFrame == nil ? .cancel : .allow)
                return
            }

            if isWebNavigation(scheme) {
                if navigationAction.targetFrame == nil {
                    webView.load(navigationAction.request)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
            } else if shouldOpenExternally(url) {
                Task { @MainActor in
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                Log.app.debug("Blocked LinuxDo web login navigation to unsupported URL: \(url.absoluteString, privacy: .public)")
                decisionHandler(.cancel)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url, isBlankNavigation(url) {
                let popup = makePopupWebView(configuration: configuration)
                container?.presentPopupWebView(popup)
                return popup
            }

            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                let popup = makePopupWebView(configuration: configuration)
                container?.presentPopupWebView(popup)
                return popup
            }

            if isWebNavigation(scheme) {
                webView.load(navigationAction.request)
            } else if shouldOpenExternally(url) {
                NSWorkspace.shared.open(url)
            } else {
                Log.app.debug("Blocked LinuxDo popup navigation to unsupported URL: \(url.absoluteString, privacy: .public)")
            }
            return nil
        }

        func webViewDidClose(_ webView: WKWebView) {
            container?.closePopupWebView(webView)
        }

        private func makePopupWebView(configuration: WKWebViewConfiguration) -> WKWebView {
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true

            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.allowsBackForwardNavigationGestures = true
            return popup
        }

        private func isWebNavigation(_ scheme: String) -> Bool {
            scheme == "http" || scheme == "https"
        }

        private func isBlankNavigation(_ url: URL) -> Bool {
            let absolute = url.absoluteString.lowercased()
            return absolute == "about:blank" || absolute == "about:srcdoc"
        }

        private func shouldOpenExternally(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased(),
                  !["about", "blob", "data", "javascript"].contains(scheme) else {
                return false
            }

            return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
        }

        private func syncCookies(from webView: WKWebView) {
            let callback = onCookiesChanged
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let stored = cookies
                    .map(LinuxDoStoredCookie.init(cookie:))
                    .filter(\.isLinuxDoCookie)
                Task { @MainActor in
                    callback(stored)
                }
            }
        }
    }
}

final class LinuxDoWebLoginContainerView: NSView {
    private weak var rootWebView: WKWebView?
    private weak var popupWebView: WKWebView?
    private var activeConstraints: [NSLayoutConstraint] = []

    func installRootWebView(_ webView: WKWebView) {
        rootWebView = webView
        show(webView)
    }

    func presentPopupWebView(_ webView: WKWebView) {
        popupWebView = webView
        show(webView)
    }

    func closePopupWebView(_ webView: WKWebView) {
        guard popupWebView === webView else { return }
        popupWebView = nil

        if let rootWebView {
            show(rootWebView)
        } else {
            webView.removeFromSuperview()
        }
    }

    private func show(_ webView: WKWebView) {
        activeConstraints.forEach { $0.isActive = false }
        activeConstraints.removeAll()

        subviews
            .filter { $0 !== webView }
            .forEach { $0.removeFromSuperview() }

        if webView.superview !== self {
            webView.removeFromSuperview()
            addSubview(webView)
        }

        webView.translatesAutoresizingMaskIntoConstraints = false
        activeConstraints = [
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(activeConstraints)
    }
}
