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
    /// The strength sent to the toy `t` seconds after the start, for the chosen level and the settings.
    func output(level: Int, at t: Double, tune: NyxTune) -> Int {
        let l = Double(max(0, min(100, level)))
        guard l > 0 else { return 0 }
        let lo = tune.low
        switch self {
        case .steady: return Int(l)
        case .wave: return Int((l * (lo + (1 - lo) * (0.5 + 0.5 * sin(2 * .pi * t / tune.wave)))).rounded())
        case .pulse: return t.truncatingRemainder(dividingBy: tune.pulse) / tune.pulse < tune.duty ? Int(l) : Int((l * lo).rounded())
        case .steps: return Int((l * [0.2, 0.4, 0.6, 0.8, 1.0, 0][Int(t / tune.steps) % 6]).rounded())
        }
    }
}

/// The settings of the rhythms (the screen «Nyx» → «Налаштувати»): how long a wave is, how fast the pulse beats and how
/// long a beat lasts, how long a step is, and how low the wave and the pulse go. Kept on this phone only.
struct NyxTune: Codable, Hashable {
    var wave: Double = 6      // seconds, one whole wave
    var pulse: Double = 1.2   // seconds, one beat and its pause
    var duty: Double = 0.3    // share of the beat that is strong
    var steps: Double = 1.8   // seconds on one step
    var low: Double = 0.2     // the lowest point of the wave and the pulse, share of the strength

    /// Anything from the page: missing or silly numbers fall back to what is sane.
    init(_ d: [String: Any] = [:]) {
        func n(_ k: String, _ lo: Double, _ hi: Double, _ def: Double) -> Double {
            guard let v = (d[k] as? NSNumber)?.doubleValue, v.isFinite else { return def }
            return min(hi, max(lo, v))
        }
        wave = n("wave", 1, 30, 6); pulse = n("pulse", 0.25, 5, 1.2); duty = n("duty", 0.1, 0.9, 0.3)
        steps = n("steps", 0.4, 10, 1.8); low = n("low", 0, 0.9, 0.2)
    }
    var dict: [String: Any] { ["wave": wave, "pulse": pulse, "duty": duty, "steps": steps, "low": low] }

    static let key = "nyx.tune"
    static func load() -> NyxTune {
        guard let d = UserDefaults(suiteName: Shared.group)?.dictionary(forKey: key) else { return NyxTune() }
        return NyxTune(d)
    }
    func save() { UserDefaults(suiteName: Shared.group)?.set(dict, forKey: Self.key) }
}

struct NyxAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var level: Int
        var rhythm: NyxRhythm
        var battery: Int?
        /// «на відстані»: the partner is steering from far away
        var remote: Bool = false
        /// the rhythm waits for the app to be opened (iOS ended the background time); the strength stays steady
        var paused: Bool = false
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
