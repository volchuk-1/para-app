import XCTest

/// Answers every request with a canned response and remembers the last request.
final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        StubProtocol.lastRequest = request
        do {
            guard let h = StubProtocol.handler else { throw URLError(.badServerResponse) }
            let (status, data) = try h(request)
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class APITests: XCTestCase {
    private func makeAPI(key: String? = nil) -> API {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        return API(base: URL(string: "https://example.test")!, key: key, session: URLSession(configuration: cfg))
    }

    func testUnauthorized() async {
        StubProtocol.handler = { _ in (401, Data(#"{"error":"UNAUTHORIZED"}"#.utf8)) }
        do { _ = try await makeAPI(key: "x").me(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }

    func testBadCode() async {
        StubProtocol.handler = { _ in (400, Data(#"{"error":"BAD_CODE"}"#.utf8)) }
        do { _ = try await makeAPI().join(code: "ZZZZZZ", name: nil); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? APIError, .badCode) }
    }

    func testTooMany() async {
        StubProtocol.handler = { _ in (429, Data(#"{"error":"TOO_MANY"}"#.utf8)) }
        do { _ = try await makeAPI().join(code: "ZZZZZZ", name: nil); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? APIError, .tooMany) }
    }

    func testOffline() async {
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await makeAPI(key: "x").me(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? APIError, .offline) }
    }

    func testBearerHeaderAndPath() async throws {
        StubProtocol.handler = { _ in
            (200, Data(#"{"me":{"id":"a","name":"В","role":"m"},"partner":null,"coupleId":"c"}"#.utf8))
        }
        let r = try await makeAPI(key: "secret").me()
        XCTAssertEqual(r.coupleId, "c")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/me")
    }

    func testNoHeaderWithoutKey() async throws {
        StubProtocol.handler = { _ in
            (201, Data(#"{"deviceKey":"k","me":{"id":"a","name":"В","role":"m"},"partner":{"id":"b","name":"Д","role":"f"},"pairCode":"ABC234","pairCodeExpiresAt":"2026-11-24T10:00:00.000Z"}"#.utf8))
        }
        let r = try await makeAPI().createPair(myName: "В", partnerName: "Д", myRole: "m")
        XCTAssertEqual(r.pairCode, "ABC234")
        XCTAssertNil(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "POST")
    }
}
