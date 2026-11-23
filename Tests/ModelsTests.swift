import XCTest

final class ModelsTests: XCTestCase {
    func testPairResultDecodes() throws {
        let json = """
        {"deviceKey":"k1","me":{"id":"a","name":"Віктор","role":"m"},
         "partner":{"id":"b","name":"Дарина","role":"f"},
         "pairCode":"ABC234","pairCodeExpiresAt":"2026-11-24T10:00:00.000Z"}
        """.data(using: .utf8)!
        let r = try API.decoder.decode(PairResult.self, from: json)
        XCTAssertEqual(r.deviceKey, "k1")
        XCTAssertEqual(r.me.name, "Віктор")
        XCTAssertEqual(r.partner?.role, "f")
        XCTAssertEqual(r.pairCode, "ABC234")
        XCTAssertNotNil(r.pairCodeExpiresAt)
    }

    func testJoinResultHasNoCode() throws {
        let json = """
        {"deviceKey":"k2","me":{"id":"b","name":"Дарина","role":"f"},"partner":{"id":"a","name":"Віктор","role":"m"}}
        """.data(using: .utf8)!
        let r = try API.decoder.decode(PairResult.self, from: json)
        XCTAssertNil(r.pairCode)
        XCTAssertEqual(r.partner?.name, "Віктор")
    }

    func testMeResultDecodes() throws {
        let json = """
        {"me":{"id":"a","name":"Віктор","role":"m"},"partner":{"id":"b","name":"Дарина","role":"f"},"coupleId":"c"}
        """.data(using: .utf8)!
        let r = try API.decoder.decode(MeResult.self, from: json)
        XCTAssertEqual(r.coupleId, "c")
    }

    func testDatesWithAndWithoutFraction() throws {
        struct D: Decodable { let a: Date; let b: Date }
        let json = #"{"a":"2026-11-24T10:00:00.000Z","b":"2026-11-24T10:00:00Z"}"#.data(using: .utf8)!
        let d = try API.decoder.decode(D.self, from: json)
        XCTAssertEqual(d.a, d.b)
    }
}
