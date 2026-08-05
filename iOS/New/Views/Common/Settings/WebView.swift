//
//  WebView.swift
//  Aidoku
//
//  Created by Skitty on 5/21/25.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    let localStorageKeys: [String]

    @Binding var cookies: [String: String]
    @Binding var localStorage: [String: String]
    @Binding var reloadToggle: Bool

    private let webView = WKWebView()

    init(
        _ url: URL,
        localStorageKeys: [String] = [],
        cookies: Binding<[String: String]> = .constant([:]),
        localStorage: Binding<[String: String]> = .constant([:]),
        reloadToggle: Binding<Bool> = .constant(false)
    ) {
        self.url = url
        self.localStorageKeys = localStorageKeys
        self._cookies = cookies
        self._localStorage = localStorage
        self._reloadToggle = reloadToggle
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.load(URLRequest(url: url))
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if reloadToggle {
            reloadToggle = false
            uiView.reload()
        }
    }

    func makeCoordinator() -> Coordinator {
        .init(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        var parent: WebView
        private var pollTask: Task<Void, Never>?

        init(parent: WebView) {
            self.parent = parent
            super.init()
            WKWebsiteDataStore.default().httpCookieStore.add(self)
        }

        deinit {
            WKWebsiteDataStore.default().httpCookieStore.remove(self)
            pollTask?.cancel()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { [weak self] in
                await self?.refreshState(webView: webView)
            }
            // SPA login flows often write the token to localStorage via JS without a full page
            // navigation or a cookie change, so neither didFinish nor cookiesDidChange would fire
            // again. Poll periodically while the login sheet is open to catch that case too.
            startPollingIfNeeded(webView: webView)
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { [weak self] in
                guard let self else { return }
                await self.refreshState(webView: self.parent.webView)
            }
        }

        @MainActor
        private func refreshState(webView: WKWebView) async {
            let cookies = await webView.getCookies(for: parent.url.host)
            parent.cookies = cookies
            // Always scan localStorage (requested keys + token/auth heuristic) so SPA logins
            // that write under unexpected key names still surface a value for handleWebLogin.
            let storage = await webView.getLocalStorage(keys: parent.localStorageKeys)
            parent.localStorage = storage
        }

        private func startPollingIfNeeded(webView: WKWebView) {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self, weak webView] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled, let self, let webView else { return }
                    await self.refreshState(webView: webView)
                }
            }
        }
    }
}
