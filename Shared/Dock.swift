import Foundation

/// What the bottom bar shows: the week strip, the nearest event and its short line.
enum Dock {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "uk_UA")
        c.timeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current
        return c
    }

    /// Monday…Sunday of the week that contains `date`.
    static func week(containing date: Date, cal: Calendar = calendar) -> [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// The first event that has not ended yet.
    static func nextEvent(_ events: [Event], now: Date = Date()) -> Event? {
        events
            .filter { ($0.endsAt ?? $0.startsAt.addingTimeInterval(3600)) > now }
            .min { $0.startsAt < $1.startsAt }
    }

    /// «Сьогодні», «Завтра» or «сб, 28».
    static func dayLabel(_ d: Date, now: Date = Date(), cal: Calendar = calendar) -> String {
        if cal.isDate(d, inSameDayAs: now) { return "Сьогодні" }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { return "Завтра" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "uk_UA")
        f.timeZone = cal.timeZone
        f.dateFormat = "EEEEEE, d"
        return f.string(from: d)
    }

    /// «сб, 28 · Кіно о 19:30» — or a calm line when nothing is planned.
    static func nextLine(_ e: Event?, now: Date = Date(), cal: Calendar = calendar) -> String {
        guard let e else { return "Попереду поки вільно" }
        let f = DateFormatter()
        f.timeZone = cal.timeZone
        f.dateFormat = "HH:mm"
        return "\(dayLabel(e.startsAt, now: now, cal: cal)) · \(e.title) о \(f.string(from: e.startsAt))"
    }

    /// Events that start on `day`.
    static func events(_ events: [Event], on day: Date, cal: Calendar = calendar) -> [Event] {
        events.filter { cal.isDate($0.startsAt, inSameDayAs: day) }
    }
}

/// In-app notifications (the same list the Telegram version shows under the bell).
struct AppNotification: Codable, Identifiable, Equatable {
    let id: String
    let kind: String
    let title: String
    let body: String?
    let createdAt: Date
    let read: Bool
}

struct NotificationsResult: Codable, Equatable {
    let items: [AppNotification]
    let unread: Int
}

extension API {
    func notifications() async throws -> NotificationsResult { try await get("/notifications") }
    func markNotificationsRead() async throws { try await send("POST", "/notifications/read", Empty()) }
}

/// «У кіно в Україні з 17 грудня» for movies that are not out yet.
enum Release {
    static func day(_ s: String?) -> Date? {
        guard let s, s.count == 10 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Dock.calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    static func line(_ s: String?, inUkraine: Bool?, now: Date = Date()) -> String? {
        guard let d = day(s), d > Dock.calendar.startOfDay(for: now) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "uk_UA")
        f.timeZone = Dock.calendar.timeZone
        f.dateFormat = "d MMMM"
        return inUkraine == true ? "У кіно в Україні з \(f.string(from: d))" : "Прем'єра \(f.string(from: d)), дата в Україні ще невідома"
    }

    /// A cinema invitation can't be before the movie is out: that day at 19:00.
    static func cinemaStart(_ s: String?, now: Date = Date()) -> Date? {
        guard let d = day(s), d > now else { return nil }
        return Dock.calendar.date(bySettingHour: 19, minute: 0, second: 0, of: d)
    }
}
