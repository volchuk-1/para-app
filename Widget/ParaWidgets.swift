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

/// Matte cards on the lock screen: our own even colour fills the card, and the system tint under it is a darker shade of
/// the same colour — iOS draws a light rim from that tint, so a dark tint keeps the edge from glowing.
enum Matte {
    static func color(_ v: Int, _ k: Double = 1) -> Color {
        Color(red: Double((v >> 16) & 255) / 255 * k, green: Double((v >> 8) & 255) / 255 * k, blue: Double(v & 255) / 255 * k)
    }
}
extension View {
    func matteCard(_ hex: Int) -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Matte.color(hex))
            .activityBackgroundTint(Matte.color(hex, 0.55))
    }
}

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
            .matteCard(0x4B5E3A)
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

    /// The colour of this kind of date (the same as in the pages): Кіно — burgundy, a dinner — terracotta …
    static func tint(_ title: String) -> Color { Matte.color(hexOf(title)) }
    static func hexOf(_ title: String) -> Int {
        let t = title.lowercased()
        func hex(_ v: Int) -> Int { v }
        if t.hasPrefix("кіно") || t.contains("сеанс") { return hex(0x790C12) }
        if ["вечер", "ресторан", "кафе", "кава", "сніданок", "обід"].contains(where: t.contains) { return hex(0x8C4A2F) }
        if ["прогулян", "парк", "гори", "похід"].contains(where: t.contains) { return hex(0x3F5A34) }
        if ["поїздк", "подорож", "відпустк"].contains(where: t.contains) { return hex(0x2F5F86) }
        if ["концерт", "театр", "виставк", "музей"].contains(where: t.contains) { return hex(0x4A3B6B) }
        if t.contains("вдома") { return hex(0x7A4F6A) }
        return hex(0x6E3039)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DateAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "heart.fill").font(.title2).foregroundStyle(cream)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.headline).foregroundStyle(cream).lineLimit(1)
                    if let who = context.state.partner, !who.isEmpty {
                        Text(who).font(.caption.weight(.semibold)).foregroundStyle(cream).lineLimit(1)
                    } else if !context.attributes.place.isEmpty {
                        Text(context.attributes.place).font(.caption).foregroundStyle(cream.opacity(0.8)).lineLimit(1)
                    }
                }
                Spacer()
                Text(timerInterval: Date.countdown(to: context.state.startsAt), countsDown: true).opacity(context.isStale ? 0 : 1).overlay { if context.isStale { Text("Час іти ❤").fixedSize() } }
                    .monospacedDigit().font(.title2.bold()).foregroundStyle(cream)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 110)
            }
            .padding()
            // matte: one even colour of the kind of date, no light at the edges
            .matteCard(Self.hexOf(context.attributes.title))
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
                    if let who = context.state.partner, !who.isEmpty { Text(who).font(.caption.weight(.semibold)) }
                    else if !context.attributes.place.isEmpty { Text(context.attributes.place).font(.caption) }
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(Self.tint(context.attributes.title).opacity(1)).brightness(0.25)
            } compactTrailing: {
                // the whole «2:17:39» fits: a smaller, fixed-width font and a wider place
                Text(timerInterval: Date.countdown(to: context.state.startsAt), countsDown: true)
                    .opacity(context.isStale ? 0 : 1).overlay { if context.isStale { Text("Час ❤").fixedSize() } }
                    .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.trailing).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 68, alignment: .trailing)
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(Self.tint(context.attributes.title)).brightness(0.25)
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
            .matteCard(0x4B5E3A)
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
        TodayWidget()
        CalendarWidget()
        PartnerPhotoWidget()
        BoilerWidget()
        VoiceNoteWidget()
        SnapWidget()
        PingLiveActivity()
        DateLiveActivity()
        TaskLiveActivity()
        if #available(iOS 18.0, *) {
            VoiceNoteControl()
            MomentControl()
        }
    }
}
