import Foundation
import ActivityKit

/// Shared between the app and the widget extension.
enum Shared {
    static let group = "group.com.volchuk.para"
    static let server = URL(string: "https://kartky-167-233-130-88.sslip.io/robots.txt")!
}

/// Probe Live Activity: a countdown shown on the lock screen and in the Dynamic Island.
struct PingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endsAt: Date
        var label: String
    }
    var title: String
}

extension Date {
    /// A range that is never inverted, so `Text(timerInterval:)` can't crash after the end.
    static func countdown(to end: Date) -> ClosedRange<Date> {
        let now = Date()
        return now...max(now, end)
    }
}
