import SwiftUI
import WebKit
import CoreLocation
import CoreMotion
import WidgetKit

/// The hybrid shell: the same pages as the Telegram version, shown in the app's own web view.
/// `server/web/native.js` stands in for Telegram there and talks to this file over the «dv» message handler;
/// everything a page cannot do (strong haptics, location, motion, links, widgets) happens here.
struct ShellScreen: View {
    @EnvironmentObject var state: AppState
    @StateObject private var shell = ShellModel()

    var body: some View {
        ZStack {
            Color(hex: 0xEEF0EE).ignoresSafeArea()
            WebShell(model: shell)
                .ignoresSafeArea()
                .opacity(shell.ready ? 1 : 0)
            if !shell.ready && shell.failed == nil {
                VStack(spacing: 6) {
                    Text("DaVincit").font(.serif(34, .semibold))
                    Text("Amor vincit omnia").font(.caps).tracking(2).foregroundStyle(.secondary)
                }
            }
            if let why = shell.failed {
                VStack(spacing: 14) {
                    Text("Немає зв'язку").font(.serif(24, .semibold))
                    Text(why).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Спробувати ще") { shell.reload() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(32)
            }
        }
        .animation(.easeOut(duration: 0.25), value: shell.ready)
        .foregroundStyle(Color(hex: 0x17202C))
        .onAppear { shell.start(); state.whiteStatusBar = !shell.darkStatusBar }
        .onDisappear { state.whiteStatusBar = false }
        .onChange(of: shell.darkStatusBar) { _, dark in state.whiteStatusBar = !dark }
        .onChange(of: state.pendingLink) { _, link in
            if let link { shell.open(link: link); state.pendingLink = nil }
        }
        .task { if let link = state.pendingLink { shell.open(link: link); state.pendingLink = nil } }
    }
}

@MainActor
final class ShellModel: NSObject, ObservableObject {
    @Published var ready = false
    @Published var failed: String?
    /// Dark digits in the status bar over a light top («Налаштування»), white over the rest.
    @Published var darkStatusBar = false

    fileprivate var web: WKWebView?
    private let location = OneShotLocation()
    private let motion = CMMotionManager()
    private var started = false
    /// The pages say whether there is anywhere to go back to (not on the Основа): the edge swipe moves the page only then.
    private var canBack = false
    /// A link from a widget that came before the pages were ready.
    private var waitingLink: String?

    func start() {
        guard !started else { return }
        started = true
        load()
    }

    func reload() {
        failed = nil
        load()
    }

    private func load() {
        guard let web else { return }
        var req = URLRequest(url: KeyStore.serverURL)
        req.cachePolicy = .reloadRevalidatingCacheData
        web.load(req)
    }

    /// The web view is made once and lives as long as the screen.
    fileprivate func makeWebView() -> WKWebView {
        if let web { return web }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()                 // the offline queue of the pages lives in localStorage / IndexedDB
        cfg.allowsInlineMediaPlayback = true
        cfg.applicationNameForUserAgent = "DaVincitApp/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1")"
        cfg.mediaTypesRequiringUserActionForPlayback = []  // the wooden click of the slider needs no first tap
        let ucc = WKUserContentController()
        ucc.add(WeakHandler(self), name: "dv")
        ucc.addUserScript(WKUserScript(source: Self.keyScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController = ucc
        // Telegram's own script is not needed here (native.js stands in for it): no request to telegram.org at every start
        let rules = #"[{"trigger":{"url-filter":"^https://telegram[.]org/"},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "dv-no-telegram", encodedContentRuleList: rules) { list, _ in
            if let list { ucc.add(list) }
        }

        let w = WKWebView(frame: .zero, configuration: cfg)
        w.navigationDelegate = self
        w.uiDelegate = self
        w.isOpaque = false
        w.backgroundColor = UIColor(Color(hex: 0xEEF0EE))
        w.scrollView.backgroundColor = .clear
        w.scrollView.bounces = false                       // no rubber band: the slider, the ring and the drums own the touches
        w.scrollView.alwaysBounceVertical = false
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.scrollView.showsVerticalScrollIndicator = false
        w.scrollView.showsHorizontalScrollIndicator = false
        w.allowsBackForwardNavigationGestures = false
        w.allowsLinkPreview = false
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeSwipe(_:)))
        edge.edges = .left
        w.addGestureRecognizer(edge)
        web = w
        return w
    }

    /// The pages look for the device key in localStorage (`dv-key-tg`): put ours there before they start,
    /// so they never ask Telegram who we are.
    private static func keyScript() -> String {
        guard let key = KeyStore.deviceKey,
              let data = try? JSONSerialization.data(withJSONObject: [key]),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return "try{localStorage.setItem('dv-key-tg',\(json)[0])}catch(e){}"
    }

    /// «Назад» from the left edge: the page follows the finger, then goes away (or springs back).
    @objc private func edgeSwipe(_ g: UIScreenEdgePanGestureRecognizer) {
        guard let v = g.view else { return }
        guard canBack else { v.transform = .identity; return }
        let x = max(0, g.translation(in: v.superview).x)
        switch g.state {
        case .changed:
            v.transform = CGAffineTransform(translationX: x, y: 0)
        case .ended, .cancelled, .failed:
            let go = g.state == .ended && (x > 90 || g.velocity(in: v.superview).x > 600)
            if go {
                UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseOut, animations: {
                    v.transform = CGAffineTransform(translationX: v.bounds.width, y: 0)
                }, completion: { _ in
                    self.js("window.DVNative&&window.DVNative.back()")
                    v.alpha = 0
                    v.transform = .identity
                    UIView.animate(withDuration: 0.22, delay: 0.06, options: .curveEaseOut, animations: { v.alpha = 1 }, completion: nil)
                })
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [], animations: {
                    v.transform = .identity
                }, completion: nil)
            }
        default:
            break
        }
    }

    /// A widget was tapped: «note» starts a voice note, «snap» the camera for a quick photo, «moment» the last photo, «date» the date of today.
    func open(link: String) {
        guard ready else { waitingLink = link; return }
        call("DV.deepLink", [link])
    }

    /// Calls a function of the pages with JSON arguments: `call("DV.dateEta", [id, result])`.
    private func call(_ fn: String, _ args: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: args), let json = String(data: data, encoding: .utf8) else { return }
        js("window.DV&&\(fn)&&\(fn).apply(null,\(json))")
    }

    private func js(_ source: String) {
        web?.evaluateJavaScript(source, completionHandler: nil)
    }

    private func resolve(_ id: Int, _ value: Any?) {
        let payload: String
        if let value, let data = try? JSONSerialization.data(withJSONObject: [value]), let s = String(data: data, encoding: .utf8) {
            payload = "\(s)[0]"
        } else {
            payload = "null"
        }
        js("window.DVNative&&window.DVNative.resolve(\(id),\(payload))")
    }

    // MARK: messages from the pages

    fileprivate func handle(_ body: Any) {
        guard let m = body as? [String: Any], let t = m["t"] as? String else { return }
        switch t {
        case "ready":
            ready = true
            if let l = waitingLink { waitingLink = nil; open(link: l) }
        case "back":
            canBack = m["on"] as? Bool ?? false
        case "haptic":
            Haptics.play(kind: m["kind"] as? String ?? "", style: m["style"] as? String ?? "")
        case "open":
            if let s = m["url"] as? String, let url = URL(string: s), ["http", "https", "tel", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(url)
            }
        case "location":
            let id = m["id"] as? Int ?? 0
            location.request { [weak self] c in
                self?.resolve(id, c.map { ["lat": (($0.latitude * 100_000).rounded() / 100_000), "lon": (($0.longitude * 100_000).rounded() / 100_000)] })
            }
        case "photo":
            resolve(m["id"] as? Int ?? 0, nil)   // the photo bridge comes with the next step (PhotoKit, date and place)
        case "motion":
            (m["on"] as? Bool ?? false) ? startMotion() : motion.stopAccelerometerUpdates()
        case "statusbar":
            darkStatusBar = m["dark"] as? Bool ?? false
        case "changed":
            WidgetCenter.shared.reloadAllTimelines()
        case "settings":
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case "eta":
            // how long the way to the place of a date is: on foot and by car, from where I am now
            let id = m["id"] as? String ?? ""
            let place = m["place"] as? String ?? ""
            location.request { [weak self] c in
                Task { @MainActor in
                    let r = await RouteETA.find(place: place, from: c)
                    self?.call("DV.dateEta", [id, r])
                }
            }
        case "savePhoto":
            if let s = m["data"] as? String, let d = Data(base64Encoded: s) {
                PhotoSaver.save(d) { [weak self] ok in self?.call("DV.photoSaved", [ok]) }
            }
        case "calendarAdd":
            if let title = m["title"] as? String, let a = m["startsAt"] as? Double {
                let start = Date(timeIntervalSince1970: a / 1000)
                let end = (m["endsAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? start.addingTimeInterval(3 * 3600)
                CalendarAdd.add(title: title, start: start, end: end, place: m["place"] as? String ?? "") { [weak self] ok in self?.call("DV.calendarAdded", [ok]) }
            }
        case "dateTrack":
            if m["on"] as? Bool ?? false, let id = m["id"] as? String {
                DateTracker.shared.start(id: id, partner: m["name"] as? String ?? "", eta: m["eta"] as? Int)
            } else {
                DateTracker.shared.stop()
            }
        case "dateActivity":
            if let id = m["id"] as? String {
                if m["on"] as? Bool ?? true, let ms = m["startsAt"] as? Double {
                    DateActivity.start(eventId: id, title: m["title"] as? String ?? "", place: m["place"] as? String ?? "", startsAt: Date(timeIntervalSince1970: ms / 1000))
                } else {
                    DateActivity.end(eventId: id)
                }
            }
        default:
            break
        }
    }

    /// Only strong jolts are passed on (the pages count three of them as a shake), not every reading.
    private func startMotion() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 1.0 / 30.0
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let a = data?.acceleration else { return }
            let g = 9.81
            let mag = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() * g
            guard abs(mag - g) > 8 else { return }
            self?.js("window.DVNative&&window.DVNative.emit('_motion',{x:\(a.x * g),y:\(a.y * g),z:\(a.z * g)})")
        }
    }
}

extension ShellModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        // our own server stays inside; any other address a page tries to go to opens outside the app
        if action.targetFrame?.isMainFrame == true, url.host != KeyStore.serverURL.host, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // if native.js did not answer «ready» (an old copy of the pages), show the page anyway
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.ready = true }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        ready = false
        failed = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        failed = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

extension ShellModel: WKUIDelegate {
    private func top() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = vc?.presentedViewController { vc = next }
        return vc
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let top = top() else { completionHandler(); return }
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Гаразд", style: .default) { _ in completionHandler() })
        top.present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let top = top() else { completionHandler(false); return }
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Скасувати", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "Так", style: .default) { _ in completionHandler(true) })
        top.present(a, animated: true)
    }

    /// The microphone for voice notes: our own pages may use it once iOS itself has allowed the app.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host == KeyStore.serverURL.host ? .grant : .deny)
    }

    /// `window.open` and links with target=_blank: outside, in Safari.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { UIApplication.shared.open(url) }
        return nil
    }
}

/// WKUserContentController keeps its handlers strongly; this breaks the cycle.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var model: ShellModel?
    init(_ model: ShellModel) { self.model = model }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        Task { @MainActor in self.model?.handle(body) }
    }
}

struct WebShell: UIViewRepresentable {
    @ObservedObject var model: ShellModel
    func makeUIView(context: Context) -> WKWebView { model.makeWebView() }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Stronger than Telegram: every style is one step up, and a few patterns of our own.
enum Haptics {
    static func play(kind: String, style: String) {
        switch kind {
        case "impact":
            let (s, i): (UIImpactFeedbackGenerator.FeedbackStyle, CGFloat) = {
                switch style {
                case "soft": return (.medium, 0.8)
                case "light": return (.medium, 1.0)
                case "medium": return (.heavy, 0.9)
                case "rigid": return (.rigid, 1.0)
                default: return (.heavy, 1.0)
                }
            }()
            let g = UIImpactFeedbackGenerator(style: s)
            g.impactOccurred(intensity: i)
        case "notify":
            let g = UINotificationFeedbackGenerator()
            g.notificationOccurred(style == "error" ? .error : style == "warning" ? .warning : .success)
        case "select":
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
        case "pattern":
            pattern(style)
        default:
            break
        }
    }

    private static func pattern(_ name: String) {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        switch name {
        case "heartbeat":
            heavy.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { heavy.impactOccurred(intensity: 0.7) }
        case "drop":
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { heavy.impactOccurred(intensity: 1.0) }
        default:   // "drum" and anything unknown: one crisp tick
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
        }
    }
}

/// «Де я зараз»: asks once, answers once.
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: [(CLLocationCoordinate2D?) -> Void] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request(_ done: @escaping (CLLocationCoordinate2D?) -> Void) {
        waiting.append(done)
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(nil)
        default: manager.requestLocation()
        }
    }

    private func finish(_ c: CLLocationCoordinate2D?) {
        let all = waiting
        waiting = []
        all.forEach { $0(c) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !waiting.isEmpty else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: finish(nil)
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}
