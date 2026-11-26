import WidgetKit
import SwiftUI

// «Календар» on the home screen (large, also medium): the week as a strip with dots, then the next events by day.
// Made for both looks of iOS: in full colour — a dark olive card; when the home screen is clear or tinted, iOS takes the
// background away and paints everything in one colour — then the text stands on its own and the accents
// (today, the dots, the times) are marked `widgetAccentable`, so they keep the tint.

struct CalItem: Hashable {
    let title: String
    let start: Date
    let end: Date?
    let place: String?
    let who: String      // "us" · "me" · "partner"
}

struct CalEntry: TimelineEntry {
    let date: Date
    var items: [CalItem]
    var busyDays: Set<Int>    // day offsets 0…6 from today that have something
    var signedIn: Bool
}

struct CalProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalEntry {
        let now = Date()
        return CalEntry(date: now, items: [
            CalItem(title: "Вечеря на даху", start: now.addingTimeInterval(3 * 3600), end: nil, place: "Республіка", who: "us"),
            CalItem(title: "Пілатес + йога", start: now.addingTimeInterval(27 * 3600), end: nil, place: nil, who: "partner"),
            CalItem(title: "Кіно: Дюна 3", start: now.addingTimeInterval(52 * 3600), end: nil, place: "Multiplex", who: "us"),
        ], busyDays: [0, 1, 2], signedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalEntry) -> Void) { completion(placeholder(in: context)) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalEntry>) -> Void) {
        Task {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let to = cal.date(byAdding: .day, value: 21, to: today) ?? today
            let f = ISO8601DateFormatter()
            var entry = CalEntry(date: .now, items: [], busyDays: [], signedIn: KeyStore.deviceKey != nil)
            if let d = await WidgetAPI.json("events?from=\(f.string(from: today))&to=\(f.string(from: to))"), let list = d["events"] as? [[String: Any]] {
                let me = KeyStore.cachedMe?.me.id
                var items: [CalItem] = []
                for e in list {
                    guard let start = WidgetAPI.date(e["startsAt"] as? String) else { continue }
                    let end = WidgetAPI.date(e["endsAt"] as? String)
                    if (end ?? start.addingTimeInterval(2 * 3600)) < Date() { continue }
                    let owner = e["ownerId"] as? String
                    let inv = e["invitation"] as? [String: Any]
                    let status = inv?["status"] as? String
                    if status == "cancelled" { continue }
                    let who = owner == nil ? "us" : owner == me ? "me" : "partner"
                    items.append(CalItem(title: e["title"] as? String ?? "Подія", start: start, end: end, place: e["place"] as? String, who: status == "accepted" ? "us" : who))
                }
                items.sort { $0.start < $1.start }
                entry.items = items
                for it in items {
                    let off = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: it.start)).day ?? -1
                    if (0...6).contains(off) { entry.busyDays.insert(off) }
                }
            }
            // refresh at the next event's end, at midnight, or in 30 min — whichever is first
            let midnight = cal.date(byAdding: .day, value: 1, to: today) ?? Date().addingTimeInterval(3600)
            let next = min(Date().addingTimeInterval(30 * 60), midnight)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

private let olive = Color(hex: 0x1E241B)
private let olive2 = Color(hex: 0x2A3326)
private let cream = Color(hex: 0xECE9DF)
private let sage = Color(hex: 0xA8B99B)
private let rose = Color(hex: 0xD59BAC)
private let blue = Color(hex: 0x7FA6D1)
private let warm = Color(hex: 0xD9B26F)

struct CalWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    let entry: CalEntry

    private var tinted: Bool { mode != .fullColor }
    private var maxRows: Int { family == .systemLarge ? 7 : 3 }

    private func fmt(_ d: Date, _ p: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "uk_UA")
        f.dateFormat = p
        return f.string(from: d)
    }
    private func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Сьогодні" }
        if cal.isDateInTomorrow(d) { return "Завтра" }
        return fmt(d, "EEEE, d MMMM").capitalized(with: Locale(identifier: "uk_UA"))
    }
    private func dot(_ who: String) -> Color { tinted ? .primary : (who == "us" ? warm : who == "me" ? blue : rose) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if family == .systemLarge { week.padding(.top, 12) }
            Rectangle().fill(.primary.opacity(tinted ? 0.25 : 0.12)).frame(height: 0.5).padding(.vertical, family == .systemLarge ? 12 : 8)
            if !entry.signedIn {
                Text("Відкрий DaVincit, щоб побачити календар").font(.subheadline).opacity(0.8)
            } else if entry.items.isEmpty {
                Text("Попереду вільно — саме час щось запланувати ♥").font(.system(size: 15, design: .serif)).opacity(0.85)
            } else {
                list
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(tinted ? Color.primary : cream)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [olive2, olive], startPoint: .top, endPoint: .bottom)
        }
        .widgetURL(URL(string: "davincit://cal"))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(fmt(entry.date, "d")).font(.system(size: family == .systemLarge ? 34 : 26, weight: .semibold, design: .serif)).widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(fmt(entry.date, "EEEE").capitalized(with: Locale(identifier: "uk_UA"))).font(.system(size: 14, weight: .semibold))
                Text(fmt(entry.date, "LLLL").capitalized(with: Locale(identifier: "uk_UA"))).font(.system(size: 12)).opacity(0.65)
            }
            Spacer()
            Text("КАЛЕНДАР").font(.system(size: 10, weight: .semibold)).tracking(1.6).opacity(0.6)
        }
    }

    private var week: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: entry.date)
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let d = cal.date(byAdding: .day, value: i, to: today) ?? today
                VStack(spacing: 4) {
                    Text(fmt(d, "EEEEEE").lowercased()).font(.system(size: 10, weight: .semibold)).opacity(0.55)
                    ZStack {
                        if i == 0 {
                            Circle().fill(tinted ? Color.primary.opacity(0.22) : sage.opacity(0.28)).frame(width: 30, height: 30).widgetAccentable()
                        }
                        Text(fmt(d, "d")).font(.system(size: 15, weight: i == 0 ? .bold : .medium, design: .serif))
                    }
                    .frame(height: 30)
                    Circle().fill(entry.busyDays.contains(i) ? (tinted ? Color.primary : sage) : .clear).frame(width: 5, height: 5).widgetAccentable()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var list: some View {
        let shown = Array(entry.items.prefix(maxRows))
        let groups = Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.start) }.sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 6) {
            ForEach(groups, id: \.key) { day, items in
                VStack(alignment: .leading, spacing: 5) {
                    Text(dayTitle(day).uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2).opacity(0.6)
                    ForEach(items, id: \.self) { it in
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 2).fill(dot(it.who)).frame(width: 3, height: family == .systemLarge ? 30 : 22).widgetAccentable()
                            Text(fmt(it.start, "HH:mm")).font(.system(size: 14, weight: .semibold)).monospacedDigit().widgetAccentable()
                            VStack(alignment: .leading, spacing: 0) {
                                Text(it.title).font(.system(size: 14.5, weight: .medium)).lineLimit(1)
                                if family == .systemLarge, let p = it.place, !p.isEmpty {
                                    Text(p).font(.system(size: 11.5)).opacity(0.6).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            if entry.items.count > maxRows {
                Text("і ще \(entry.items.count - maxRows)").font(.system(size: 11.5)).opacity(0.55)
            }
        }
    }
}

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "calendar", provider: CalProvider()) { entry in
            CalWidgetView(entry: entry)
        }
        .configurationDisplayName("Календар")
        .description("Тиждень і найближчі наші події.")
        .supportedFamilies([.systemLarge, .systemMedium])
    }
}
