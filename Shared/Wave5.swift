import Foundation

// MARK: - Wave 5: dashboard, widget faces, notes, mood, coin, turn, pomodoro, stats, Spotify, albums, trailers

struct DashEvent: Codable, Hashable { let id: String; let title: String; let startsAt: Date; var place: String? = nil; var inMinutes: Int? = nil }
struct DashMonth: Codable, Hashable { let label: String; let evenings: Int; let films: Int; let books: Int }
struct DashPhoto: Codable, Hashable { let url: String?; let title: String; let date: String?; let yearAgo: Bool }
struct DashFilm: Codable, Hashable { let id: String; let title: String; let season: Int?; let episode: Int?; let mediaType: String; let backdropUrl: String? }
struct PomoState: Codable, Hashable {
    let activity: String; let startedAt: Date; let endsAt: Date; let total: Int; let left: Int; let paused: Bool; let together: Bool
    var leftNow: Int { paused ? left : max(0, Int(endsAt.timeIntervalSinceNow.rounded())) }
}
struct PomoPair: Codable, Hashable { let me: PomoState?; let partner: PomoState? }
struct MoodState: Codable, Hashable { let emoji: String; let at: Date }
struct MoodPair: Codable, Hashable { let me: MoodState?; let partner: MoodState? }
struct NoteItem: Codable, Hashable, Identifiable { let id: String; let memberId: String; let text: String; let photoUrl: String?; let at: Date }
struct TurnInfo: Codable, Hashable { let memberId: String; let name: String }
struct CoinResult: Codable, Hashable { let question: String; let winnerId: String; let winnerName: String; var at: Date? = nil }
struct DashMember: Codable, Hashable { let id: String; let name: String }
/// A dashboard widget: size s | m | l, a stack of faces (several — it turns as a cube), own colours ("#rrggbb").
struct WidgetColors: Codable, Hashable { var bg: String? = nil; var fg: String? = nil; var ac: String? = nil }
struct DashWidget: Codable, Hashable, Identifiable { var id: String; var size: String; var faces: [String]; var colors: WidgetColors? = nil }
struct LayoutResult: Decodable { let layout: [DashWidget] }
struct Dashboard: Codable, Hashable {
    let me: DashMember; let partner: DashMember?
    let daysTogether: Int; let month: DashMonth; let wave: [Int]
    let next: DashEvent?; let soon: Bool; let photo: DashPhoto?; let film: DashFilm?
    let pomo: PomoPair; let mood: MoodPair; let note: NoteItem?; let myNote: NoteItem?
    let turn: TurnInfo; let coin: CoinResult?; let faces: [String]
    var layout: [DashWidget]? = nil
}
struct WidgetPrefs: Codable { let faces: [String]; var all: [String]? = nil }
struct StatsMonth: Codable, Hashable { let month: String; let dates: Int; let films: Int; let touches: Int }
struct StatsScore: Codable, Hashable { let name: String; let avg: Double; let count: Int }
struct Stats: Codable {
    let daysTogether: Int; let dates: Int; let byKind: [String: Int]; let films: Int; let watching: Int; let episodes: Int
    let books: Int; let memories: Int; let touches: Int; let cancelled: Int; let scores: [StatsScore]; let months: [StatsMonth]
}
struct SpotTrack: Codable, Hashable { let playing: Bool; let title: String; let artist: String; let cover: String?; let url: String?; var at: Date? = nil; var progress: Int? = nil; var duration: Int? = nil }
struct SpotSent: Codable, Hashable { let title: String; let artist: String?; let cover: String?; let url: String?; let at: Date }
struct SpotSide: Codable, Hashable { var name: String? = nil; let linked: Bool; let track: SpotTrack?; var sent: SpotSent? = nil }
struct SpotNow: Codable { let ready: Bool; let me: SpotSide; let partner: SpotSide? }
struct SpotConnect: Codable { let ready: Bool; var url: String? = nil }
struct AlbumPhoto: Codable, Hashable, Identifiable { let id: String; let url: String?; let takenAt: Date?; let lat: Double?; let lon: Double?; let place: String?; let temp: Int?; var note: String? = nil }
struct AlbumPlace: Codable, Hashable, Identifiable {
    let place: String?; let lat: Double?; let lon: Double?; let count: Int
    var label: String { place ?? String(format: "%.3f, %.3f", lat ?? 0, lon ?? 0) }
    var id: String { label }
}
struct Album: Codable, Hashable, Identifiable { let id: String; let title: String; let count: Int; let coverUrl: String?; let place: String?; let photos: [AlbumPhoto]; var places: [AlbumPlace]? = nil; var note: String? = nil }
struct AlbumResult: Decodable { let album: Album }
struct Trailer: Codable, Hashable { let key: String; let lang: String }
struct PlayResult: Decodable { let play: PlayState; let status: WatchStatus }
struct RemoteInfo: Decodable { let connected: Bool; let online: Bool; let template: String }
struct RemoteOpen: Decodable { let queued: Bool; let online: Bool; let url: String; let play: PlayState? }
struct TrailerResult: Decodable { let trailer: Trailer? }

extension API {
    struct WidgetsBody: Encodable { let faces: [String] }
    struct LayoutBody: Encodable { let layout: [DashWidget] }
    struct NoteBody: Encodable { let text: String }
    struct NoteResult: Decodable { let note: NoteItem }
    struct EmojiBody: Encodable { let emoji: String }
    struct KindBody: Encodable { let kind: String }
    struct QuickBody: Encodable { let kind: String; let time: String }
    struct QuestionBody: Encodable { let question: String }
    struct PomoBody: Encodable { let activity: String; let minutes: Int; let together: Bool }
    struct PomoMe: Decodable { let me: PomoState? }
    struct FavBody5: Encodable { let fav: Bool }
    struct SongBody: Encodable { let title: String; let artist: String; let cover: String?; let url: String? }
    struct AlbumBody: Encodable { let title: String }
    struct ItemBody: Encodable { let itemId: String? }

    func dashboard() async throws -> Dashboard { try await get("/dashboard") }
    func widgets() async throws -> WidgetPrefs { try await get("/widgets") }
    func setWidgets(_ faces: [String]) async throws { let _: WidgetPrefs = try await send("PUT", "/widgets", WidgetsBody(faces: faces)) }
    func setLayout(_ l: [DashWidget]) async throws -> [DashWidget] { (try await send("PUT", "/widgets", LayoutBody(layout: l)) as LayoutResult).layout }
    func sendNote(_ text: String) async throws -> NoteItem { (try await send("POST", "/notes", NoteBody(text: text)) as NoteResult).note }
    func noteURLPhoto(_ id: String, jpeg: Data) async throws { let _: NoteResult = try await upload("/notes/\(id)/photo", jpeg: jpeg) }
    func setMood(_ e: String) async throws { let _: Empty = try await send("PUT", "/mood", EmojiBody(emoji: e)) }
    func touch(_ kind: String) async throws { let _: OkResult = try await send("POST", "/touch", KindBody(kind: kind)) }
    func coin(_ q: String) async throws -> CoinResult { try await send("POST", "/coin", QuestionBody(question: q)) }
    func turnDone(_ itemId: String?) async throws { let _: TurnInfo = try await send("POST", "/watch/turn", ItemBody(itemId: itemId)) }
    func pomo() async throws -> PomoPair { try await get("/pomo") }
    func startPomo(_ activity: String, minutes: Int, together: Bool) async throws -> PomoState? { (try await send("PUT", "/pomo", PomoBody(activity: activity, minutes: minutes, together: together)) as PomoMe).me }
    func pausePomo() async throws -> PomoState? { (try await send("POST", "/pomo/pause", Empty()) as PomoMe).me }
    func stopPomo() async throws { try await delete("/pomo") }
    func stats() async throws -> Stats { try await get("/stats") }
    func quickEvening(_ kind: String, time: String) async throws { let _: Empty = try await send("POST", "/evening/quick", QuickBody(kind: kind, time: time)) }
    func setFav(_ id: String, _ on: Bool) async throws { let _: Empty = try await send("PUT", "/watch/\(id)/fav", FavBody5(fav: on)) }
    func trailer(watchId: String) async throws -> Trailer? { (try await get("/watch/\(watchId)/trailer") as TrailerResult).trailer }
    func trailer(title: String) async throws -> Trailer? {
        let e = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? title
        return (try await get("/trailer?title=\(e)") as TrailerResult).trailer
    }
    func trailer(tmdbId: Int, mediaType: String) async throws -> Trailer? { (try await get("/trailer?tmdbId=\(tmdbId)&mediaType=\(mediaType)") as TrailerResult).trailer }
    func spotifyNow() async throws -> SpotNow { try await get("/spotify/now") }
    func spotifyConnect() async throws -> SpotConnect { try await get("/spotify/connect") }
    func spotifySend(_ t: SpotTrack) async throws { let _: OkResult = try await send("POST", "/spotify/send", SongBody(title: t.title, artist: t.artist, cover: t.cover, url: t.url)) }
    func newAlbum(_ title: String) async throws -> Album { (try await send("POST", "/albums", AlbumBody(title: title)) as AlbumResult).album }
    func addAlbumPhoto(_ id: String, jpeg: Data, lat: Double?, lon: Double?, place: String?, takenAt: Date?) async throws {
        var q: [String] = []
        if let lat, let lon { q.append("lat=\(lat)"); q.append("lon=\(lon)") }
        if let place, let e = place.addingPercentEncoding(withAllowedCharacters: .alphanumerics) { q.append("place=\(e)") }
        if let takenAt { q.append("takenAt=\(ISO8601DateFormatter().string(from: takenAt))") }
        let _: AlbumResult = try await upload("/albums/\(id)/photos" + (q.isEmpty ? "" : "?" + q.joined(separator: "&")), jpeg: jpeg, method: "POST")
    }
    func deleteAlbum(_ id: String) async throws { try await delete("/albums/\(id)") }

    // wave 6: where we stopped, the laptop, the archive of invitations
    struct PlayBody: Encodable { let action: String; let position: Int? }
    struct OpenBody: Encodable { let watchId: String }
    struct TemplateBody: Encodable { let template: String }
    struct KeyResult: Decodable { let key: String }
    func play(_ id: String, _ action: String, position: Int?) async throws -> PlayResult { try await send("PUT", "/watch/\(id)/play", PlayBody(action: action, position: position)) }
    func remote() async throws -> RemoteInfo { try await get("/remote") }
    func remoteKey() async throws -> String { (try await send("POST", "/remote/key", Empty()) as KeyResult).key }
    func remoteTemplate(_ t: String) async throws { let _: Empty = try await send("PUT", "/remote", TemplateBody(template: t)) }
    func remoteOpen(_ watchId: String) async throws -> RemoteOpen { try await send("POST", "/remote/open", OpenBody(watchId: watchId)) }
    func archiveInvite(_ id: String, _ on: Bool) async throws {
        if on { let _: Empty = try await send("POST", "/invitations/\(id)/archive", Empty()) } else { try await delete("/invitations/\(id)/archive") }
    }
}
