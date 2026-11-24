import Foundation

// MARK: - «Мої гроші» (server: /money, private to the member who connected the «Витрати» widget)

struct MoneyCat: Codable, Hashable { let cat: String; let label: String; let amount: Double; let prev: Double }
struct MoneyMonth: Codable, Equatable { let spend: Double; let income: Double; let prevSpend: Double; let cats: [MoneyCat] }
struct MoneyCard: Codable, Hashable { let name: String; let balance: Double?; var at: Double? = nil }
struct MoneyDebt: Codable, Hashable {
    var name: String
    var amount: Double
    var cur: String
    var uah: Double = 0
    var rateMonth: Double = 0
    var monthly: Double = 0
    var due: String? = nil
    var link: String? = nil
    var note: String? = nil
    var live: Bool = false
}
struct MoneyJar: Codable, Hashable, Identifiable { let id: String; let title: String; let balance: Double; var monthly: Double; var on: Bool }
struct MoneySettings: Codable, Equatable { var income: Double; var life: Double; var usdRate: Double; var jars: [MoneyJar] }
struct MoneyPlan: Codable, Hashable { let name: String; let done: String?; let interest: Double; let due: String?; let leftAtDue: Double?; let needForDue: Double? }
struct MoneyResult: Codable, Equatable {
    let connected: Bool
    let updatedAt: String?
    let month: MoneyMonth
    let cards: [MoneyCard]
    let pumb: [MoneyCard]
    let debts: [MoneyDebt]
    let total: Double
    let settings: MoneySettings
    let free: Double
    let pay: Double
    let plan: [MoneyPlan]
}

enum MoneyText {
    static let months = ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"]
    static let inMonth = ["січні", "лютому", "березні", "квітні", "травні", "червні", "липні", "серпні", "вересні", "жовтні", "листопаді", "грудні"]

    /// 12 345.6 → «12 346 ₴»
    static func uah(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal; f.groupingSeparator = " "; f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))") + " ₴"
    }

    /// "2027-03" → «до березня 2027»; nil → «понад 10 років»
    static func until(_ ym: String?) -> String {
        guard let ym else { return "понад 10 років" }
        let p = ym.split(separator: "-").compactMap { Int($0) }
        guard p.count >= 2, (1...12).contains(p[1]) else { return ym }
        return "до \(months[p[1] - 1]) \(p[0])"
    }

    /// "2027-08-30" → «30 серпня 2027»
    static func date(_ iso: String?) -> String {
        guard let iso else { return "" }
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return iso }
        return "\(p[2]) \(months[p[1] - 1]) \(p[0])"
    }
}

extension API {
    struct ScriptKey: Decodable { let key: String }
    struct DebtsBody: Encodable { let debts: [MoneyDebt] }
    struct JarSetting: Encodable { let id: String; let monthly: Double; let on: Bool }
    struct MoneySettingsBody: Encodable { let income: Double; let life: Double; let usdRate: Double; let jars: [JarSetting] }

    func money(pay: Double? = nil) async throws -> MoneyResult { try await get(pay.map { "/money?pay=\(Int($0))" } ?? "/money") }
    func newScriptKey() async throws -> String { (try await send("POST", "/me/script-key", Empty()) as ScriptKey).key }
    func setDebts(_ debts: [MoneyDebt]) async throws { try await send("PUT", "/money/debts", DebtsBody(debts: debts)) }
    func setMoneySettings(_ s: MoneySettings) async throws {
        try await send("PUT", "/money/settings", MoneySettingsBody(income: s.income, life: s.life, usdRate: s.usdRate,
                                                                    jars: s.jars.map { JarSetting(id: $0.id, monthly: $0.monthly, on: $0.on) }))
    }
}
