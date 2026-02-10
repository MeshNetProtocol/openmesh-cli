import Foundation
import WebKit

@MainActor
final class WebViewTextFetcher: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<String, Error>?
    private var webView: WKWebView?
    private var timeoutTask: Task<Void, Never>?

    func fetchText(url: URL, timeoutSeconds: TimeInterval = 20) async throws -> String {
        cancel()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        webView = wv

        timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let ns = UInt64(max(1, timeoutSeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            self.finish(.failure(NSError(domain: "WebViewTextFetcher", code: 2, userInfo: [NSLocalizedDescriptionKey: "WebView 拉取超时"])))
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            continuation = cont
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = timeoutSeconds
            wv.load(req)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.body ? document.body.innerText : document.documentElement.innerText") { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.finish(.failure(error))
                return
            }
            let text = (result as? String) ?? ""
            self.finish(.success(text))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil

        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }

    private func cancel() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation = nil
    }
}
