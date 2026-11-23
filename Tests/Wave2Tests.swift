import XCTest

final class Wave2Tests: XCTestCase {
    func testDayPlanDecodesAndLabels() throws {
        let json = #"{"days":[{"date":"2026-11-24","weekday":2,"status":"free","freeFrom":"17:00","plan":null,"meOff":false,"partnerOff":true,"blocks":{"me":[{"kind":"work","label":"Робота","start":"09:00","end":"17:00"}],"partner":[]}}]}"#
        let r = try API.decoder.decode(AvailabilityResult.self, from: Data(json.utf8))
        let d = r.days[0]
        XCTAssertTrue(d.isFree)
        XCTAssertEqual(Evening.label(d), "Вільний вечір")
        XCTAssertEqual(Evening.note(d, partner: "Дарина"), "Обоє вільні з 17:00 · у Дарина вихідний")
        XCTAssertEqual(Evening.minutes(d.blocks.me[0].end), 17 * 60)
    }

    func testIsoRoundTripAndMonday() {
        let d = Evening.date("2026-11-26")!
        XCTAssertEqual(Evening.iso(d), "2026-11-26")
        XCTAssertEqual(Evening.iso(Evening.monday(of: d)), "2026-11-23")
    }

    func testFilmMainAction() throws {
        func item(_ type: String, _ status: String) throws -> WatchItem {
            try API.decoder.decode(WatchItem.self, from: Data(#"{"id":"1","tmdbId":1,"mediaType":"\#(type)","isAnime":false,"title":"T","year":2024,"posterUrl":null,"status":"\#(status)","season":null,"episode":null,"sourceUrl":null,"addedBy":"m","ratings":{},"avg":null}"#.utf8))
        }
        XCTAssertEqual(try item("tv", "watching").mainAction, .nextEpisode)
        XCTAssertEqual(try item("movie", "want").mainAction, .invite)
        XCTAssertEqual(try item("tv", "want").mainAction, .start)
        XCTAssertEqual(try item("movie", "done").mainAction, .done)
    }

    func testWave2PayloadsDecode() throws {
        let b = try API.decoder.decode(BooksResult.self, from: Data(#"{"books":[{"id":"b","ownerId":"m","title":"Процес","author":"Кафка","pages":340,"coverUrl":null,"isbn":null,"status":"paused","currentPage":35,"addedAt":"2026-11-23T10:00:00.000Z","finishedAt":null}]}"#.utf8))
        XCTAssertEqual(b.books[0].status, .paused)
        XCTAssertEqual(b.books[0].progress, 35.0 / 340.0, accuracy: 0.0001)
        let f = try API.decoder.decode(FinanceResult.self, from: Data(#"{"connected":true,"jars":[{"id":"j","title":"Відпустка","balance":11200,"goal":20000,"topUpUrl":"https://send.monobank.ua/jar/A"}],"goal":{"title":"Карпати","target":40000,"jarIds":["j"],"saved":11200,"percent":28},"error":null}"#.utf8))
        XCTAssertEqual(f.goal?.percent, 28)
        let s = try API.decoder.decode(SessionsResult.self, from: Data(#"{"cinema":"Паннонія","sessions":[{"title":"Месники","date":"2026-12-17","time":"19:00","tags":["3D"],"buyUrl":"https://new.multiplex.ua/order/cinema/1/session/2"}]}"#.utf8))
        XCTAssertEqual(s.sessions[0].tags, ["3D"])
        let w = try API.decoder.decode(WatchItem.self, from: Data(#"{"id":"1","tmdbId":1,"mediaType":"tv","isAnime":false,"title":"Loki","year":2021,"posterUrl":null,"status":"done","season":null,"episode":null,"sourceUrl":null,"addedBy":"m","ratings":{"m":9},"avg":9,"overview":"…","backdropUrl":"https://image.tmdb.org/t/p/w780/q.jpg","genres":["Драма"],"rating":{"tmdb":8.2,"imdb":8.2,"rt":92},"reviews":{"m":"Супер"}}"#.utf8))
        XCTAssertEqual(w.rating?.rt, 92)
        XCTAssertEqual(w.reviews?["m"], "Супер")
    }
}
