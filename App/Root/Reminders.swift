import Foundation
import UserNotifications
import ActivityKit

/// Local reminders (work without push): 1 hour before every "ours" event and 09:00 on the day.
enum Reminders {
    private static let prefix = "dv-"

    static func sync(_ events: [Event]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
            let now = Date()
            let soon = events.filter { $0.isOurs && $0.startsAt > now && $0.startsAt < now.addingTimeInterval(30 * 86400) }
                .filter { $0.invitation == nil || $0.invitation?.status == .accepted }
                .prefix(30)
            for e in soon {
                add(center, id: "\(prefix)\(e.id)-1h", at: e.startsAt.addingTimeInterval(-3600),
                    title: "За годину: \(e.title)", body: e.place ?? "")
                if let morning = Countdown.morningReminder(startsAt: e.startsAt, tz: Countdown.kyiv), morning > now {
                    let t = e.startsAt.formatted(.dateTime.hour().minute())
                    add(center, id: "\(prefix)\(e.id)-am", at: morning,
                        title: "Сьогодні о \(t): \(e.title)",
                        body: e.invitation != nil ? "Відкрий DaVincit, щоб запустити відлік." : (e.place ?? ""))
                }
            }
        }
    }

    private static func add(_ c: UNUserNotificationCenter, id: String, at date: Date, title: String, body: String) {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        c.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    static func askPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}

/// Starts the date countdown in the Dynamic Island when an accepted invitation is less than 8 hours away.
enum LiveDates {
    static func sync(_ events: [Event]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()
        let running = Set(Activity<DateAttributes>.activities.map(\.attributes.eventId))
        for e in events where e.invitation?.status == .accepted && Countdown.shouldStartLiveActivity(startsAt: e.startsAt, now: now) {
            if running.contains(e.id) { continue }
            let attrs = DateAttributes(eventId: e.id, title: e.title, place: e.place ?? "")
            let state = DateAttributes.ContentState(startsAt: e.startsAt)
            _ = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: e.startsAt.addingTimeInterval(3600)))
        }
        // End countdowns of cancelled / past events.
        for a in Activity<DateAttributes>.activities {
            let e = events.first { $0.id == a.attributes.eventId }
            if e == nil || e?.invitation?.status != .accepted || (e!.startsAt < now.addingTimeInterval(-3600)) {
                Task { await a.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }
}
