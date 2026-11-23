import Foundation

enum APIError: Error, Equatable, LocalizedError {
    case unauthorized, badCode, tooMany, offline, notFound, decoding
    case server(Int)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Цей телефон більше не в парі. Увійди знову."
        case .badCode: return "Код не підходить або вже використаний."
        case .tooMany: return "Забагато спроб. Спробуй за 15 хвилин."
        case .offline: return "Немає зв'язку з сервером."
        case .notFound: return "Не знайдено."
        case .decoding: return "Незрозуміла відповідь сервера."
        case .server(let code): return "Помилка сервера (\(code))."
        case .other(let code): return "Помилка: \(code)."
        }
    }
}

/// Thin client for the DaVincit server. All calls are JSON; the device key goes in `Authorization: Bearer`.
actor API {
    let base: URL
    private(set) var key: String?
    private let session: URLSession

    init(base: URL, key: String?, session: URLSession = .shared) {
        self.base = base
        self.key = key
        self.session = session
    }

    /// The client the app and extensions use: server and key from the shared store.
    static func current() -> API { API(base: KeyStore.serverURL, key: KeyStore.deviceKey) }

    func setKey(_ key: String?) { self.key = key }

    // MARK: JSON

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let v = withFraction.date(from: s) ?? plain.date(from: s) { return v }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(f.string(from: date))
        }
        return e
    }()

    // MARK: Core

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request("GET", path, body: Optional<Empty>.none)
    }

    func send<B: Encodable, T: Decodable>(_ method: String, _ path: String, _ body: B) async throws -> T {
        try await request(method, path, body: body)
    }

    /// For calls that answer 204 / an ignored body.
    func send<B: Encodable>(_ method: String, _ path: String, _ body: B) async throws {
        let _: Empty = try await request(method, path, body: body)
    }

    func delete(_ path: String) async throws {
        let _: Empty = try await request("DELETE", path, body: Optional<Empty>.none)
    }

    /// Raw body of a GET (for caches).
    func raw(_ path: String) async throws -> Data {
        let r: RawBody = try await get(path)
        return r.data
    }

    func upload<T: Decodable>(_ path: String, jpeg: Data, method: String = "PUT") async throws -> T {
        let boundary = "dv-\(UUID().uuidString)"
        var data = Data()
        data.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"cover.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        data.append(jpeg)
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var req = makeRequest(method, path)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        return try await perform(req)
    }

    private func makeRequest(_ method: String, _ path: String) -> URLRequest {
        let url = URL(string: path, relativeTo: base)!.absoluteURL
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private func request<B: Encodable, T: Decodable>(_ method: String, _ path: String, body: B?) async throws -> T {
        var req = makeRequest(method, path)
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try API.encoder.encode(body)
        }
        return try await perform(req)
    }

    private func perform<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .timedOut, .dataNotAllowed, .internationalRoamingOff, .dnsLookupFailed:
                throw APIError.offline
            default:
                throw APIError.other(e.localizedDescription)
            }
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) {
            if T.self == RawBody.self { return RawBody(data: data) as! T }
            if T.self == Empty.self, data.isEmpty || status == 204 { return Empty() as! T }
            do { return try API.decoder.decode(T.self, from: data) } catch { throw APIError.decoding }
        }
        let code = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
        switch (status, code) {
        case (401, _): throw APIError.unauthorized
        case (429, _): throw APIError.tooMany
        case (404, _): throw APIError.notFound
        case (_, "BAD_CODE"?): throw APIError.badCode
        case (400..<500, let c?): throw APIError.other(c)
        default: throw APIError.server(status)
        }
    }

    // MARK: Pair

    struct CreateBody: Encodable { let myName: String; let partnerName: String; let myRole: String }
    struct JoinBody: Encodable { let code: String; let name: String? }
    struct DeviceCodeBody: Encodable { let memberId: String }
    struct NameBody: Encodable { let name: String }

    func createPair(myName: String, partnerName: String, myRole: String) async throws -> PairResult {
        try await send("POST", "/pair/create", CreateBody(myName: myName, partnerName: partnerName, myRole: myRole))
    }

    func join(code: String, name: String?) async throws -> PairResult {
        try await send("POST", "/pair/join", JoinBody(code: code, name: name))
    }

    func me() async throws -> MeResult { try await get("/me") }

    func deviceCode(for memberId: String) async throws -> PairCode {
        try await send("POST", "/pair/device-code", DeviceCodeBody(memberId: memberId))
    }

    // MARK: Push probe

    struct TokenBody: Encodable { let token: String }
    struct PushStatus: Decodable { let myTokens: Int; let serverCanSend: Bool }

    func sendPushToken(_ token: String) async throws {
        try await send("POST", "/push/token", TokenBody(token: token))
    }

    func pushStatus() async throws -> PushStatus { try await get("/push/status") }

    func rename(_ name: String) async throws -> Member {
        struct R: Decodable { let me: Member }
        let r: R = try await send("PATCH", "/me", NameBody(name: name))
        return r.me
    }
}
