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
            Color(red: 0x4B / 255, green: 0x5E / 255, blue: 0x3A / 255)
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
                Image(systemName: "timer").foregroundStyle(Color(red: 0xF2 / 255, green: 0xEE / 255, blue: 0xE2 / 255))
                Text(context.state.label).font(.headline)
                Spacer()
                Text(timerInterval: Date.countdown(to: context.state.endsAt), countsDown: true).opacity(context.isStale ? 0 : 1).overlay { if context.isStale { Text("Час!") } }
                    .monospacedDigit()
                    .font(.title3.bold())
            }
            .padding()
            .activityBackgroundTint(Color(red: 0x4B / 255, green: 0x5E / 255, blue: 0x3A / 255))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.label, systemImage: "heart.fill")
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.countdown(to: context.state.endsAt), countsDown: true).opacity(context.isStale ? 0 : 1).overlay { if context.isStale { Text("Час!") } }
                        .monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            } compactTrailing: {
                Text(timerInterval: Date.countdown(to: context.state.endsAt), countsDown: true).opacity(context.isStale ? 0 : 1).overlay { if context.isStale { Text("Час!") } }
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
                Text(timerInterval: Date.countdown(to: context.state.startsAt), countsDown: true).opacity(context.isStale ? 0 : 1).overlay { if context.isStale { Text("Час іти ❤").fixedSize() } }
                    .monospacedDigit().font(.title2.bold()).foregroundStyle(cream)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 110)
            }
            .padding()
            .activityBackgroundTint(olive)
            .activitySystemActionForegroundColor(cream)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: "heart.fill")
                        .lineLimit(1).minimumScaleFactor(0.7).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.countdown(to: context.state.startsAt), countsDown: true).opacity(context.isStale ? 0 : 1).overlay { if context.isStale { Text("Час іти ❤").fixedSize() } }.monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.attributes.place.isEmpty { Text(context.attributes.place).font(.caption) }
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            } compactTrailing: {
                Text(timerInterval: Date.countdown(to: context.state.startsAt), countsDown: true).opacity(context.isStale ? 0 : 1).overlay { if context.isStale { Text("Час іти ❤").fixedSize() } }
                    .monospacedDigit().frame(width: 52)
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
        }
    }
}

// MARK: - Activity timer (calendar): olive, counts down to the start, then to the end

struct TaskLiveActivity: Widget {
    private let olive = Color(red: 0x4B / 255, green: 0x5E / 255, blue: 0x3A / 255)
    private let cream = Color(red: 0xF2 / 255, green: 0xEE / 255, blue: 0xE2 / 255)

    @ViewBuilder private func time(_ s: TaskAttributes.ContentState, stale: Bool) -> some View {
        // staleDate = start: before it — countdown to the start; after it — countdown to the end
        if stale { Text(timerInterval: Date.countdown(to: s.endsAt), countsDown: true) }
        else { Text(timerInterval: Date.countdown(to: s.startsAt), countsDown: true) }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "timer").font(.title2).foregroundStyle(olive)
                    .frame(width: 44, height: 44).background(cream, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.headline).foregroundStyle(cream).lineLimit(1)
                    Text(context.isStale ? "до \(context.state.endsAt.formatted(date: .omitted, time: .shortened))" : "почнеться о \(context.state.startsAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(cream.opacity(0.8))
                }
                Spacer()
                time(context.state, stale: context.isStale).monospacedDigit().font(.title2.bold()).foregroundStyle(cream)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 100)
            }
            .padding()
            .activityBackgroundTint(olive)
            .activitySystemActionForegroundColor(cream)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: "timer").foregroundStyle(cream).lineLimit(1).minimumScaleFactor(0.7).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    time(context.state, stale: context.isStale).monospacedDigit().foregroundStyle(cream)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? "до \(context.state.endsAt.formatted(date: .omitted, time: .shortened))" : "почнеться о \(context.state.startsAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(cream.opacity(0.8))
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Color(red: 0x9D / 255, green: 0xB2 / 255, blue: 0x7F / 255))
            } compactTrailing: {
                time(context.state, stale: context.isStale).monospacedDigit().frame(width: 52).foregroundStyle(Color(red: 0x9D / 255, green: 0xB2 / 255, blue: 0x7F / 255))
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Color(red: 0x9D / 255, green: 0xB2 / 255, blue: 0x7F / 255))
            }
            .keylineTint(olive)
        }
    }
}

@main
struct ParaWidgets: WidgetBundle {
    var body: some Widget {
        NoteWidget()
        PingLiveActivity()
        DateLiveActivity()
        TaskLiveActivity()
    }
}
