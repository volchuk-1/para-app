import Foundation

// MARK: - Events & invitations

enum InviteStatus: String, Codable { case pending, accepted, reschedule, cancelled }

struct Invitation: Codable, Equatable, Hashable {
    var dress: String?
    var message: String?
    var coverUrl: String?
    var status: InviteStatus
    var replyNote: String?
    var answeredAt: Date?
}

struct Event: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var ownerId: String?
    var title: String
    var startsAt: Date
    var endsAt: Date?
    var place: String?
    var mapUrl: String?
    var note: String?
    let createdBy: String
    var invitation: Invitation?

    var isOurs: Bool { ownerId == nil }
    var isLiveInvitation: Bool { invitation != nil && invitation?.status != .cancelled }
}

struct EventsResult: Decodable { let events: [Event] }
struct EventResult: Decodable { let event: Event }

/// Body for POST/PATCH /events and POST /invitations.
struct EventDraft: Encodable {
    var ownerId: String?
    var title: String
    var startsAt: Date
    var endsAt: Date?
    var place: String?
    var mapUrl: String?
    var note: String?
    var dress: String?
    var message: String?

    // ownerId must be sent as null for "ours", so encode it explicitly.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ownerId, forKey: .ownerId)
        try c.encode(title, forKey: .title)
        try c.encode(startsAt, forKey: .startsAt)
        try c.encode(endsAt, forKey: .endsAt)
        // Always sent (null clears a field on the server).
        try c.encode(place, forKey: .place)
        try c.encode(mapUrl, forKey: .mapUrl)
        try c.encode(note, forKey: .note)
        try c.encode(dress, forKey: .dress)
        try c.encode(message, forKey: .message)
    }
    private enum CodingKeys: String, CodingKey { case ownerId, title, startsAt, endsAt, place, mapUrl, note, dress, message }
}

// MARK: - Watch

enum WatchStatus: String, Codable, CaseIterable, Identifiable {
    case want, watching, done, dropped
    var id: String { rawValue }
    var label: String {
        switch self {
        case .want: return "Хочемо"
        case .watching: return "Дивимось"
        case .done: return "Подивились"
        case .dropped: return "Кинули"
        }
    }
}

struct Candidate: Codable, Identifiable, Hashable {
    var id: String { "\(mediaType)-\(tmdbId)" }
    let tmdbId: Int
    let mediaType: String
    let title: String
    let originalTitle: String?
    let year: Int?
    let posterPath: String?
    let posterUrl: String?
    let isAnime: Bool
}

struct WatchItem: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let tmdbId: Int
    let mediaType: String
    let isAnime: Bool
    let title: String
    let year: Int?
    let posterUrl: String?
    var status: WatchStatus
    var season: Int?
    var episode: Int?
    let sourceUrl: String?
    let addedBy: String
    var ratings: [String: Int]
    var avg: Double?
    var releaseDate: String? = nil
    var releaseInUkraine: Bool? = nil

    var kindLabel: String { isAnime ? "Аніме" : (mediaType == "tv" ? "Серіал" : "Фільм") }
    var episodeLabel: String? {
        guard let s = season, let e = episode else { return nil }
        return "S\(s)E\(e)"
    }
}

struct WatchList: Decodable { let items: [WatchItem] }
struct WatchResult: Decodable { let item: WatchItem }
struct CandidatesResult: Decodable { let candidates: [Candidate] }

// MARK: - Wishes

struct Wish: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var ownerId: String
    let url: String?
    var title: String
    let imageUrl: String?
    var price: Double?
    var currency: String?
    var firstPrice: Double?
    var note: String?
    var status: String
    let addedBy: String
    var dropPercent: Int?

    var priceText: String? {
        guard let price else { return nil }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "uk_UA")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.groupingSeparator = " "
        f.decimalSeparator = ","
        let n = f.string(from: NSNumber(value: price)) ?? "\(price)"
        let sym: String
        switch currency {
        case "UAH", nil: sym = "₴"
        case "USD": sym = "$"
        case "EUR": sym = "€"
        default: sym = currency ?? ""
        }
        return "\(n) \(sym)"
    }
}

struct WishList: Decodable { let wishes: [Wish] }
struct WishResult: Decodable { let wish: Wish }

// MARK: - Home

struct Greeting: Decodable, Equatable { let name: String; let subline: String }

struct WatchMini: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let posterUrl: String?
    let season: Int?
    let episode: Int?
    let mediaType: String
    var episodeLabel: String? {
        guard let s = season, let e = episode else { return nil }
        return "S\(s)E\(e)"
    }
}

enum Tile: Identifiable, Equatable {
    case next(Event)
    case awaiting([Event])
    case watching([WatchMini])
    case want(count: Int, posters: [String])
    case drop([Wish])

    var id: String {
        switch self {
        case .next: return "next"
        case .awaiting: return "awaiting"
        case .watching: return "watching"
        case .want: return "want"
        case .drop: return "drop"
        }
    }
}

/// Decodes a tile, or nothing if the server sends a kind this app version does not know.
private struct LossyTile: Decodable {
    let tile: Tile?
    private enum K: String, CodingKey { case kind, event, events, items, count, posters, wishes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "next": tile = .next(try c.decode(Event.self, forKey: .event))
        case "awaiting": tile = .awaiting(try c.decode([Event].self, forKey: .events))
        case "watching": tile = .watching(try c.decode([WatchMini].self, forKey: .items))
        case "want": tile = .want(count: try c.decode(Int.self, forKey: .count), posters: try c.decode([String].self, forKey: .posters))
        case "drop": tile = .drop(try c.decode([Wish].self, forKey: .wishes))
        default: tile = nil
        }
    }
}

struct HomeResult: Decodable {
    let greeting: Greeting
    let tiles: [Tile]
    private enum K: String, CodingKey { case greeting, tiles }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        greeting = try c.decode(Greeting.self, forKey: .greeting)
        tiles = try c.decode([LossyTile].self, forKey: .tiles).compactMap(\.tile)
    }
}

/// Last `/home` answer as raw JSON, so the app opens offline with the same tiles.
enum HomeCache {
    private static let key = "cache.homeRaw"
    static func save(_ raw: Data) { KeyStore.defaults.set(raw, forKey: key) }
    static func load() -> HomeResult? {
        KeyStore.defaults.data(forKey: key).flatMap { try? API.decoder.decode(HomeResult.self, from: $0) }
    }
}

// MARK: - Share

struct ShareResult: Decodable {
    let kind: String
    let caption: String?
    let candidates: [Candidate]?
    let wish: Wish?
}

extension String {
    /// URL from a server string that may contain spaces or be junk.
    var asURL: URL? {
        URL(string: self) ?? addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
    }
}
