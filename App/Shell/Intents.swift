import AppIntents
import Foundation

// Actions of DaVincit for «Команди» (Shortcuts) and automations of the phone:
//  - «Записати витрату» — for the automation «Транзакція» of Wallet: after a payment the amount and the shop go
//    straight to «Мої гроші» (only into my own cabinet);
//  - «Котел» — switch it on for a while or off: for an NFC tag at the door or «залишаю роботу».

enum IntentCall {
    /// POST to our own server with the device key of the app. True when the server said yes.
    static func post(_ path: String, _ body: [String: Any]) async -> Bool {
        guard let key = KeyStore.deviceKey else { return false }
        var req = URLRequest(url: KeyStore.serverURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, response) = try? await URLSession.shared.data(for: req) else { return false }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 500
        return code < 300
    }
}

struct LogSpendIntent: AppIntent {
    static var title: LocalizedStringResource = "Записати витрату"
    static var description = IntentDescription("Записує витрату у «Мої гроші» в DaVincit.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Сума")
    var amount: Double

    @Parameter(title: "Магазин")
    var merchant: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await IntentCall.post("money/spend", ["amount": amount, "merchant": merchant ?? ""])
        let sum = String(format: "%.2f", amount).replacingOccurrences(of: ".", with: ",")
        let text = ok ? "Записано: \(sum) ₴" : "DaVincit не зміг записати витрату"
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

enum BoilerCommand: String, AppEnum {
    case hour1, hour2, hour3, on, off

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Що зробити"
    static var caseDisplayRepresentations: [BoilerCommand: DisplayRepresentation] = [
        .hour1: "Увімкнути на 1 годину",
        .hour2: "Увімкнути на 2 години",
        .hour3: "Увімкнути на 3 години",
        .on: "Увімкнути",
        .off: "Вимкнути",
    ]

    var action: String {
        switch self {
        case .hour1: return "timer:1"
        case .hour2: return "timer:2"
        case .hour3: return "timer:3"
        case .on: return "on"
        case .off: return "off"
        }
    }
}

struct BoilerIntent: AppIntent {
    static var title: LocalizedStringResource = "Котел"
    static var description = IntentDescription("Вмикає або вимикає котел через DaVincit.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Що зробити", default: .hour2)
    var command: BoilerCommand

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await IntentCall.post("boiler", ["action": command.action])
        let text = ok ? "Котел: готово" : "Котел не відповів"
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}
