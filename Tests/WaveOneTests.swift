import XCTest

final class WaveOneTests: XCTestCase {
    private func decode<T: Decodable>(_ t: T.Type, _ s: String) throws -> T {
        try API.decoder.decode(T.self, from: Data(s.utf8))
    }

    // MARK: Events

    func testEventWithInvitationDecodes() throws {
        let e = try decode(Event.self, """
        {"id":"e1","ownerId":null,"title":"Вечеря","startsAt":"2026-11-28T17:00:00.000Z","endsAt":null,
         "place":"Тераса","mapUrl":null,"note":null,"createdBy":"a","updatedAt":"2026-11-23T10:00:00.000Z",
         "invitation":{"dress":"темне","message":"Чекаю","coverUrl":"https://x/files/a.jpg","status":"pending","replyNote":null,"answeredAt":null}}
        """)
        XCTAssertNil(e.ownerId)
        XCTAssertTrue(e.isOurs)
        XCTAssertEqual(e.invitation?.status, .pending)
        XCTAssertEqual(e.invitation?.coverUrl, "https://x/files/a.jpg")
    }

    // MARK: Countdown

    func testLiveActivityWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(Countdown.shouldStartLiveActivity(startsAt: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(Countdown.shouldStartLiveActivity(startsAt: now, now: now))
        XCTAssertTrue(Countdown.shouldStartLiveActivity(startsAt: now.addingTimeInterval(7 * 3600 + 59 * 60), now: now))
        XCTAssertFalse(Countdown.shouldStartLiveActivity(startsAt: now.addingTimeInterval(8 * 3600 + 60), now: now))
    }

    func testMorningReminder() throws {
        let kyiv = TimeZone(identifier: "Europe/Kyiv")!
        let f = ISO8601DateFormatter()
        // 19:00 Kyiv (winter, UTC+2) → 09:00 the same day
        let evening = f.date(from: "2026-11-28T17:00:00Z")!
        XCTAssertEqual(Countdown.morningReminder(startsAt: evening, tz: kyiv), f.date(from: "2026-11-28T07:00:00Z"))
        // 09:30 → no morning reminder
        XCTAssertNil(Countdown.morningReminder(startsAt: f.date(from: "2026-11-28T07:30:00Z")!, tz: kyiv))
        // 10:00 → 09:00
        XCTAssertEqual(Countdown.morningReminder(startsAt: f.date(from: "2026-11-28T08:00:00Z")!, tz: kyiv), f.date(from: "2026-11-28T07:00:00Z"))
    }

    // MARK: Home tiles

    func testTilesDecodeAndUnknownKindIsSkipped() throws {
        let h = try decode(HomeResult.self, """
        {"greeting":{"name":"Віктор","subline":"Побачення за 4 дні"},"tiles":[
          {"kind":"next","event":{"id":"e1","ownerId":null,"title":"Кіно","startsAt":"2026-11-26T17:00:00.000Z","endsAt":null,"place":null,"mapUrl":null,"note":null,"createdBy":"a","updatedAt":"2026-11-23T10:00:00.000Z","invitation":null}},
          {"kind":"future_kind","x":1},
          {"kind":"watching","items":[{"id":"w","title":"Темрява","posterUrl":null,"season":1,"episode":5,"mediaType":"tv"}]},
          {"kind":"want","count":3,"posters":["https://image.tmdb.org/t/p/w342/a.jpg"]},
          {"kind":"drop","wishes":[{"id":"x","ownerId":"b","url":null,"title":"Крем","imageUrl":null,"price":800,"currency":"UAH","firstPrice":1000,"note":null,"status":"want","addedBy":"b","addedAt":"2026-11-23T10:00:00.000Z","dropPercent":20}]}
        ]}
        """)
        XCTAssertEqual(h.greeting.subline, "Побачення за 4 дні")
        XCTAssertEqual(h.tiles.count, 4)
        guard case .watching(let items) = h.tiles[1] else { return XCTFail("watching expected") }
        XCTAssertEqual(items.first?.episodeLabel, "S1E5")
        guard case .drop(let wishes) = h.tiles[3] else { return XCTFail("drop expected") }
        XCTAssertEqual(wishes.first?.dropPercent, 20)
    }

    // MARK: Watch & wishes

    func testWatchItemRatings() throws {
        let w = try decode(WatchItem.self, """
        {"id":"w","tmdbId":70523,"mediaType":"tv","isAnime":false,"title":"Темрява","year":2017,"posterUrl":null,
         "status":"done","season":3,"episode":8,"sourceUrl":null,"addedBy":"a","addedAt":"2026-11-23T10:00:00.000Z",
         "ratings":{"a":9,"b":6},"avg":7.5}
        """)
        XCTAssertEqual(w.ratings["a"], 9)
        XCTAssertEqual(w.avg, 7.5)
        XCTAssertEqual(w.status, .done)
        XCTAssertEqual(w.kindLabel, "Серіал")
    }

    func testWishPriceText() throws {
        let w = try decode(Wish.self, """
        {"id":"x","ownerId":"b","url":"https://shop.ua/a b","title":"Крем","imageUrl":"не url","price":1290.5,"currency":"UAH",
         "firstPrice":1290.5,"note":null,"status":"want","addedBy":"b","addedAt":"2026-11-23T10:00:00.000Z","dropPercent":null}
        """)
        XCTAssertEqual(w.priceText, "1 290,5 ₴")
        XCTAssertNil(w.dropPercent)
    }

    func testShareResultBothKinds() throws {
        let watch = try decode(ShareResult.self, #"{"kind":"watch","caption":"x","candidates":[{"tmdbId":1,"mediaType":"tv","title":"Темрява","originalTitle":"Dark","year":2017,"posterPath":"/a.jpg","posterUrl":"https://i/a.jpg","isAnime":false}]}"#)
        XCTAssertEqual(watch.candidates?.first?.title, "Темрява")
        let wish = try decode(ShareResult.self, #"{"kind":"wish","wish":{"id":"x","ownerId":"b","url":null,"title":"Крем","imageUrl":null,"price":null,"currency":null,"firstPrice":null,"note":null,"status":"want","addedBy":"b","addedAt":"2026-11-23T10:00:00.000Z","dropPercent":null}}"#)
        XCTAssertEqual(wish.wish?.title, "Крем")
    }

    // MARK: Share routing

    func testFirstURLInText() {
        XCTAssertEqual(ShareRouting.firstURL(in: "Дивись це https://vm.tiktok.com/ZM123/ 🔥")?.absoluteString, "https://vm.tiktok.com/ZM123/")
        XCTAssertEqual(ShareRouting.firstURL(in: "https://youtu.be/abc")?.host, "youtu.be")
        XCTAssertNil(ShareRouting.firstURL(in: "без посилання"))
    }
}
