import WidgetKit
import SwiftUI
import AppIntents

/// Nyx outside the app, beyond the plate: more buttons for «Пункт керування» (they also go to the Lock Screen corners
/// and the Action button), one button per preset, and a widget for the Lock Screen (under the clock) and the Home Screen.
private let wineColor = Color(red: 0x3B / 255, green: 0x1F / 255, blue: 0x2B / 255)
private let peachColor = Color(red: 0xF1 / 255, green: 0xC9 / 255, blue: 0xA5 / 255)

// MARK: - «Пункт керування»

@available(iOS 18.0, *)
struct NyxUpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.volchuk.para.control.nyx.up") {
            ControlWidgetButton(action: NyxStepIntent(delta: 10)) { Label("Nyx +10%", systemImage: "plus.circle.fill") }
        }
        .displayName("Nyx · сильніше")
        .description("+10 %. Якщо Nyx не підключена — підключає.")
    }
}

@available(iOS 18.0, *)
struct NyxDownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.volchuk.para.control.nyx.down") {
            ControlWidgetButton(action: NyxStepIntent(delta: -10)) { Label("Nyx −10%", systemImage: "minus.circle.fill") }
        }
        .displayName("Nyx · слабше")
        .description("−10 %.")
    }
}

@available(iOS 18.0, *)
struct NyxRhythmControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.volchuk.para.control.nyx.rhythm") {
            ControlWidgetButton(action: NyxRhythmIntent()) { Label("Nyx · ритм", systemImage: "water.waves") }
        }
        .displayName("Nyx · ритм")
        .description("Наступний ритм: Рівно → Хвиля → Пульс → Сходинки.")
    }
}

@available(iOS 18.0, *)
struct NyxPlayValue: ControlValueProvider {
    var previewValue: Bool { false }
    func currentValue() async throws -> Bool { let s = NyxState.load(); return s.phase == "on" && s.level > 0 }
}

/// Пуск і стоп однією кнопкою (the same place as the old «стоп»): on — plays the last strength, off — 0.
@available(iOS 18.0, *)
struct NyxStopControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.volchuk.para.control.nyx.stop", provider: NyxPlayValue()) { playing in
            ControlWidgetToggle("Nyx", isOn: playing, action: NyxPlayIntent()) { on in
                Label(on ? "грає" : "пауза", systemImage: on ? "stop.fill" : "play.fill")
            }
            .tint(.green)
        }
        .displayName("Nyx · пуск/стоп")
        .description("Одна кнопка: пуск з останньою силою або стоп.")
    }
}

/// One button = one preset (chosen when the button is added; several buttons — several presets).
@available(iOS 18.0, *)
struct NyxPresetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.volchuk.para.control.nyx.preset", intent: NyxPresetConfig.self) { cfg in
            ControlWidgetButton(action: NyxPresetIntent(preset: cfg.preset)) {
                Label(cfg.preset?.name ?? "Пресет", systemImage: "heart.circle.fill")
            }
        }
        .displayName("Nyx · пресет")
        .description("Обраний пресет: його ритм і налаштування.")
        .promptsForUserConfiguration()
    }
}

// MARK: - the widget: Lock Screen (under the clock) and Home Screen

struct NyxEntry: TimelineEntry {
    let date: Date
    let state: NyxState
}

struct NyxProvider: TimelineProvider {
    func placeholder(in context: Context) -> NyxEntry {
        NyxEntry(date: .now, state: NyxState(phase: "on", level: 40, rhythm: .wave, battery: 72))
    }
    func getSnapshot(in context: Context, completion: @escaping (NyxEntry) -> Void) {
        completion(NyxEntry(date: .now, state: NyxState.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NyxEntry>) -> Void) {
        // the app reloads it on every real change
        completion(Timeline(entries: [NyxEntry(date: .now, state: NyxState.load())], policy: .never))
    }
}

struct NyxWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NyxEntry
    private var s: NyxState { entry.state }
    private var on: Bool { s.phase == "on" }
    private var playing: Bool { on && s.level > 0 }
    private var line: String { on ? "\(s.level)% · \(s.rhythm.title)" : "вимкнено" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryInline:
            Text("Nyx · \(line)")
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            rectangular
        default:
            home
        }
    }

    private var circular: some View {
        Button(intent: NyxPlayPauseIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: 15, weight: .bold))
                    Text(on ? "\(s.level)%" : "Nyx").font(.system(size: 12, weight: .bold)).monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 11, weight: .bold))
                Text("Nyx · \(line)").font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            HStack(spacing: 4) {
                Button(intent: NyxStepIntent(delta: -10)) { Image(systemName: "minus").frame(maxWidth: .infinity, minHeight: 24) }
                Button(intent: NyxStepIntent(delta: 10)) { Image(systemName: "plus").frame(maxWidth: .infinity, minHeight: 24) }
                Button(intent: NyxRhythmIntent()) { Image(systemName: "water.waves").frame(maxWidth: .infinity, minHeight: 24) }
                Button(intent: NyxPlayPauseIntent()) { Image(systemName: playing ? "stop.fill" : "play.fill").frame(maxWidth: .infinity, minHeight: 24) }
            }
            .font(.system(size: 13, weight: .bold))
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.15)))
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "heart.fill").foregroundStyle(peachColor)
                Text("Nyx").font(.headline).foregroundStyle(.white)
                Spacer()
                if let b = s.battery { Text("\(b)%").font(.caption2).foregroundStyle(.white.opacity(0.7)) }
            }
            Text(on ? "\(s.level)%" : "вимк.").font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(peachColor)
            Text(on ? s.rhythm.title : "+ — підключити").font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button(intent: NyxStepIntent(delta: -10)) { Image(systemName: "minus").frame(maxWidth: .infinity, minHeight: 30) }
                Button(intent: NyxStepIntent(delta: 10)) { Image(systemName: "plus").frame(maxWidth: .infinity, minHeight: 30) }
                Button(intent: NyxPlayPauseIntent()) { Image(systemName: playing ? "stop.fill" : "play.fill").frame(maxWidth: .infinity, minHeight: 30) }
            }
            .font(.system(size: 14, weight: .bold))
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .containerBackground(for: .widget) { wineColor }
    }
}

struct NyxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nyx", provider: NyxProvider()) { entry in
            NyxWidgetView(entry: entry)
        }
        .configurationDisplayName("Nyx")
        .description("Сила й ритм; −, +, ритм, стоп — просто з екрана блокування.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall])
    }
}

/// Everything of Nyx in one group (the main bundle takes it as one item).
struct NyxWidgets: WidgetBundle {
    var body: some Widget {
        NyxLiveActivity()
        NyxWidget()
        if #available(iOS 18.0, *) {
            NyxControl()
            NyxUpControl()
            NyxDownControl()
            NyxRhythmControl()
            NyxStopControl()
            NyxPresetControl()
        }
    }
}
