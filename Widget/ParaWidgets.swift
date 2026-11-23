import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Home screen widget: reads the shared folder and pings the server

struct NoteEntry: TimelineEntry {
    let date: Date
    let note: String
    let server: String
}

struct NoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        NoteEntry(date: .now, note: "…", server: "…")
    }

    func getSnapshot(in context: Context, completion: @escaping (NoteEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NoteEntry>) -> Void) {
        let defaults = UserDefaults(suiteName: Shared.group)
        let note = defaults == nil ? "✗ App Group" : (defaults?.string(forKey: "note") ?? "порожньо")
        var request = URLRequest(url: Shared.server)
        request.timeoutInterval = 8
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let entry = NoteEntry(date: .now, note: note, server: ok ? "сервер ✓" : "сервер ✗")
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
        }.resume()
    }
}

struct NoteWidgetView: View {
    let entry: NoteEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Двоє").font(.caption).foregroundStyle(.secondary)
            Text(entry.note).font(.headline).lineLimit(2)
            Spacer(minLength: 0)
            Text(entry.server).font(.caption2)
            Text(entry.date, style: .time).font(.caption2).foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) {
            Color(red: 0.06, green: 0.08, blue: 0.19)
        }
    }
}

struct NoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "note", provider: NoteProvider()) { entry in
            NoteWidgetView(entry: entry)
        }
        .configurationDisplayName("Двоє")
        .description("Проба віджета")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Live Activity / Dynamic Island

struct PingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PingAttributes.self) { context in
            HStack {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
                Text(context.state.label).font(.headline)
                Spacer()
                Text(timerInterval: Date.countdown(to: context.state.endsAt), countsDown: true)
                    .monospacedDigit()
                    .font(.title3.bold())
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.06, green: 0.08, blue: 0.19))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.label, systemImage: "heart.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.countdown(to: context.state.endsAt), countsDown: true)
                        .monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            } compactTrailing: {
                Text(timerInterval: Date.countdown(to: context.state.endsAt), countsDown: true)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
        }
    }
}

// MARK: - Date countdown (accepted invitation)

struct DateLiveActivity: Widget {
    private let olive = Color(red: 0x4B / 255, green: 0x5E / 255, blue: 0x3A / 255)
    private let cream = Color(red: 0xF2 / 255, green: 0xEE / 255, blue: 0xE2 / 255)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DateAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "heart.fill").font(.title2).foregroundStyle(cream)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.headline).foregroundStyle(cream).lineLimit(1)
                    if !context.attributes.place.isEmpty {
                        Text(context.attributes.place).font(.caption).foregroundStyle(cream.opacity(0.8)).lineLimit(1)
                    }
                }
                Spacer()
                Text(timerInterval: Date.countdown(to: context.state.startsAt), countsDown: true)
                    .monospacedDigit().font(.title2.bold()).foregroundStyle(cream)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 110)
            }
            .padding()
            .activityBackgroundTint(olive)
            .activitySystemActionForegroundColor(cream)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: "heart.fill").lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.countdown(to: context.state.startsAt), countsDown: true).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.attributes.place.isEmpty { Text(context.attributes.place).font(.caption) }
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            } compactTrailing: {
                Text(timerInterval: Date.countdown(to: context.state.startsAt), countsDown: true)
                    .monospacedDigit().frame(width: 52)
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
        }
    }
}

@main
struct ParaWidgets: WidgetBundle {
    var body: some Widget {
        NoteWidget()
        PingLiveActivity()
        DateLiveActivity()
    }
}
