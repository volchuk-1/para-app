import Foundation

// MARK: - Wave 4 models: shift hours, banks, close people, trips, premieres, episodes, discover, history

struct ShiftDay4: Codable, Equatable, Hashable { let memberId: String; let date: String; let value: String; var start: String? = nil; var end: String? = nil }
struct Schedule4: Codable, Equatable { let rules: [ScheduleRule]; let shifts: [ShiftDay4] }

struct JarPlan: Codable, Equatable, Hashable { var perMonth: Double? = nil; var eta: String? = nil }
struct Jar4: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let balance: Double
    let goal: Double?
    let topUpUrl: String?
    var category: String
    var visibility: String
    var purpose: String?
    var due: String?
    var monthly: Double?
    var isNew: Bool
    var plan: JarPlan

    static let categories: [(String, String, String)] = [("trip", "Подорож", "airplane"), ("gift", "Подарунок", "gift.fill"), ("birthday", "День народження", "birthday.cake.fill"),
                                                         ("holiday", "Свято", "sparkles"), ("purchase", "Покупка", "bag.fill"), ("other", "Інше", "banknote.fill")]
    static let seen: [String: String] = ["both": "бачимо обоє", "me": "лише я", "hidden": "сховано"]
    var categoryLabel: String { Self.categories.first { $0.0 == category }?.1 ?? "Інше" }
    var categoryIcon: String { Self.categories.first { $0.0 == category }?.2 ?? "banknote.fill" }
}
struct Finance4: Codable, Equatable { let connected: Bool; var owner: Bool? = nil; let jars: [Jar4]; var hidden: [Jar4]? = nil; var error: String? = nil }

struct Person: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var relation: String?
    var birthday: String   // MM-DD
    var year: Int?
    let next: String
    let daysLeft: Int
    let turns: Int?
}
struct PeopleResult: Decodable { let people: [Person] }
struct PersonResult: Decodable { let person: Person }

struct TripStay: Codable, Equatable, Hashable { var name: String? = nil; var url: String? = nil; var checkIn: String? = nil; var checkOut: String? = nil; var price: Double? = nil; var booked: Bool = false }
struct PackItem: Codable, Equatable, Hashable { var t: String; var done: Bool = false }
struct PlanItem: Codable, Equatable, Hashable { var day: String?; var text: String }
struct Trip: Codable, Identifiable, Equatable, Hashable {
    var id: String = ""
    var title: String = ""
    var place: String? = nil
    var from: String? = nil
    var to: String? = nil
    var budget: Double? = nil
    var jarId: String? = nil
    var transport: String? = "car"
    var road: String? = nil
    var stay: TripStay? = TripStay()
    var packing: [PackItem] = []
    var plan: [PlanItem] = []
    var nights: Int? = nil
}
struct TripsResult: Decodable { let trips: [Trip] }
struct TripResult: Decodable { let trip: Trip }
struct WeatherDay: Codable, Hashable { let date: String; let max: Int; let min: Int; let rain: Int?; let code: Int? }
struct WeatherResult: Decodable { var place: String? = nil; let days: [WeatherDay]; var note: String? = nil }

struct SeasonInfo: Codable, Hashable { let n: Int; let name: String?; let count: Int }
struct EpisodeInfo: Codable, Hashable, Identifiable { let n: Int; let name: String?; let air: String?; let ratings: [String: Int]; var id: Int { n } }
struct EpisodeOverall: Codable, Equatable { let couple: Double?; let byMember: [String: Double] }
struct EpisodesResult: Codable, Equatable { let seasons: [SeasonInfo]; let season: Int; let episodes: [EpisodeInfo]; let overall: EpisodeOverall }

struct Found: Codable, Identifiable, Hashable {
    var id: String { "\(mediaType)-\(tmdbId)" }
    let tmdbId: Int
    let mediaType: String
    let title: String
    var originalTitle: String? = nil
    let year: Int?
    var posterPath: String? = nil
    var posterUrl: String? = nil
    var isAnime: Bool = false
    var vote: Double? = nil
    var inList: Bool? = nil
    var because: String? = nil
    var candidate: Candidate { Candidate(tmdbId: tmdbId, mediaType: mediaType, title: title, originalTitle: originalTitle, year: year, posterPath: posterPath, posterUrl: posterUrl, isAnime: isAnime) }
}
struct FoundList: Decodable { let results: [Found]; var pages: Int? = nil; var because: [String]? = nil }
struct Genre: Codable, Hashable, Identifiable { let id: Int; let name: String }
struct GenresResult: Decodable { let genres: [Genre] }

struct HistoryItem: Codable, Identifiable, Hashable {
    let kind: String   // memory | date | film
    var at: String
    let id: String
    var title: String
    var note: String? = nil
    var photoUrl: String? = nil
    var place: String? = nil
    var addedBy: String? = nil
    var mediaType: String? = nil
    var backdropUrl: String? = nil
    var ratings: [String: Int]? = nil
    var avg: Double? = nil
    var reviews: [ReviewLine]? = nil
    var lat: Double? = nil
    var lon: Double? = nil
    var temp: Int? = nil
    var count: Int? = nil
    var photos: [String]? = nil
    /// An album: every photo with its own date, place and note; every place once.
    var shots: [AlbumPhoto]? = nil
    var places: [AlbumPlace]? = nil
}
struct ReviewLine: Codable, Hashable { let memberId: String; let text: String }
struct HistoryResult: Decodable { let items: [HistoryItem] }
struct MemoryResult: Decodable { let memory: HistoryItemLite }
struct HistoryItemLite: Decodable { let id: String }

extension API {
    struct ShiftBody4: Encodable {
        let date: String; let value: String?; var start: String? = nil; var end: String? = nil
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(date, forKey: .date); try c.encode(value, forKey: .value)
            try c.encodeIfPresent(start, forKey: .start); try c.encodeIfPresent(end, forKey: .end)
        }
        private enum K: String, CodingKey { case date, value, start, end }
    }
    struct JarBody: Encodable { let category: String; let visibility: String; let purpose: String?; let due: String?; let monthly: Double? }
    struct PersonBody: Encodable { let name: String; let relation: String?; let birthday: String; let year: Int? }
    struct MemoryBody: Encodable {
        let title: String; let date: String; let note: String?
        var eventId: String? = nil; var lat: Double? = nil; var lon: Double? = nil; var place: String? = nil; var takenAt: Date? = nil
    }
    struct RemindBody: Encodable { let title: String; let date: String; let movieUrl: String? }
    struct EpisodeScore: Encodable {
        let score: Int?
        func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: K.self); try c.encode(score, forKey: .score) }
        private enum K: String, CodingKey { case score }
    }

    func schedule4() async throws -> Schedule4 { try await get("/schedule") }
    func setShift4(date: String, value: String?, start: String? = nil, end: String? = nil) async throws {
        let _: OkResult = try await send("PUT", "/schedule/shifts", ShiftBody4(date: date, value: value, start: start, end: end))
    }
    func finance4() async throws -> Finance4 { try await get("/finance") }
    func setJar(_ id: String, _ b: JarBody) async throws { let _: OkResult = try await send("PUT", "/finance/jars/\(id)", b) }
    func people() async throws -> [Person] { (try await get("/people") as PeopleResult).people }
    func addPerson(_ b: PersonBody) async throws -> Person { (try await send("POST", "/people", b) as PersonResult).person }
    func deletePerson(_ id: String) async throws { try await delete("/people/\(id)") }
    func trips() async throws -> [Trip] { (try await get("/trips") as TripsResult).trips }
    func saveTrip(_ t: Trip) async throws -> Trip {
        t.id.isEmpty ? (try await send("POST", "/trips", t) as TripResult).trip : (try await send("PATCH", "/trips/\(t.id)", t) as TripResult).trip
    }
    func deleteTrip(_ id: String) async throws { try await delete("/trips/\(id)") }
    func tripWeather(_ id: String) async throws -> WeatherResult { try await get("/trips/\(id)/weather") }
    func remind(title: String, date: String, movieUrl: String?) async throws { let _: OkResult = try await send("POST", "/cinema/remind", RemindBody(title: title, date: date, movieUrl: movieUrl)) }
    func unremind(title: String) async throws {
        let e = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? title
        let _: OkResult = try await send("DELETE", "/cinema/remind?title=\(e)", Empty())
    }
    func episodes(_ id: String, season: Int?) async throws -> EpisodesResult { try await get("/watch/\(id)/episodes" + (season.map { "?season=\($0)" } ?? "")) }
    func rateEpisode(_ id: String, season: Int, episode: Int, score: Int?) async throws { let _: WatchResult = try await send("PUT", "/watch/\(id)/episodes/\(season)/\(episode)", EpisodeScore(score: score)) }
    func genres(_ type: String) async throws -> [Genre] { (try await get("/watch/genres?type=\(type == "movie" ? "movie" : "tv")") as GenresResult).genres }
    func discover(type: String, genre: Int?, from: String?, to: String?, minRating: Int?, sort: String, page: Int = 1) async throws -> [Found] {
        var q = ["type=\(type)", "sort=\(sort)", "page=\(page)"]
        if let genre { q.append("genre=\(genre)") }
        if let from, !from.isEmpty { q.append("from=\(from)") }
        if let to, !to.isEmpty { q.append("to=\(to)") }
        if let minRating { q.append("minRating=\(minRating)") }
        return (try await get("/watch/discover?" + q.joined(separator: "&")) as FoundList).results
    }
    func recommend() async throws -> FoundList { try await get("/watch/recommend") }
    func history() async throws -> [HistoryItem] { (try await get("/history") as HistoryResult).items }
    func addMemory(_ b: MemoryBody) async throws -> String { (try await send("POST", "/memories", b) as MemoryResult).memory.id }
    func uploadMemoryPhoto(_ id: String, jpeg: Data) async throws { let _: MemoryResult = try await upload("/memories/\(id)/photo", jpeg: jpeg) }
}
