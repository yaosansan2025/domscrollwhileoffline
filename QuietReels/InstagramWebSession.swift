import Foundation
import SwiftUI
import WebKit

struct WebReelCandidate: Hashable {
    let reelID: String
    let reelURL: String
    let mediaURL: URL
}

enum WebDiscoveryError: LocalizedError {
    case loginRequired
    case noDownloadableMedia

    var errorDescription: String? {
        switch self {
        case .loginRequired:
            return "Sign in to Instagram in the in-app Web Session, then try again."
        case .noDownloadableMedia:
            return "The current Instagram Web page exposed no direct video files. Blob streams, protected media, and page links cannot be cached by this prototype."
        }
    }
}

@MainActor
final class InstagramWebSession: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published private(set) var pageDescription = "Instagram Web session not opened"
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var awaitedNavigation: WKNavigation?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func openLoginPage() {
        guard webView.url?.host?.hasSuffix("instagram.com") != true else { return }
        webView.load(URLRequest(url: URL(string: "https://www.instagram.com/")!))
    }

    func park() {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    func discover(limit: Int) async throws -> [WebReelCandidate] {
        defer { park() }
        try await loadReelsPage()
        let page = webView.url
        guard page?.host?.hasSuffix("instagram.com") == true,
              page?.path.contains("accounts/login") != true else {
            throw WebDiscoveryError.loginRequired
        }

        var found: [WebReelCandidate] = []
        var seen: Set<String> = []
        let rounds = min(max(limit * 2, 12), 100)
        for _ in 0..<rounds {
            try Task.checkCancellation()
            let raw = try await webView.evaluateJavaScript(Self.extractScript)
            if let rows = raw as? [[String: String]] {
                for row in rows {
                    guard let reel = row["reel"], let media = row["media"],
                          let canonical = try? LibraryStore.canonicalReelURL(reel),
                          let url = URL(string: media), url.scheme == "https",
                          url.host != nil else { continue }
                    let id = String(canonical.split(separator: "/").last ?? "")
                    if seen.insert(id).inserted {
                        found.append(WebReelCandidate(reelID: id, reelURL: canonical, mediaURL: url))
                    }
                }
            }
            if found.count >= limit { break }
            _ = try await webView.evaluateJavaScript(Self.scrollScript)
            try await Task.sleep(nanoseconds: 700_000_000)
        }
        guard !found.isEmpty else { throw WebDiscoveryError.noDownloadableMedia }
        return Array(found.prefix(limit))
    }

    func sessionCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
                continuation.resume(returning: $0)
            }
        }
    }

    private func loadReelsPage() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                navigationContinuation = continuation
                awaitedNavigation = webView.load(
                    URLRequest(url: URL(string: "https://www.instagram.com/reels/")!))
            }
        } onCancel: {
            Task { @MainActor in
                self.webView.stopLoading()
                self.navigationContinuation?.resume(throwing: CancellationError())
                self.navigationContinuation = nil
                self.awaitedNavigation = nil
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageDescription = webView.url?.path ?? "Instagram Web loaded"
        guard navigation === awaitedNavigation else { return }
        navigationContinuation?.resume()
        navigationContinuation = nil
        awaitedNavigation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === awaitedNavigation else { return }
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
        awaitedNavigation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard navigation === awaitedNavigation else { return }
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
        awaitedNavigation = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame != false,
              let host = navigationAction.request.url?.host?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        let allowed = host == "instagram.com" || host.hasSuffix(".instagram.com") ||
            host == "facebook.com" || host.hasSuffix(".facebook.com")
        decisionHandler(allowed ? .allow : .cancel)
    }

    private static let extractScript = """
    (() => {
      const rows = [];
      const candidates = document.querySelectorAll('video');
      for (const video of candidates) {
        const media = video.currentSrc || video.src || video.querySelector('source')?.src || '';
        let scope = video;
        let link = null;
        for (let depth = 0; depth < 8 && scope && !link; depth++, scope = scope.parentElement) {
          link = scope.querySelector('a[href*="/reel/"]');
        }
        const canonical = document.querySelector('link[rel="canonical"][href*="/reel/"]');
        const reel = link?.href || canonical?.href ||
          (new RegExp('^/reel/[^/]+/?$').test(location.pathname) ? location.href : '');
        if (reel && media) rows.push({reel, media});
      }
      return rows;
    })()
    """

    private static let scrollScript = """
    (() => {
      const items = [...document.querySelectorAll('*')].filter(e =>
        e.scrollHeight > e.clientHeight + 200 && e.clientHeight > 300);
      const target = items.sort((a,b) => b.clientHeight - a.clientHeight)[0];
      if (target) target.scrollTop += Math.max(target.clientHeight, 700);
      window.scrollBy(0, Math.max(window.innerHeight, 700));
      return true;
    })()
    """
}

struct InstagramLoginView: UIViewRepresentable {
    let session: InstagramWebSession
    var opensLoginPage = true

    func makeUIView(context: Context) -> WKWebView {
        if opensLoginPage { session.openLoginPage() }
        return session.webView
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
