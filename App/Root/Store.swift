import SwiftUI

/// Everything the screens show. Loads from the server, keeps the last answer on the phone for instant/offline start.
@MainActor
final class Store: ObservableObject {
    @Published var home: HomeResult?
    @Published var events: [Event] = []
    @Published var watch: [WatchItem] = []
    @Published var wishes: [Wish] = []
    @Published var notifications: [AppNotification] = []
    @Published var unread = 0
    @Published var error: String?
    @Published var offline = false

    private var api: API { API.current() }

    init() {
        events = Cache.load([Event].self, "events") ?? []
        watch = Cache.load([WatchItem].self, "watch") ?? []
        wishes = Cache.load([Wish].self, "wishes") ?? []
        home = HomeCache.load()
    }

    func refreshAll() async {
        await run {
            async let h = self.api.homeRaw()
            async let e = self.api.events(from: Date().addingTimeInterval(-7 * 86400), to: Date().addingTimeInterval(120 * 86400))
            async let w = self.api.watchList()
            async let ws = self.api.wishes()
            let (home, events, watch, wishes) = try await (h, e, w, ws)
            self.home = home.0
            HomeCache.save(home.1)
            self.setEvents(events)
            self.watch = watch; Cache.save(watch, "watch")
            self.wishes = wishes; Cache.save(wishes, "wishes")
        }
        await refreshNotifications()
    }

    func refreshNotifications() async {
        guard let r = try? await api.notifications() else { return }
        notifications = r.items
        unread = r.unread
    }

    func markNotificationsRead() async {
        guard unread > 0 else { return }
        unread = 0
        try? await api.markNotificationsRead()
    }

    func setEvents(_ e: [Event]) {
        events = e.sorted { $0.startsAt < $1.startsAt }
        Cache.save(events, "events")
        Reminders.sync(events)
        LiveDates.sync(events)
    }

    func upsert(_ e: Event) {
        var list = events.filter { $0.id != e.id }
        list.append(e)
        setEvents(list)
    }

    func removeEvent(_ id: String) { setEvents(events.filter { $0.id != id }) }

    func upsert(_ w: WatchItem) {
        if let i = watch.firstIndex(where: { $0.id == w.id }) { watch[i] = w } else { watch.insert(w, at: 0) }
        Cache.save(watch, "watch")
    }

    func upsert(_ w: Wish) {
        if let i = wishes.firstIndex(where: { $0.id == w.id }) { wishes[i] = w } else { wishes.insert(w, at: 0) }
        Cache.save(wishes, "wishes")
    }

    /// Runs a server call, turning errors into a banner. Returns false on failure.
    @discardableResult
    func run(_ work: @escaping @MainActor () async throws -> Void) async -> Bool {
        do {
            try await work()
            offline = false
            error = nil
            return true
        } catch APIError.offline {
            offline = true
            error = APIError.offline.localizedDescription + " Зміни не збережено."
            return false
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

/// Small JSON cache in the App Group.
enum Cache {
    static func save<T: Encodable>(_ v: T, _ key: String) {
        KeyStore.defaults.set(try? API.encoder.encode(v), forKey: "cache." + key)
    }
    static func load<T: Decodable>(_ t: T.Type, _ key: String) -> T? {
        KeyStore.defaults.data(forKey: "cache." + key).flatMap { try? API.decoder.decode(T.self, from: $0) }
    }
}
