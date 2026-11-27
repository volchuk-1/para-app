import WidgetKit
import SwiftUI
import AppIntents
import ActivityKit

/// Nyx on the lock screen and in the Dynamic Island (макет nyx_керування.html, екрани 1–3):
/// strength (bar + %), rhythm, battery; − · + · Ритм · Стоп — pressed without unlocking.
private let wine = 0x3B1F2B
private let peach = Color(red: 0xF1 / 255, green: 0xC9 / 255, blue: 0xA5 / 255)
private let stopRed = Color(red: 0xD9 / 255, green: 0x4F / 255, blue: 0x5C / 255)

private func rhythmIcon(_ r: NyxRhythm) -> String {
    switch r {
    case .steady: return "minus"
    case .wave: return "water.waves"
    case .pulse: return "waveform.path.ecg"
    case .steps: return "chart.bar.fill"
    }
}

private struct NyxButtons: View {
    let state: NyxAttributes.ContentState
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: NyxStepIntent(delta: -10)) { Image(systemName: "minus").frame(maxWidth: .infinity, minHeight: 38) }
            Button(intent: NyxStepIntent(delta: 10)) { Image(systemName: "plus").frame(maxWidth: .infinity, minHeight: 38) }
            Button(intent: NyxRhythmIntent()) { Image(systemName: rhythmIcon(state.rhythm.next)).frame(maxWidth: .infinity, minHeight: 38) }
            // one button for both: ▶ when quiet (the last strength), ■ when it plays
            Button(intent: NyxPlayPauseIntent()) { Image(systemName: state.level > 0 ? "stop.fill" : "play.fill").frame(maxWidth: .infinity, minHeight: 38) }
                .tint(state.level > 0 ? stopRed : Color(red: 0x52 / 255, green: 0x7A / 255, blue: 0x5C / 255))
        }
        .font(.system(size: 17, weight: .bold))
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(Color.white.opacity(0.16))
        .foregroundStyle(.white)
    }
}

private struct NyxBar: View {
    let level: Int
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(peach).frame(width: max(6, g.size.width * CGFloat(level) / 100))
            }
        }
        .frame(height: 6)
    }
}

private func subtitle(_ s: NyxAttributes.ContentState) -> String {
    var parts = [s.remote ? "на відстані" : s.paused ? "\(s.rhythm.title) — відкрий DaVincit" : s.rhythm.title]
    if let b = s.battery { parts.append("батарея \(b)%") }
    return parts.joined(separator: " · ")
}

struct NyxLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NyxAttributes.self) { context in
            let s = context.state
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex6: wine))
                        .frame(width: 30, height: 30).background(Circle().fill(peach))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Nyx").font(.headline).foregroundStyle(.white)
                        Text(subtitle(s)).font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Text("\(s.level)%").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(peach)
                }
                NyxBar(level: s.level)
                if !s.remote { NyxButtons(state: s) }
            }
            .padding(14)
            .matteCard(wine)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Nyx · \(s.remote ? "на відстані" : s.rhythm.title)", systemImage: "heart.fill")
                        .font(.subheadline.bold()).foregroundStyle(peach).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(s.level)%").font(.title3.bold()).monospacedDigit().foregroundStyle(peach).padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        NyxBar(level: s.level)
                        if !s.remote { NyxButtons(state: s) }
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(peach)
            } compactTrailing: {
                Text("\(s.level)%").monospacedDigit().foregroundStyle(peach)
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(peach)
            }
            .keylineTint(peach)
        }
    }
}

@available(iOS 18.0, *)
struct NyxControlValue: ControlValueProvider {
    var previewValue: Bool { false }
    func currentValue() async throws -> Bool { NyxHook.isOn }
}

/// «Пункт керування»: one button. On — connect and show the plate with the last strength; off — 0 and disconnect.
@available(iOS 18.0, *)
struct NyxControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.volchuk.para.control.nyx", provider: NyxControlValue()) { on in
            ControlWidgetToggle("Nyx", isOn: on, action: NyxPowerIntent()) { isOn in
                Label(isOn ? "увімк." : "вимк.", systemImage: isOn ? "heart.fill" : "heart")
            }
            .tint(peach)
        }
        .displayName("Nyx")
        .description("Підключити й показати плашку Nyx; вимкнути — зупинити й відключити.")
    }
}

private extension Color {
    init(hex6 v: Int) { self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255) }
}
