import Foundation

/// Device key and server address, shared with the extensions through the App Group.
/// Falls back to the app's own defaults if the App Group is not available (SideStore quirk).
enum KeyStore {
    private static let keyName = "deviceKey"
    private static let serverName = "serverURL"
    private static let meName = "meJSON"

    static var defaults: UserDefaults { UserDefaults(suiteName: Shared.group) ?? .standard }

    static var deviceKey: String? {
        get { defaults.string(forKey: keyName) }
        set {
            if let v = newValue { defaults.set(v, forKey: keyName) } else { defaults.removeObject(forKey: keyName) }
        }
    }

    static var serverURL: URL {
        get { defaults.string(forKey: serverName).flatMap(URL.init(string:)) ?? Shared.defaultServer }
        set { defaults.set(newValue.absoluteString, forKey: serverName) }
    }

    /// Last known `/me` answer, so the app opens instantly and offline.
    static var cachedMe: MeResult? {
        get { defaults.data(forKey: meName).flatMap { try? API.decoder.decode(MeResult.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? API.encoder.encode($0) }, forKey: meName) }
    }

    static func signOut() {
        deviceKey = nil
        cachedMe = nil
    }
}
