import WidgetKit
import SwiftUI
import AppIntents
import UIKit

// The widgets of DaVincit (approved concept «віджети»): «Сьогодні», the last photo from the partner, the boiler.
// They ask our own server with the device key of the app; nothing else leaves the phone.

enum WidgetAPI {
    static func json(_ path: String, method: String = "GET", body: [String: Any]? = nil) async -> [String: Any]? {
        guard let key = KeyStore.deviceKey else { return nil }
        var req = URLRequest(url: KeyStore.serverURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 10
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return nil }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard code < 300 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// A protected photo, made small enough for a widget.
    static func image(_ address: String, side: CGFloat) async -> UIImage? {
        guard let key = KeyStore.deviceKey, let url = URL(string: address) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req), let full = UIImage(data: data) else { return nil }
        let k = min(1, side / max(full.size.width, full.size.height, 1))
        let size = CGSize(width: max(1, full.size.width * k), height: max(1, full.size.height * k))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in full.draw(in: CGRect(origin: .zero, size: size)) }
    }

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

private let wOlive = Color(hex: 0x525E4F)
private let wCream = Color(hex: 0xF2EEE2)

// MARK: - «Сьогодні»: what is next, how the tasks go

struct TodayEntry: TimelineEntry {
    let date: Date
    var title: String
    var when: Date?
    var tasks: String
    var days: Int
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, title: "Вечеря на даху", when: Date().addingTimeInterval(3 * 3600), tasks: "2/5", days: 412)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        Task {
            var entry = TodayEntry(date: .now, title: "Попереду вільно", when: nil, tasks: "—", days: 0)
            if let d = await WidgetAPI.json("dashboard") {
                if let next = d["next"] as? [String: Any] {
                    entry.title = next["title"] as? String ?? entry.title
                    entry.when = WidgetAPI.date(next["startsAt"] as? String)
                }
                if let t = d["tasks"] as? [String: Any], let done = t["done"] as? Int, let total = t["total"] as? Int {
                    entry.tasks = "\(done)/\(total)"
                }
                entry.days = d["daysTogether"] as? Int ?? 0
            } else if KeyStore.deviceKey == nil {
                entry.title = "Відкрий DaVincit"
            }
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(20 * 60))))
        }
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var whenText: String {
        guard let w = entry.when else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "uk_UA")
        f.dateFormat = Calendar.current.isDateInToday(w) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: w)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.when == nil ? entry.title : "\(whenText) · \(entry.title)")
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.headline).lineLimit(1)
                Text(entry.when == nil ? "справи \(entry.tasks)" : "\(whenText) · справи \(entry.tasks)").font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("СЬОГОДНІ").font(.system(size: 10, weight: .semibold)).tracking(1.6).opacity(0.7)
                Text(entry.title).font(.system(size: family == .systemSmall ? 19 : 22, weight: .semibold, design: .serif)).lineLimit(3).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    if entry.when != nil { Text(whenText).font(.system(size: 22, weight: .semibold, design: .serif)).monospacedDigit() }
                    Spacer(minLength: 0)
                    Label(entry.tasks, systemImage: "checkmark").font(.caption.weight(.semibold)).opacity(0.85)
                    if family != .systemSmall && entry.days > 0 {
                        Label("\(entry.days)", systemImage: "heart.fill").font(.caption.weight(.semibold)).opacity(0.85)
                    }
                }
            }
            .foregroundStyle(wCream)
            .containerBackground(for: .widget) { wOlive }
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Сьогодні")
        .description("Найближча подія і справи на день.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - the last photo from the partner («Миттєвість»)

struct PhotoEntry: TimelineEntry {
    let date: Date
    var image: UIImage?
    var text: String
    var who: String
    var at: Date?
}

struct PhotoProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhotoEntry {
        PhotoEntry(date: .now, image: nil, text: "Тут буде фото", who: "", at: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> Void) {
        Task {
            var entry = PhotoEntry(date: .now, image: nil, text: "Тут буде фото", who: "", at: nil)
            if let d = await WidgetAPI.json("dashboard") {
                entry.who = (d["partner"] as? [String: Any])?["name"] as? String ?? ""
                if let n = d["note"] as? [String: Any] {
                    entry.text = n["text"] as? String ?? ""
                    entry.at = WidgetAPI.date(n["at"] as? String)
                    if let u = n["photoUrl"] as? String { entry.image = await WidgetAPI.image(u, side: 600) }
                    if entry.image == nil && entry.text.isEmpty { entry.text = "Тут буде фото" }
                }
            }
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}

struct PhotoWidgetView: View {
    let entry: PhotoEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            if !entry.text.isEmpty { Text(entry.text).font(.system(size: 13, weight: .semibold)).lineLimit(2) }
            if let at = entry.at {
                (Text(entry.who.isEmpty ? "" : "\(entry.who) · ") + Text(at, style: .relative)).font(.system(size: 10.5)).opacity(0.85).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .widgetURL(URL(string: "davincit://moment"))
        .containerBackground(for: .widget) {
            ZStack {
                Color(hex: 0x91798F)
                if let image = entry.image {
                    Image(uiImage: image).resizable().scaledToFill()
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                }
            }
        }
    }
}

struct PartnerPhotoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "moment", provider: PhotoProvider()) { entry in
            PhotoWidgetView(entry: entry)
        }
        .configurationDisplayName("Миттєвість")
        .description("Останнє фото, яке тобі надіслали.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

// MARK: - the boiler: its state and a button that switches it

struct BoilerToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "Перемкнути котел"

    func perform() async throws -> some IntentResult {
        _ = await WidgetAPI.json("boiler", method: "POST", body: ["action": "toggle"])
        WidgetCenter.shared.reloadTimelines(ofKind: "boiler")
        return .result()
    }
}

struct BoilerEntry: TimelineEntry {
    let date: Date
    var configured: Bool
    var online: Bool
    var on: Bool
    var watts: Double
    var until: Date?
}

struct BoilerProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoilerEntry {
        BoilerEntry(date: .now, configured: true, online: true, on: false, watts: 0, until: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BoilerEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoilerEntry>) -> Void) {
        Task {
            var entry = BoilerEntry(date: .now, configured: false, online: false, on: false, watts: 0, until: nil)
            if let b = await WidgetAPI.json("boiler") {
                entry.configured = b["configured"] as? Bool ?? false
                entry.online = (b["online"] as? Bool ?? true) && b["error"] == nil
                entry.on = b["on"] as? Bool ?? false
                entry.watts = b["watts"] as? Double ?? 0
                if let left = b["countdown"] as? Double, left > 0 { entry.until = Date().addingTimeInterval(left) }
            }
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(10 * 60))))
        }
    }
}

struct BoilerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BoilerEntry

    private var state: String {
        if !entry.configured { return "Не підключено" }
        if !entry.online { return "Офлайн" }
        return entry.on ? "Гріє" : "Вимкнено"
    }

    var body: some View {
        if family == .accessoryCircular { lock } else { home }
    }

    /// The lock screen: one round button that switches the boiler.
    private var lock: some View {
        Button(intent: BoilerToggleIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.on ? "flame.fill" : "power").font(.system(size: 20, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("КОТЕЛ").font(.system(size: 10, weight: .semibold)).tracking(1.6).opacity(0.7)
            Text(state).font(.system(size: 21, weight: .semibold, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
            if let until = entry.until, entry.on {
                Text(timerInterval: Date.countdown(to: until), countsDown: true).font(.caption).monospacedDigit().opacity(0.85)
            } else if entry.on && entry.watts > 0 {
                Text(String(format: "%.1f кВт", entry.watts / 1000).replacingOccurrences(of: ".", with: ",")).font(.caption).opacity(0.85)
            }
            Spacer(minLength: 0)
            if entry.configured && entry.online {
                Button(intent: BoilerToggleIntent()) {
                    Label(entry.on ? "Вимкнути" : "Увімкнути", systemImage: "power")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            // warm while it heats, dark blue when it is off
            entry.on && entry.online ? Color(hex: 0xB4501F) : Color(hex: 0x1F2A44)
        }
    }
}

struct BoilerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "boiler", provider: BoilerProvider()) { entry in
            BoilerWidgetView(entry: entry)
        }
        .configurationDisplayName("Котел")
        .description("Стан котла і кнопка, що його перемикає.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: - quick starts for the lock screen: a voice note, a photo for the other one

struct QuickEntry: TimelineEntry { let date: Date }

struct QuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) { completion(QuickEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
        completion(Timeline(entries: [QuickEntry(date: .now)], policy: .never))
    }
}

struct QuickView: View {
    @Environment(\.widgetFamily) private var family
    let icon: String
    let title: String
    let link: String
    let color: Color

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                }
                .containerBackground(for: .widget) { Color.clear }
            } else {
                VStack(alignment: .leading) {
                    Image(systemName: icon).font(.system(size: 30, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(title).font(.system(size: 19, weight: .semibold, design: .serif)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .foregroundStyle(.white)
                .containerBackground(for: .widget) { color }
            }
        }
        .widgetURL(URL(string: link))
    }
}

struct VoiceNoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "voicenote", provider: QuickProvider()) { _ in
            QuickView(icon: "mic.fill", title: "Нотатка голосом", link: "davincit://note", color: Color(hex: 0x5B7E98))
        }
        .configurationDisplayName("Нотатка голосом")
        .description("Одразу починає запис.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct SnapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "snap", provider: QuickProvider()) { _ in
            QuickView(icon: "camera.fill", title: "Миттєвість", link: "davincit://snap", color: Color(hex: 0xA97B60))
        }
        .configurationDisplayName("Зняти миттєвість")
        .description("Фото з підписом для другої половини.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
