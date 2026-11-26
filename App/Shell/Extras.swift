import Foundation
import AppIntents
import Speech

// MARK: «Ранкова зведенка» і «На добраніч» — дії для «Команд» і автоматизацій (будильник, фокус «Сон»).

extension IntentCall {
    /// GET from our own server with the device key of the app.
    static func get(_ path: String) async -> [String: Any]? {
        guard let key = KeyStore.deviceKey else { return nil }
        var req = URLRequest(url: KeyStore.serverURL.appendingPathComponent(path))
        req.timeoutInterval = 15
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: req), ((response as? HTTPURLResponse)?.statusCode ?? 500) < 300 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// POST that also returns the answer of the server.
    static func postJSON(_ path: String, _ body: [String: Any]) async -> [String: Any]? {
        guard let key = KeyStore.deviceKey else { return nil }
        var req = URLRequest(url: KeyStore.serverURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: req), ((response as? HTTPURLResponse)?.statusCode ?? 500) < 300 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

struct MorningIntent: AppIntent {
    static var title: LocalizedStringResource = "Ранкова зведенка"
    static var description = IntentDescription("Погода, наші події, справи й заняття на сьогодні — Siri може прочитати вголос.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let r = await IntentCall.get("auto/morning") else {
            return .result(value: "", dialog: "DaVincit не відповів — перевір інтернет")
        }
        let text = [r["title"] as? String, r["body"] as? String].compactMap { $0 }.joined(separator: "\n")
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct GoodnightIntent: AppIntent {
    static var title: LocalizedStringResource = "На добраніч"
    static var description = IntentDescription("Надсилає «на добраніч ♥» — один раз за ніч. Зручно з фокусу «Сон».")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let r = await IntentCall.postJSON("auto/goodnight", [:]) else {
            return .result(dialog: "Не вдалося надіслати")
        }
        let sent = r["sent"] as? Bool ?? false
        let off = r["off"] as? Bool ?? false
        return .result(dialog: IntentDialog(stringLiteral: sent ? "Надіслано ♥" : off ? "Вимкнено в «Автоматизаціях»" : "Сьогодні вже надсилав"))
    }
}

// MARK: SideStore — коли застосунок перестане відкриватися (дата з підпису всередині самого застосунку).

enum AppExpiry {
    private static var sent = false

    /// The end of the signature of this copy of the app (SideStore signs it for 7 days), or nil.
    static var date: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1),
              let a = raw.range(of: "<?xml"), let z = raw.range(of: "</plist>") else { return nil }
        let xml = Data(raw[a.lowerBound..<z.upperBound].utf8)
        let plist = (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }

    /// Once a launch: the server reminds a day before.
    static func report() {
        guard !sent, let d = date else { return }
        sent = true
        Task { _ = await CalendarSync.api("PUT", "app/expiry", ["expiresAt": ISO8601DateFormatter().string(from: d)]) }
    }
}

// MARK: Чи вміє цей iPhone українську голосом (для нотаток): розпізнавання Apple на телефоні.

enum SpeechCheck {
    static func run() async -> [String: Any] {
        let uk = Locale(identifier: "uk-UA")
        var out: [String: Any] = [:]
        let old = SFSpeechRecognizer(locale: uk)
        out["classic"] = old != nil
        out["classicAvailable"] = old?.isAvailable ?? false
        out["classicOnDevice"] = old?.supportsOnDeviceRecognition ?? false
        out["system"] = UIDeviceInfo.system
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let supported = await SpeechTranscriber.supportedLocales
            let installed = await SpeechTranscriber.installedLocales
            out["analyzer"] = supported.contains { $0.identifier.lowercased().hasPrefix("uk") }
            out["analyzerInstalled"] = installed.contains { $0.identifier.lowercased().hasPrefix("uk") }
        } else {
            out["analyzer"] = NSNull()
        }
        #else
        out["analyzer"] = NSNull()   // this copy was built with an older Xcode: the new recognizer is not checked
        #endif
        return out
    }
}

enum UIDeviceInfo {
    static var system: String { ProcessInfo.processInfo.operatingSystemVersionString }
}
