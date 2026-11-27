import Foundation
import ActivityKit
import AppIntents

/// Magic Motion Nyx (NYX_ДИЗАЙН.md, макет nyx_керування.html). Shared by the app and the widget extension:
/// the Live Activity, its buttons and the button of «Пункт керування». The buttons are LiveActivityIntents —
/// iOS runs them in the app's own process, where `NyxHook.run` talks to the toy over Bluetooth.
enum NyxRhythm: String, Codable, CaseIterable, Hashable {
    case steady, wave, pulse, steps
    var title: String {
        switch self {
        case .steady: return "Рівно"
        case .wave: return "Хвиля"
        case .pulse: return "Пульс"
        case .steps: return "Сходинки"
        }
    }
    var next: NyxRhythm {
        let all = NyxRhythm.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
    /// The strength sent to the toy at the moment `t` (in ticks of 0.12 s) for the chosen level.
    func output(level: Int, tick t: Int) -> Int {
        let l = Double(max(0, min(100, level)))
        guard l > 0 else { return 0 }
        switch self {
        case .steady: return Int(l)
        case .wave: return Int((l * (0.55 + 0.45 * sin(Double(t) / 8))).rounded())
        case .pulse: return t % 10 < 3 ? Int(l) : Int((l * 0.2).rounded())
        case .steps: return Int((l * [0.2, 0.4, 0.6, 0.8, 1.0, 0][(t / 15) % 6]).rounded())
        }
    }
}

struct NyxAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var level: Int
        var rhythm: NyxRhythm
        var battery: Int?
        /// «на відстані»: the partner is steering from far away
        var remote: Bool = false
    }
    var name: String
}

enum NyxCmd {
    case step(Int), nextRhythm, stop, power(Bool)
}

/// Set by the app at launch; the widget extension never runs these intents itself.
enum NyxHook {
    static var run: ((NyxCmd) async -> Void)?
    static let onKey = "nyx.on"
    static var isOn: Bool { UserDefaults(suiteName: Shared.group)?.bool(forKey: onKey) ?? false }
}

struct NyxStepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Nyx: сильніше чи слабше"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Крок") var delta: Int
    init() { delta = 10 }
    init(delta: Int) { self.delta = delta }
    func perform() async throws -> some IntentResult {
        await NyxHook.run?(.step(delta))
        return .result()
    }
}

struct NyxRhythmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Nyx: наступний ритм"
    static var isDiscoverable: Bool = false
    func perform() async throws -> some IntentResult {
        await NyxHook.run?(.nextRhythm)
        return .result()
    }
}

struct NyxStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Nyx: стоп"
    static var isDiscoverable: Bool = false
    func perform() async throws -> some IntentResult {
        await NyxHook.run?(.stop)
        return .result()
    }
}

/// «Пункт керування»: on — connect and show the plate with the last strength; off — 0 and disconnect.
@available(iOS 18.0, *)
struct NyxPowerIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Nyx"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Увімкнено") var value: Bool
    func perform() async throws -> some IntentResult {
        await NyxHook.run?(.power(value))
        return .result()
    }
}
