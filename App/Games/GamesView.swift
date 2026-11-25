import SwiftUI
import WebKit

// MARK: - «Ігри для двох»: the games live on the server as a web page (the Telegram version has them too), so new games
// and fixes reach the iPhone without a new build. One web view for the whole run of the app — switching pages keeps its game.

enum GamesWeb {
    static let shared: WKWebView = {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        // the page signs in with the device key it finds under "dv-key-tg"
        if let key = KeyStore.deviceKey,
           let data = try? JSONEncoder().encode(key), let json = String(data: data, encoding: .utf8) {
            let js = "try { localStorage.setItem('dv-key-tg', \(json)); } catch (e) {}"
            cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = UIColor(red: 0xF2 / 255, green: 0xEE / 255, blue: 0xE2 / 255, alpha: 1)
        v.scrollView.backgroundColor = v.backgroundColor
        v.scrollView.contentInsetAdjustmentBehavior = .never
        v.allowsBackForwardNavigationGestures = false
        v.uiDelegate = Dialogs.shared
        return v
    }()
    static var url: URL {
        var c = URLComponents(url: KeyStore.serverURL, resolvingAgainstBaseURL: false)!
        c.path = c.path.isEmpty ? "/" : c.path
        c.queryItems = [URLQueryItem(name: "tab", value: "games"), URLQueryItem(name: "embed", value: "1")]
        return c.url!
    }
    static func loadIfNeeded() {
        if shared.url == nil { shared.load(URLRequest(url: url)) }
    }

    /// alert() and confirm() of the page (without this confirm() silently says «no» and «Здатися» does nothing)
    final class Dialogs: NSObject, WKUIDelegate {
        static let shared = Dialogs()
        private func top() -> UIViewController? {
            var vc = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
            while let p = vc?.presentedViewController { vc = p }
            return vc
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            guard let vc = top() else { return completionHandler() }
            vc.present(a, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Скасувати", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "Так", style: .default) { _ in completionHandler(true) })
            guard let vc = top() else { return completionHandler(false) }
            vc.present(a, animated: true)
        }
    }
}

struct GamesWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        GamesWeb.loadIfNeeded()
        return GamesWeb.shared
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct GamesPage: View {
    var body: some View {
        GamesWebView()
            .padding(.top, 4)
            .background(Theme.cream.ignoresSafeArea())
    }
}
