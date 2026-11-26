import Foundation
import WebKit
import EventKit
import MapKit
import UIKit

/// «Без інтернету»: after every good start the app keeps a copy of the pages (a web archive); when the network
/// is not there, it opens that copy instead of the «Немає звʼязку» screen. Voice notes recorded then wait on the
/// phone and go up by themselves later (that part lives in the pages).
enum OfflineCopy {
    private static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("offline-pages.webarchive")
    }

    static var exists: Bool { file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    @MainActor
    static func save(from web: WKWebView) {
        guard let file, web.url?.host == KeyStore.serverURL.host else { return }
        web.createWebArchiveData { result in
            guard case .success(let data) = result, data.count > 10_000 else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Opens the copy; true when there was one.
    @MainActor
    static func open(in web: WKWebView) -> Bool {
        guard let file, let data = try? Data(contentsOf: file) else { return false }
        web.load(data, mimeType: "application/x-webarchive", characterEncodingName: "utf-8", baseURL: KeyStore.serverURL)
        return true
    }
}

/// «Календар iPhone» in both directions (only after a «так» in the app):
///  - our events (ours, mine, accepted invitations) live in a calendar «DaVincit» on the phone and follow the changes;
///  - the busy times of the phone's own calendars go to our server as «from–to» only — no titles, no places.
enum CalendarSync {
    private static let store = EKEventStore()
    private static let calendarKey = "dv-cal-id"
    private static let onKey = "dv-cal-sync"
    private static var running = false
    private static var lastRun = Date.distantPast

    static var isOn: Bool { UserDefaults.standard.bool(forKey: onKey) }

    static func setOn(_ on: Bool, done: @escaping (Bool) -> Void) {
        guard on else {
            UserDefaults.standard.set(false, forKey: onKey)
            Task { _ = await api("DELETE", "availability/phone", nil) }
            done(false)
            return
        }
        store.requestFullAccessToEvents { granted, _ in
            UserDefaults.standard.set(granted, forKey: onKey)
            DispatchQueue.main.async { done(granted) }
            if granted { run(force: true) }
        }
    }

    /// Called when the app comes to the front; at most every five minutes.
    static func run(force: Bool = false) {
        guard isOn, !running, force || Date().timeIntervalSince(lastRun) > 300,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        running = true
        lastRun = Date()
        Task {
            defer { running = false }
            await pushOurs()
            await sendBusy()
        }
    }

    private static func ourCalendar() -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: calendarKey), let c = store.calendar(withIdentifier: id) { return c }
        let c = EKCalendar(for: .event, eventStore: store)
        c.title = "DaVincit"
        c.cgColor = UIColor(red: 0x52 / 255, green: 0x5E / 255, blue: 0x4F / 255, alpha: 1).cgColor
        // the same place the phone keeps its other calendars (iCloud, else on the phone)
        c.source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .calDAV }
            ?? store.sources.first { $0.sourceType == .local }
        guard c.source != nil, (try? store.saveCalendar(c, commit: true)) != nil else { return nil }
        UserDefaults.standard.set(c.calendarIdentifier, forKey: calendarKey)
        return c
    }

    private static func pushOurs() async {
        let from = Date().addingTimeInterval(-86400), to = Date().addingTimeInterval(60 * 86400)
        let f = ISO8601DateFormatter()
        guard let cal = ourCalendar(),
              let json = await api("GET", "events?from=\(f.string(from: from))&to=\(f.string(from: to))", nil),
              let events = json["events"] as? [[String: Any]] else { return }
        let me = KeyStore.cachedMe?.me.id
        let parse: (Any?) -> Date? = { v in
            guard let s = v as? String else { return nil }
            let g = ISO8601DateFormatter(); g.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return g.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        var wanted: [String: [String: Any]] = [:]
        for e in events {
            guard let id = e["id"] as? String else { continue }
            let owner = e["ownerId"] as? String
            let status = (e["invitation"] as? [String: Any])?["status"] as? String
            // ours, mine, or an invitation we both said yes to; not the other one's private events
            if owner == nil || owner == me || status == "accepted" { wanted[id] = e }
        }
        let existing = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [cal]))
        var seen = Set<String>()
        for ev in existing {
            guard let id = ev.url?.absoluteString.replacingOccurrences(of: "davincit://event/", with: "") else { continue }
            if let e = wanted[id], let s = parse(e["startsAt"]) {
                ev.title = e["title"] as? String ?? ev.title
                ev.startDate = s
                ev.endDate = parse(e["endsAt"]) ?? s.addingTimeInterval(2 * 3600)
                ev.location = e["place"] as? String
                try? store.save(ev, span: .thisEvent, commit: false)
                seen.insert(id)
            } else {
                try? store.remove(ev, span: .thisEvent, commit: false)
            }
        }
        for (id, e) in wanted where !seen.contains(id) {
            guard let s = parse(e["startsAt"]) else { continue }
            let ev = EKEvent(eventStore: store)
            ev.calendar = cal
            ev.title = e["title"] as? String ?? "Подія"
            ev.startDate = s
            ev.endDate = parse(e["endsAt"]) ?? s.addingTimeInterval(2 * 3600)
            ev.location = e["place"] as? String
            ev.url = URL(string: "davincit://event/\(id)")
            ev.addAlarm(EKAlarm(relativeOffset: -3600))
            try? store.save(ev, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }

    private static func sendBusy() async {
        let from = Date(), to = Date().addingTimeInterval(21 * 86400)
        let mine = UserDefaults.standard.string(forKey: calendarKey)
        let cals = store.calendars(for: .event).filter { $0.calendarIdentifier != mine && $0.type != .birthday && !$0.title.lowercased().contains("свят") && $0.type != .subscription }
        guard !cals.isEmpty else { return }
        let f = ISO8601DateFormatter()
        let busy = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: cals))
            .filter { !$0.isAllDay && $0.availability != .free && $0.endDate > $0.startDate }
            .prefix(500)
            .map { ["start": f.string(from: $0.startDate), "end": f.string(from: $0.endDate)] }
        _ = await api("PUT", "availability/phone", ["busy": Array(busy)])
    }

    @discardableResult
    static func api(_ method: String, _ path: String, _ body: [String: Any]?) async -> [String: Any]? {
        guard let key = KeyStore.deviceKey, let url = URL(string: path, relativeTo: KeyStore.serverURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: req), ((response as? HTTPURLResponse)?.statusCode ?? 500) < 300 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// A real map for the window of a date: Apple Maps draws it on the phone (nothing goes to anyone else);
/// the place of the date and, when shared, where each of us is.
enum MapPicture {
    static func make(place: String, points: [(lat: Double, lon: Double, color: UIColor)], near: CLLocationCoordinate2D?) async -> String? {
        var all = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        var target: CLLocationCoordinate2D?
        if !place.isEmpty {
            let search = MKLocalSearch.Request()
            search.naturalLanguageQuery = place
            if let c = near ?? all.first { search.region = MKCoordinateRegion(center: c, latitudinalMeters: 40_000, longitudinalMeters: 40_000) }
            target = try? await MKLocalSearch(request: search).start().mapItems.first?.placemark.coordinate
        }
        if let target { all.append(target) }
        guard !all.isEmpty else { return nil }
        let lats = all.map(\.latitude), lons = all.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.006, (lats.max()! - lats.min()!) * 1.6), longitudeDelta: max(0.006, (lons.max()! - lons.min()!) * 1.6))
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: center, span: span)
        o.size = CGSize(width: 340, height: 190)
        o.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        guard let shot = try? await MKMapSnapshotter(options: o).start() else { return nil }
        let img = UIGraphicsImageRenderer(size: o.size).image { _ in
            shot.image.draw(at: .zero)
            let dot = { (c: CLLocationCoordinate2D, color: UIColor, r: CGFloat) in
                let p = shot.point(for: c)
                UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: p.x - r - 2, y: p.y - r - 2, width: (r + 2) * 2, height: (r + 2) * 2)).fill()
                color.setFill(); UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)).fill()
            }
            if let target { dot(target, UIColor(red: 0.42, green: 0.23, blue: 0.2, alpha: 1), 8) }
            for p in points { dot(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon), p.color, 6) }
        }
        guard let data = img.jpegData(compressionQuality: 0.82) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}
