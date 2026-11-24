import Foundation

// MARK: - Wave 2 models (server: books, availability, schedule, cinema, finance, archive)

struct SiteRating: Codable, Equatable, Hashable {
    var tmdb: Double?
    var imdb: Double?
    var rt: Int?
}

struct Book: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var ownerId: String
    var title: String
    var author: String?
    var pages: Int?
    var coverUrl: String?
    var isbn: String?
    var status: BookStatus
    var currentPage: Int?

    var progress: Double {
        guard let p = pages, p > 0, let c = currentPage else { return 0 }
        return min(1, Double(c) / Double(p))
    }
}

enum BookStatus: String, Codable, CaseIterable, Identifiable {
    case reading, done, want, paused
    var id: String { rawValue }
    var label: String {
        switch self {
        case .reading: return "Читаю"
        case .done: return "Прочитав(ла)"
        case .want: return "Хочу"
        case .paused: return "Відклав(ла)"
        }
    }
}

struct BooksResult: Decodable { let books: [Book] }
struct BookResult: Decodable { let book: Book }
struct IsbnFound: Decodable, Equatable, Hashable { let title: String; let author: String?; let pages: Int?; let coverUrl: String?; let isbn: String? }
struct BookSearchResult: Decodable { let results: [IsbnFound] }
struct IsbnResult: Decodable { let found: IsbnFound? }

struct DayBlock: Codable, Equatable, Hashable {
    let kind: String   // work, activity, maybe, event, ours
    let label: String?
    let start: String  // "HH:MM"
    let end: String
}

struct DayBlocks: Codable, Equatable, Hashable {
    let me: [DayBlock]
    let partner: [DayBlock]
}

struct DayPlan: Codable, Equatable, Hashable, Identifiable {
    let date: String
    let weekday: Int
    let status: String  // free, day, home, maybe, busy, plan
    let freeFrom: String
    let plan: String?
    let meOff: Bool
    let partnerOff: Bool
    var meKnown: Bool? = nil        // nil from an older server = known
    var partnerKnown: Bool? = nil
    let blocks: DayBlocks
    var id: String { date }
    var isFree: Bool { status == "free" || status == "day" }
    /// ♥ only when both have entered a schedule — otherwise «free» means «nobody said otherwise».
    var bothFree: Bool { isFree && (partnerKnown ?? true) && (meKnown ?? true) }
}

struct AvailabilityResult: Decodable { let days: [DayPlan] }

struct ScheduleRule: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let memberId: String
    let kind: String
    let label: String?
    let weekdays: [Int]
    let start: String
    let end: String
    let sometimes: Bool
}

struct ShiftDay: Codable, Equatable, Hashable { let memberId: String; let date: String; let value: String }
struct ScheduleResult: Codable, Equatable { let rules: [ScheduleRule]; let shifts: [ShiftDay] }

struct CinemaSession: Codable, Equatable, Hashable, Identifiable {
    let title: String
    let date: String
    let time: String
    let tags: [String]
    let buyUrl: String
    var id: String { buyUrl }
}

struct SessionsResult: Decodable { let cinema: String; let sessions: [CinemaSession] }

struct Jar: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let balance: Double
    let goal: Double?
    let topUpUrl: String?
}

struct FinanceGoal: Codable, Equatable { let title: String; let target: Double; let jarIds: [String]; let saved: Double; let percent: Int }
struct FinanceResult: Codable, Equatable { let connected: Bool; let jars: [Jar]; let goal: FinanceGoal?; var error: String? = nil }

struct ArchiveItem: Codable, Equatable, Hashable, Identifiable { let id: String; let title: String; let note: String? }
struct ArchiveFolder: Codable, Equatable, Hashable, Identifiable { let kind: String; let title: String; let count: Int; let items: [ArchiveItem]; var id: String { kind } }
struct ArchiveResult: Decodable { let folders: [ArchiveFolder] }

// MARK: - pure helpers (tested)

enum Evening {
    /// Label of a day's evening, as the bar and the week show it.
    static func label(_ d: DayPlan) -> String {
        switch d.status {
        case "free": return "Вільний вечір"
        case "day": return "Вільний день"
        case "home": return "Лише вдома"
        case "maybe": return "Може бути"
        case "plan": return d.plan ?? "Заплановано"
        default: return "Зайнято"
        }
    }

    static func note(_ d: DayPlan, partner: String) -> String {
        if d.meKnown == false { return "Внеси свій графік роботи — тоді буде видно вільні вечори" }
        if d.partnerKnown == false {
            switch d.status {
            case "day": return "Ти вільний весь день · \(partner) ще не внесла графік"
            case "free": return "Ти вільний з \(d.freeFrom) · \(partner) ще не внесла графік"
            case "plan": return d.plan ?? ""
            default: return "Ти зайнятий до \(d.freeFrom) · \(partner) ще не внесла графік"
            }
        }
        switch d.status {
        case "plan": return d.plan ?? ""
        case "day": return "Обоє вільні весь день"
        case "free": return "Обоє вільні з \(d.freeFrom)" + (d.partnerOff && !d.meOff ? " · у \(partner) вихідний" : "")
        case "home": return "Зайняті до \(d.freeFrom) — встигнете лише фільм удома"
        case "maybe": return "Може бути зайнято («інколи») — краще спитати"
        default: return "Вечір зайнятий"
        }
    }

    /// "HH:MM" → minutes.
    static func minutes(_ s: String) -> Int {
        let p = s.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : 0
    }

    /// Monday of the week that contains `date` ("YYYY-MM-DD").
    static func monday(of date: Date, cal: Calendar = Dock.calendar) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    static func iso(_ d: Date, cal: Calendar = Dock.calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ s: String, cal: Calendar = Dock.calendar) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }
}

extension WatchItem {
    /// Bottom bar of the film page: what the main action is.
    enum MainAction: Equatable { case nextEpisode, invite, start, done }
    var mainAction: MainAction {
        if status == .watching && mediaType == "tv" { return .nextEpisode }
        if mediaType == "movie" && status != .done && status != .dropped { return .invite }
        if status == .want { return .start }
        return .done
    }
}

// MARK: - API

extension API {
    struct ReviewBody: Encodable { let text: String }
    struct BookBody: Encodable {
        var title: String; var author: String?; var pages: Int?; var coverUrl: String?; var isbn: String?; var status: String; var ownerId: String?
    }
    struct BookPatch: Encodable { var status: String?; var currentPage: Int?; var title: String?; var author: String?; var pages: Int? }
    struct RuleBody: Encodable { let kind: String; let label: String?; let weekdays: [Int]; let start: String; let end: String; let sometimes: Bool }
    struct ShiftBody: Encodable {
        let date: String; let value: String?
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(date, forKey: .date)
            try c.encode(value, forKey: .value)
        }
        private enum K: String, CodingKey { case date, value }
    }
    struct GoalBody: Encodable { let title: String; let target: Double; let jarIds: [String] }
    struct OkResult: Decodable { let ok: Bool }

    func review(_ id: String, text: String) async throws -> WatchItem { (try await send("PUT", "/watch/\(id)/review", ReviewBody(text: text)) as WatchResult).item }
    func sessions(watchId: String) async throws -> [CinemaSession] { (try await get("/cinema/sessions?watchId=\(watchId)") as SessionsResult).sessions }

    func books() async throws -> [Book] { (try await get("/books") as BooksResult).books }
    func addBook(_ b: BookBody) async throws -> Book { (try await send("POST", "/books", b) as BookResult).book }
    func patchBook(_ id: String, _ p: BookPatch) async throws -> Book { (try await send("PATCH", "/books/\(id)", p) as BookResult).book }
    func deleteBook(_ id: String) async throws { try await delete("/books/\(id)") }
    func isbn(_ code: String) async throws -> IsbnFound? {
        let q = code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? code
        return (try await get("/books/isbn/\(q)") as IsbnResult).found
    }
    func searchBooks(_ q: String) async throws -> [IsbnFound] {
        let e = q.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        return (try await get("/books/search?q=\(e)") as BookSearchResult).results
    }
    func uploadBookCover(_ id: String, jpeg: Data) async throws -> Book { (try await upload("/books/\(id)/cover", jpeg: jpeg) as BookResult).book }

    func availability(from: String, to: String) async throws -> [DayPlan] { (try await get("/availability?from=\(from)&to=\(to)") as AvailabilityResult).days }
    func schedule() async throws -> ScheduleResult { try await get("/schedule") }
    func addRule(_ r: RuleBody) async throws { struct R: Decodable {}; let _: R = try await send("POST", "/schedule/rules", r) }
    func deleteRule(_ id: String) async throws { try await delete("/schedule/rules/\(id)") }
    func setShift(date: String, value: String?) async throws { let _: OkResult = try await send("PUT", "/schedule/shifts", ShiftBody(date: date, value: value)) }

    func finance() async throws -> FinanceResult { try await get("/finance") }
    func setGoal(_ g: GoalBody) async throws { let _: OkResult = try await send("PUT", "/finance/goal", g) }
    func archive() async throws -> [ArchiveFolder] { (try await get("/archive") as ArchiveResult).folders }
}
