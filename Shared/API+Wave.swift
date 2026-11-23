import Foundation

/// Wave-1 endpoints.
extension API {
    // MARK: Home
    func home() async throws -> HomeResult { try await get("/home") }
    /// `/home` plus the raw bytes for the offline cache.
    func homeRaw() async throws -> (HomeResult, Data) {
        let data = try await raw("/home")
        do { return (try API.decoder.decode(HomeResult.self, from: data), data) } catch { throw APIError.decoding }
    }

    // MARK: Events
    func events(from: Date, to: Date) async throws -> [Event] {
        let f = ISO8601DateFormatter()
        let r: EventsResult = try await get("/events?from=\(f.string(from: from))&to=\(f.string(from: to))")
        return r.events
    }
    func createEvent(_ d: EventDraft) async throws -> Event { (try await send("POST", "/events", d) as EventResult).event }
    func updateEvent(_ id: String, _ d: EventDraft) async throws -> Event { (try await send("PATCH", "/events/\(id)", d) as EventResult).event }
    func deleteEvent(_ id: String) async throws { try await delete("/events/\(id)") }

    // MARK: Invitations
    struct AnswerBody: Encodable { let action: String; let note: String? }
    func createInvitation(_ d: EventDraft) async throws -> Event { (try await send("POST", "/invitations", d) as EventResult).event }
    func answer(_ id: String, accept: Bool, note: String? = nil) async throws -> Event {
        (try await send("POST", "/invitations/\(id)/answer", AnswerBody(action: accept ? "accept" : "reschedule", note: note)) as EventResult).event
    }
    func cancelInvitation(_ id: String) async throws -> Event { (try await send("POST", "/invitations/\(id)/cancel", Empty()) as EventResult).event }
    func uploadCover(_ id: String, jpeg: Data) async throws {
        struct R: Decodable { let coverUrl: String }
        let _: R = try await upload("/invitations/\(id)/cover", jpeg: jpeg)
    }
    /// Raw bytes of a protected file (invitation cover).
    func fileData(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.notFound }
        var req = URLRequest(url: url)
        if let key { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.notFound }
        return data
    }

    // MARK: Watch
    struct AddWatchBody: Encodable {
        let tmdbId: Int; let mediaType: String; let title: String; let year: Int?; let posterPath: String?; let isAnime: Bool; let sourceUrl: String?
    }
    struct WatchPatch: Encodable { var status: String?; var season: Int?; var episode: Int? }
    struct ScoreBody: Encodable { let score: Int }
    struct URLBody: Encodable { let url: String }

    func watchList() async throws -> [WatchItem] { (try await get("/watch") as WatchList).items }
    func addWatch(_ c: Candidate, sourceUrl: String?) async throws -> WatchItem {
        (try await send("POST", "/watch", AddWatchBody(tmdbId: c.tmdbId, mediaType: c.mediaType, title: c.title, year: c.year,
                                                        posterPath: c.posterPath, isAnime: c.isAnime, sourceUrl: sourceUrl)) as WatchResult).item
    }
    func patchWatch(_ id: String, _ p: WatchPatch) async throws -> WatchItem { (try await send("PATCH", "/watch/\(id)", p) as WatchResult).item }
    func nextEpisode(_ id: String) async throws -> WatchItem { (try await send("POST", "/watch/\(id)/next", Empty()) as WatchResult).item }
    func rate(_ id: String, _ score: Int) async throws -> WatchItem { (try await send("PUT", "/watch/\(id)/rating", ScoreBody(score: score)) as WatchResult).item }
    func deleteWatch(_ id: String) async throws { try await delete("/watch/\(id)") }
    func search(_ q: String) async throws -> [Candidate] {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let enc = q.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return (try await get("/search?q=\(enc)") as CandidatesResult).candidates
    }

    // MARK: Wishes
    struct WishBody: Encodable { var url: String?; var title: String?; var price: Double?; var note: String?; var ownerId: String? }
    struct WishPatch: Encodable { var status: String?; var note: String?; var title: String?; var price: Double?; var ownerId: String? }
    func wishes() async throws -> [Wish] { (try await get("/wishes") as WishList).wishes }
    func addWish(_ b: WishBody) async throws -> Wish { (try await send("POST", "/wishes", b) as WishResult).wish }
    func patchWish(_ id: String, _ p: WishPatch) async throws -> Wish { (try await send("PATCH", "/wishes/\(id)", p) as WishResult).wish }
    func deleteWish(_ id: String) async throws { try await delete("/wishes/\(id)") }

    // MARK: Share
    func share(_ url: URL) async throws -> ShareResult { try await send("POST", "/share", URLBody(url: url.absoluteString)) }
}
