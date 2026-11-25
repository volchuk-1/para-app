import SwiftUI

/// Who we are and how to talk to the server. Lives for the whole app.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var me: Member?
    @Published private(set) var partner: Member?
    @Published var offline = false
    @Published var banner: String?
    /// The shell is on screen and its top is dark: the status bar digits must be white.
    @Published var whiteStatusBar = false
    /// A link shared into the app (`davincit://share?url=…`) waiting to be handled.
    @Published var pendingShare: URL?
    /// A tap on a widget: «note», «snap», «moment», «date».
    @Published var pendingLink: String?

    var isPaired: Bool { KeyStore.deviceKey != nil }
    var api: API { API.current() }

    init() {
        if let cached = KeyStore.cachedMe {
            me = cached.me
            partner = cached.partner
        }
    }

    /// Re-reads `/me`. A 401 means this phone was removed from the pair.
    func refresh() async {
        guard isPaired else { return }
        do {
            let r = try await api.me()
            apply(r)
            offline = false
        } catch APIError.unauthorized {
            signOut()
        } catch APIError.offline {
            offline = true
        } catch {
            banner = error.localizedDescription
        }
    }

    func paired(_ r: PairResult) {
        KeyStore.deviceKey = r.deviceKey
        apply(MeResult(me: r.me, partner: r.partner, coupleId: ""))
    }

    func apply(_ r: MeResult) {
        me = r.me
        partner = r.partner
        KeyStore.cachedMe = r
    }

    func renamed(_ m: Member) {
        me = m
        if let p = partner { KeyStore.cachedMe = MeResult(me: m, partner: p, coupleId: KeyStore.cachedMe?.coupleId ?? "") }
    }

    func signOut() {
        KeyStore.signOut()
        me = nil
        partner = nil
    }

    func handle(url: URL) {
        guard url.scheme == "davincit",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if url.host == "share",
           let s = comps.queryItems?.first(where: { $0.name == "url" })?.value,
           let shared = URL(string: s) {
            pendingShare = shared
        } else if let host = url.host, ["note", "snap", "moment", "date", "boiler"].contains(host) {
            pendingLink = host
        }
    }
}
