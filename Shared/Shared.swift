import Foundation
import ActivityKit

/// Shared between the app and its extensions.
enum Shared {
    static let group = "group.com.volchuk.para"
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

/// Countdown to an accepted date, on the lock screen and in the Dynamic Island.
struct DateAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startsAt: Date
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
