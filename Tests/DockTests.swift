import XCTest

final class DockTests: XCTestCase {
    private let cal = Dock.calendar

    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    private func event(_ id: String, _ starts: String, title: String = "Кіно", ends: String? = nil) throws -> Event {
        let endsJSON = ends.map { "\"\($0)\"" } ?? "null"
        let json = #"{"id":"\#(id)","ownerId":null,"title":"\#(title)","startsAt":"\#(starts)","endsAt":\#(endsJSON),"createdBy":"m"}"#
        return try API.decoder.decode(Event.self, from: Data(json.utf8))
    }

    func testWeekStartsOnMonday() {
        let days = Dock.week(containing: date("2026-11-26T12:00:00Z"), cal: cal) // Thursday
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(cal.component(.weekday, from: days[0]), 2) // Monday
        XCTAssertEqual(cal.component(.day, from: days[0]), 23)
        XCTAssertEqual(cal.component(.day, from: days[6]), 29)
    }

    func testNextEventSkipsPastAndPicksEarliest() throws {
        let now = date("2026-11-23T18:00:00Z")
        let past = try event("a", "2026-11-22T17:00:00Z")
        let later = try event("b", "2026-11-28T17:30:00Z")
        let sooner = try event("c", "2026-11-25T10:00:00Z", title: "Обід")
        XCTAssertEqual(Dock.nextEvent([past, later, sooner], now: now)?.id, "c")
        XCTAssertNil(Dock.nextEvent([past], now: now))
    }

    func testNextLineSaysTodayTomorrowOrWeekday() throws {
        let now = date("2026-11-23T08:00:00Z") // Monday, Kyiv 10:00
        XCTAssertEqual(Dock.nextLine(try event("a", "2026-11-23T17:30:00Z"), now: now, cal: cal), "Сьогодні · Кіно о 19:30")
        XCTAssertEqual(Dock.nextLine(try event("b", "2026-11-24T17:30:00Z"), now: now, cal: cal), "Завтра · Кіно о 19:30")
        XCTAssertEqual(Dock.nextLine(try event("c", "2026-11-28T17:30:00Z"), now: now, cal: cal), "сб, 28 · Кіно о 19:30")
        XCTAssertEqual(Dock.nextLine(nil, now: now, cal: cal), "Попереду поки вільно")
    }

    func testNotificationsDecode() throws {
        let r = try API.decoder.decode(NotificationsResult.self, from: Data(#"{"items":[{"id":"1","kind":"wish_new","title":"Дарина: нове бажання","body":null,"createdAt":"2026-11-23T18:00:00.000Z","read":false}],"unread":1}"#.utf8))
        XCTAssertEqual(r.unread, 1)
        XCTAssertEqual(r.items.first?.title, "Дарина: нове бажання")
    }

    func testReleaseLineOnlyForMoviesNotOutYet() {
        let now = date("2026-11-23T10:00:00Z")
        XCTAssertEqual(Release.line("2026-12-17", inUkraine: true, now: now), "У кіно в Україні з 17 грудня")
        XCTAssertEqual(Release.line("2026-11-26", inUkraine: false, now: now), "Прем'єра 26 листопада, дата в Україні ще невідома")
        XCTAssertNil(Release.line("2026-11-01", inUkraine: true, now: now))
        XCTAssertNil(Release.line(nil, inUkraine: nil, now: now))
    }

    func testCinemaInvitationStartsOnReleaseEvening() {
        let now = date("2026-11-23T10:00:00Z")
        let s = Release.cinemaStart("2026-12-17", now: now)!
        XCTAssertEqual(cal.component(.day, from: s), 17)
        XCTAssertEqual(cal.component(.hour, from: s), 19)
        XCTAssertNil(Release.cinemaStart("2026-11-01", now: now))
    }
}
