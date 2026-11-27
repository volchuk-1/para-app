import Foundation
import ActivityKit
import AppIntents

/// Magic Motion Nyx (NYX_ДИЗАЙН.md, макет nyx_керування.html). Shared by the app and the widget extension:
/// the Live Activity, its buttons and the button of «Пункт керування». The buttons are LiveActivityIntents —
/// iOS runs them in the app's own process, where `NyxHook.run` talks to the toy over Bluetooth.
enum NyxRhythm: String, Codable, CaseIterable, Hashable {
    case steady, wave, pulse, steps, build, random, custom, music, tilt
    var title: String {
        switch self {
        case .steady: return "Рівно"
        case .wave: return "Хвиля"
        case .pulse: return "Пульс"
        case .steps: return "Сходинки"
        case .build: return "Наростання"
        case .random: return "Випадковий"
        case .custom: return "Свій"
        case .music: return "Під музику"
        case .tilt: return "Нахил"
        }
    }
    /// «Ритм» on the plate goes round these (music and the tilt need the app open; «Свій» — when one is drawn).
    static let round: [NyxRhythm] = [.steady, .wave, .pulse, .steps, .build, .random, .custom]
    var next: NyxRhythm {
        let all = NyxRhythm.round
        guard let i = all.firstIndex(of: self) else { return .steady }
        return all[(i + 1) % all.count]
    }
    /// The music and the tilt listen to the phone itself: only with the app open.
    var live: Bool { self == .music || self == .tilt }

    /// A number in 0…1 for the n-th moment of «Випадковий» (the same on the page: web/v37.js).
    static func rnd(_ n: Int) -> Double {
        let x = sin(Double(n) * 12.9898 + 78.233) * 43758.5453
        return abs(x - x.rounded(.down))
    }

    /// The strength sent to the toy `t` seconds after the rhythm began, for the chosen level and the settings;
    /// `env` (0…1) is what the microphone hears or how the phone is tilted.
    func output(level: Int, at t: Double, tune: NyxTune, env: Double = 1) -> Int {
        let l = Double(max(0, min(100, level)))
        guard l > 0 else { return 0 }
        let lo = tune.low
        let v: Double
        switch self {
        case .steady: v = l
        case .wave: v = l * (lo + (1 - lo) * (0.5 + 0.5 * sin(2 * .pi * t / tune.wave)))
        case .pulse: v = t.truncatingRemainder(dividingBy: tune.pulse) / tune.pulse < tune.duty ? l : l * lo
        case .steps: v = l * [0.2, 0.4, 0.6, 0.8, 1.0, 0][Int(t / tune.steps) % 6]
        case .build: v = l * min(1, lo + (1 - lo) * t / tune.build)
        case .random:
            let x = t / tune.random, n = Int(x), f = x - Double(n)
            let a = Self.rnd(n), b = Self.rnd(n + 1), k = f * f * (3 - 2 * f)
            v = l * (lo + (1 - lo) * (a + (b - a) * k))
        case .custom:
            guard let p = tune.pattern, !p.isEmpty else { v = l; break }
            v = l * p[Int(t / NyxTune.patternStep) % p.count]
        case .music, .tilt: v = l * (lo + (1 - lo) * max(0, min(1, env)))
        }
        return Int(max(0, min(100, v)).rounded())
    }
}

/// The settings of the rhythms (the screen «Nyx»): how long a wave is, how fast the pulse beats and how long a beat
/// lasts, how long a step is, how long the rise takes, how often «Випадковий» changes, the drawn rhythm, and how low
/// the rhythms go. Kept on this phone only (and for a far toy, sent along with the command).
struct NyxTune: Codable, Hashable {
    var wave: Double = 6      // seconds, one whole wave
    var pulse: Double = 1.2   // seconds, one beat and its pause
    var duty: Double = 0.3    // share of the beat that is strong
    var steps: Double = 1.8   // seconds on one step
    var low: Double = 0.2     // the lowest point, share of the strength
    var build: Double = 300   // seconds from «low» to the full strength
    var random: Double = 2    // seconds between two random points
    var pattern: [Double]?    // «Свій»: one value (0…1) every 0.05 s
    static let patternStep = 0.05

    /// Anything from the page: missing or silly numbers fall back to what is sane.
    init(_ d: [String: Any] = [:]) {
        func n(_ k: String, _ lo: Double, _ hi: Double, _ def: Double) -> Double {
            guard let v = (d[k] as? NSNumber)?.doubleValue, v.isFinite else { return def }
            return min(hi, max(lo, v))
        }
        wave = n("wave", 1, 30, 6); pulse = n("pulse", 0.25, 5, 1.2); duty = n("duty", 0.1, 0.9, 0.3)
        steps = n("steps", 0.4, 10, 1.8); low = n("low", 0, 0.9, 0.2)
        build = n("build", 30, 1800, 300); random = n("random", 0.5, 10, 2)
        if let raw = d["pattern"] as? [Any] {
            let p = raw.prefix(400).compactMap { ($0 as? NSNumber)?.doubleValue }.map { min(1, max(0, $0.isFinite ? $0 : 0)) }
            pattern = p.isEmpty ? nil : p
        }
    }
    var dict: [String: Any] {
        var d: [String: Any] = ["wave": wave, "pulse": pulse, "duty": duty, "steps": steps, "low": low, "build": build, "random": random]
        if let pattern { d["pattern"] = pattern }
        return d
    }

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
        /// the timer: the toy stops at this moment
        var endsAt: Date? = nil
        /// the preset that plays (its name), if one was chosen
        var preset: String? = nil
    }
    var name: String
}

enum NyxCmd {
    case step(Int), nextRhythm, stop, power(Bool), preset(String), playPause, play(Bool), nextPreset
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

// MARK: - presets (the screen keeps them; the buttons outside the app read them from here)

struct NyxPreset: Codable, Hashable {
    var id: String
    var name: String
    var rhythm: NyxRhythm
    var level: Int?
    var tune: NyxTune
}

enum NyxPresets {
    /// The same five as on the screen (web/v37.js PRESETS0), with the same ids.
    static let builtIn: [NyxPreset] = [
        NyxPreset(id: "b0", name: "Повільна хвиля", rhythm: .wave, level: nil, tune: NyxTune(["wave": 14.0, "low": 0.1])),
        NyxPreset(id: "b1", name: "Швидка хвиля", rhythm: .wave, level: nil, tune: NyxTune(["wave": 2.5, "low": 0.3])),
        NyxPreset(id: "b2", name: "Серце", rhythm: .pulse, level: nil, tune: NyxTune(["pulse": 0.85, "duty": 0.25, "low": 0.3])),
        NyxPreset(id: "b3", name: "Швидкий пульс", rhythm: .pulse, level: nil, tune: NyxTune(["pulse": 0.4, "duty": 0.4, "low": 0.1])),
        NyxPreset(id: "b4", name: "Драбина", rhythm: .steps, level: nil, tune: NyxTune(["steps": 1.0])),
        NyxPreset(id: "b5", name: "Прибій", rhythm: .wave, level: nil, tune: NyxTune(["wave": 9.0, "low": 0.05])),
        NyxPreset(id: "b6", name: "Шторм", rhythm: .wave, level: nil, tune: NyxTune(["wave": 1.5, "low": 0.5])),
        NyxPreset(id: "b7", name: "Тремтіння", rhythm: .pulse, level: nil, tune: NyxTune(["pulse": 0.3, "duty": 0.5, "low": 0.6])),
        NyxPreset(id: "b8", name: "Метроном", rhythm: .pulse, level: nil, tune: NyxTune(["pulse": 1.0, "duty": 0.5, "low": 0.0])),
        NyxPreset(id: "b9", name: "Дражнилка", rhythm: .pulse, level: nil, tune: NyxTune(["pulse": 4.0, "duty": 0.25, "low": 0.0])),
        NyxPreset(id: "b10", name: "Довгі сходи", rhythm: .steps, level: nil, tune: NyxTune(["steps": 4.0])),
    ]
    static let key = "nyx.presets"
    static func mine() -> [NyxPreset] {
        guard let d = UserDefaults(suiteName: Shared.group)?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([NyxPreset].self, from: d)) ?? []
    }
    static func all() -> [NyxPreset] { builtIn + mine() }
    static func find(_ id: String) -> NyxPreset? { all().first { $0.id == id } }
    /// From the page: [{id, name, rhythm, level, tune}]
    static func save(page list: [[String: Any]]) {
        let items: [NyxPreset] = list.prefix(12).compactMap { x in
            guard let id = x["id"] as? String, let name = x["name"] as? String, let r = NyxRhythm(rawValue: x["rhythm"] as? String ?? "") else { return nil }
            return NyxPreset(id: id, name: String(name.prefix(24)), rhythm: r, level: (x["level"] as? NSNumber)?.intValue, tune: NyxTune(x["tune"] as? [String: Any] ?? [:]))
        }
        if let d = try? JSONEncoder().encode(items) { UserDefaults(suiteName: Shared.group)?.set(d, forKey: key) }
    }
}

struct NyxPresetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Пресет Nyx"
    static var defaultQuery = NyxPresetQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(id: String, name: String) { self.id = id; self.name = name }
    init(_ p: NyxPreset) { id = p.id; name = p.name }
}

struct NyxPresetQuery: EntityQuery {
    init() {}
    func entities(for identifiers: [String]) async throws -> [NyxPresetEntity] {
        NyxPresets.all().filter { identifiers.contains($0.id) }.map { NyxPresetEntity($0) }
    }
    func suggestedEntities() async throws -> [NyxPresetEntity] { NyxPresets.all().map { NyxPresetEntity($0) } }
    func defaultResult() async -> NyxPresetEntity? { NyxPresets.builtIn.first.map { NyxPresetEntity($0) } }
}

/// One preset: its rhythm, its settings and (for one of mine) its strength; the toy connects first if needed.
struct NyxPresetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Nyx: пресет"
    @Parameter(title: "Пресет") var preset: NyxPresetEntity?
    init() {}
    init(preset: NyxPresetEntity?) { self.preset = preset }
    func perform() async throws -> some IntentResult {
        if let id = preset?.id { await NyxHook.run?(.preset(id)) }
        return .result()
    }
}

/// «Пункт керування» → «Nyx · пресет»: which preset this button plays (chosen when the button is added).
@available(iOS 18.0, *)
struct NyxPresetConfig: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Пресет Nyx"
    @Parameter(title: "Пресет") var preset: NyxPresetEntity?
    init() {}
    func perform() async throws -> some IntentResult { .result() }
}

/// What the widgets and the buttons show: written by the app on every real change.
struct NyxState {
    var phase = "off"
    var level = 0
    var rhythm: NyxRhythm = .steady
    var battery: Int?
    static let key = "nyx.state"
    static func load() -> NyxState {
        let d = UserDefaults(suiteName: Shared.group)?.dictionary(forKey: key) ?? [:]
        var s = NyxState()
        s.phase = d["phase"] as? String ?? "off"
        s.level = (d["level"] as? NSNumber)?.intValue ?? 0
        s.rhythm = NyxRhythm(rawValue: d["rhythm"] as? String ?? "") ?? .steady
        s.battery = (d["battery"] as? NSNumber)?.intValue
        return s
    }
}

/// The round Lock Screen widget: «стоп» while it plays, «+10 %» (connecting first) while it does not.
struct NyxTapIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Nyx: стоп або сильніше"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Стоп") var stop: Bool
    init() { stop = true }
    init(stop: Bool) { self.stop = stop }
    func perform() async throws -> some IntentResult {
        await NyxHook.run?(stop ? .stop : .step(10))
        return .result()
    }
}

/// One button for both: plays (the last strength) when it is quiet, stops when it plays. Its look follows.
struct NyxPlayPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Nyx: пуск або стоп"
    func perform() async throws -> some IntentResult {
        await NyxHook.run?(.playPause)
        return .result()
    }
}

/// «Пункт керування»: the same as a switch (on — plays, off — stops).
@available(iOS 18.0, *)
struct NyxPlayIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Nyx: пуск/стоп"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Грає") var value: Bool
    func perform() async throws -> some IntentResult {
        await NyxHook.run?(.play(value))
        return .result()
    }
}

/// The plate: the next preset (all of them in a row — the ready ones, then mine).
struct NyxNextPresetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Nyx: наступний пресет"
    static var isDiscoverable: Bool = false
    func perform() async throws -> some IntentResult {
        await NyxHook.run?(.nextPreset)
        return .result()
    }
}
