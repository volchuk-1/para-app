import XCTest

final class ReviewFixTests: XCTestCase {
    private func makeAPI() -> API {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        return API(base: URL(string: "https://example.test")!, key: "k", session: URLSession(configuration: cfg))
    }

    /// «Fast & Furious» must reach the server whole, not as «Fast ».
    func testSearchEncodesAmpersand() async throws {
        StubProtocol.handler = { _ in (200, Data(#"{"candidates":[]}"#.utf8)) }
        _ = try await makeAPI().search("Fast & Furious")
        let comps = URLComponents(url: StubProtocol.lastRequest!.url!, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(comps.queryItems?.first(where: { $0.name == "q" })?.value, "Fast & Furious")
    }

    /// Emptied fields are sent as null so the server clears them.
    func testDraftSendsNullsForEmptiedFields() throws {
        let d = EventDraft(ownerId: nil, title: "Кіно", startsAt: Date(timeIntervalSince1970: 0), endsAt: nil,
                           place: nil, mapUrl: nil, note: nil, dress: nil, message: nil)
        let obj = try JSONSerialization.jsonObject(with: API.encoder.encode(d)) as! [String: Any]
        for key in ["ownerId", "endsAt", "place", "mapUrl", "note", "dress", "message"] {
            XCTAssertTrue(obj[key] is NSNull, "\(key) must be null")
        }
    }

    /// Home answer is kept as raw JSON and decodes again offline.
    func testHomeCacheRoundTrip() throws {
        let raw = Data(#"{"greeting":{"name":"В","subline":"Сьогодні вільний вечір"},"tiles":[{"kind":"want","count":2,"posters":[]}]}"#.utf8)
        HomeCache.save(raw)
        let h = try XCTUnwrap(HomeCache.load())
        XCTAssertEqual(h.greeting.subline, "Сьогодні вільний вечір")
        XCTAssertEqual(h.tiles.count, 1)
    }

    /// SideStore renames app groups; the real one is listed in ALTAppGroups.
    func testGroupPrefersSideStoreName() {
        XCTAssertEqual(Shared.groupID(info: ["ALTAppGroups": ["group.com.volchuk.para.ABCDE12345"]]), "group.com.volchuk.para.ABCDE12345")
        XCTAssertEqual(Shared.groupID(info: [:]), "group.com.volchuk.para")
    }

    /// The end of an event is never before its start.
    func testEndClamp() {
        let start = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(EventTimes.clampedEnd(start: start, end: start.addingTimeInterval(-60)), start.addingTimeInterval(7200))
        XCTAssertEqual(EventTimes.clampedEnd(start: start, end: start.addingTimeInterval(600)), start.addingTimeInterval(600))
    }

    /// A closed pair explains what to do instead of showing a code.
    func testClosedPairMessage() {
        XCTAssertTrue(APIError.other("CLOSED").localizedDescription.contains("У мене є код"))
        XCTAssertEqual(APIError.other("XYZ").localizedDescription, "Помилка: XYZ.")
    }
}
