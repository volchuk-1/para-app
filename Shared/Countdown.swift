import Foundation

enum Countdown {
    /// iPhone keeps a Live Activity for up to 8 hours, so the countdown starts only that close to the date.
    static func shouldStartLiveActivity(startsAt: Date, now: Date) -> Bool {
        let d = startsAt.timeIntervalSince(now)
        return d > 0 && d <= 8 * 3600
    }

    /// 09:00 on the day of the event, if it starts at 10:00 or later; earlier events get only the 1-hour reminder.
    static func morningReminder(startsAt: Date, tz: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        guard let hour = cal.dateComponents([.hour], from: startsAt).hour, hour >= 10 else { return nil }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: startsAt)
    }

    static let kyiv = TimeZone(identifier: "Europe/Kyiv") ?? .current
}

enum EventTimes {
    /// An end before the start becomes start + 2 hours.
    static func clampedEnd(start: Date, end: Date) -> Date {
        end < start ? start.addingTimeInterval(7200) : end
    }
}

enum ShareRouting {
    /// First web link inside shared text («Дивись це https://vm.tiktok.com/… 🔥»).
    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for m in detector.matches(in: text, options: [], range: range) {
            if let url = m.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" { return url }
        }
        return nil
    }
}
