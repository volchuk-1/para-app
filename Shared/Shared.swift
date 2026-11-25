import Foundation
import ActivityKit

/// Shared between the app and its extensions.
enum Shared {
    static let defaultGroup = "group.com.volchuk.para"
    /// SideStore re-signs with a renamed group and lists the real name in ALTAppGroups.
    static var group: String { groupID(info: Bundle.main.infoDictionary ?? [:]) }
    static func groupID(info: [String: Any]) -> String {
        (info["ALTAppGroups"] as? [String])?.first ?? defaultGroup
    }
    /// True only if iOS really gives this app the shared container.
    static var groupWorks: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
    }
    static let defaultServer = URL(string: "https://davincit-167-233-130-88.sslip.io")!
    /// Kept for the diagnostics widget: any URL that answers 200.
    static var server: URL { KeyStore.serverURL.appendingPathComponent("health") }
}

/// Probe Live Activity (diagnostics): a countdown on the lock screen and in the Dynamic Island.
struct PingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endsAt: Date
        var label: String
    }
    var title: String
}

/// Timer of a planned activity (calendar): before the start it counts down to the start, then to the end.
struct TaskAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startsAt: Date
        var endsAt: Date
    }
    var taskId: String
    var title: String
}

/// Countdown to an accepted date, on the lock screen and in the Dynamic Island.
struct DateAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startsAt: Date
        /// «Дарина · 6 хв · 1,2 км» while we are both on the way (only with the consent of each of us).
        var partner: String? = nil
    }
    var eventId: String
    var title: String
    var place: String
}

extension Date {
    /// A range that is never inverted, so `Text(timerInterval:)` can't crash after the end.
    static func countdown(to end: Date) -> ClosedRange<Date> {
        let now = Date()
        return now...max(now, end)
    }
}
