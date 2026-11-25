import Foundation
import CoreLocation
import MapKit
import Photos
import ActivityKit
import UIKit
import EventKit

/// «Де я» on the way to a date. Works only while a date is near and both of us agreed (the server decides and
/// answers 403 / 409 otherwise — then this stops by itself). One point every ~40 seconds goes to our own server,
/// nowhere else; iOS shows its blue mark while it runs.
final class DateTracker: NSObject, CLLocationManagerDelegate {
    static let shared = DateTracker()

    private let manager = CLLocationManager()
    private var eventId: String?
    private var partnerName = ""
    private var eta: Int?
    private var lastSent = Date.distantPast
    private var startedAt = Date()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start(id: String, partner: String, eta: Int?) {
        if eventId == id { self.eta = eta ?? self.eta; return }
        eventId = id
        partnerName = partner
        self.eta = eta
        startedAt = Date()
        lastSent = .distantPast
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stop() {
        guard eventId != nil else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        if let id = eventId { DateActivity.setPartner(eventId: id, text: nil) }
        eventId = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let id = eventId, let here = locations.last else { return }
        if Date().timeIntervalSince(startedAt) > 4 * 3600 { stop(); return }      // never longer than four hours
        guard Date().timeIntervalSince(lastSent) >= 40, let key = KeyStore.deviceKey else { return }
        lastSent = Date()

        var req = URLRequest(url: KeyStore.serverURL.appendingPathComponent("dates/\(id)/loc"))
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["lat": here.coordinate.latitude, "lon": here.coordinate.longitude, "acc": here.horizontalAccuracy]
        if let eta { body["eta"] = eta }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let name = partnerName
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 403 || code == 409 || code == 404 {            // the date is over, I arrived, or the consent is gone
                DispatchQueue.main.async { self?.stop() }
                return
            }
            guard code == 200, let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let loc = json["loc"] as? [String: Any] else { return }
            var text: String?
            if let p = loc["partner"] as? [String: Any] {
                var parts = [name]
                if let m = p["eta"] as? Int { parts.append("\(m) хв") }
                if p["hidden"] as? Bool == true {
                    parts.append("місце приховано")
                } else if let lat = p["lat"] as? Double, let lon = p["lon"] as? Double {
                    let d = here.distance(from: CLLocation(latitude: lat, longitude: lon))
                    parts.append(d < 950 ? "\(Int((d / 10).rounded()) * 10) м" : String(format: "%.1f км", d / 1000).replacingOccurrences(of: ".", with: ","))
                }
                text = parts.joined(separator: " · ")
            }
            let shown = text
            DispatchQueue.main.async { DateActivity.setPartner(eventId: id, text: shown) }
        }.resume()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { stop() }
    }
}

/// The countdown of a date on the lock screen and in the Dynamic Island; while we are on the way it also says
/// «Дарина · 6 хв · 1,2 км».
enum DateActivity {
    static func start(eventId: String, title: String, place: String, startsAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, startsAt > Date() else { return }
        if Activity<DateAttributes>.activities.contains(where: { $0.attributes.eventId == eventId }) { return }
        let attrs = DateAttributes(eventId: eventId, title: title, place: place)
        let state = DateAttributes.ContentState(startsAt: startsAt)
        _ = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: startsAt))
    }

    static func setPartner(eventId: String, text: String?) {
        for a in Activity<DateAttributes>.activities where a.attributes.eventId == eventId {
            var state = a.content.state
            if state.partner == text { continue }
            state.partner = text
            let next = state
            let stale = a.content.staleDate
            Task { await a.update(ActivityContent(state: next, staleDate: stale)) }
        }
    }

    static func end(eventId: String) {
        for a in Activity<DateAttributes>.activities where a.attributes.eventId == eventId {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

/// How long the way to a place is — counted by the phone itself (Apple Maps), on foot and by car.
enum RouteETA {
    static func find(place: String, from: CLLocationCoordinate2D?) async -> [String: Any] {
        guard let from, !place.isEmpty else { return [:] }
        let search = MKLocalSearch.Request()
        search.naturalLanguageQuery = place
        search.region = MKCoordinateRegion(center: from, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        guard let found = try? await MKLocalSearch(request: search).start(), let target = found.mapItems.first else { return [:] }
        var out: [String: Any] = [:]
        let kinds: [(String, MKDirectionsTransportType)] = [("walk", .walking), ("drive", .automobile)]
        for (key, kind) in kinds {
            let d = MKDirections.Request()
            d.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
            d.destination = target
            d.transportType = kind
            if let r = try? await MKDirections(request: d).calculateETA() {
                out[key] = Int((r.expectedTravelTime / 60).rounded())
                if key == "walk" { out["km"] = (r.distance / 100).rounded() / 10 }
            }
        }
        return out
    }
}

/// «Зберегти на телефон»: the original goes to Photos (the app may only add, it cannot read the library).
enum PhotoSaver {
    static func save(_ data: Data, done: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { done(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }, completionHandler: { ok, _ in
                DispatchQueue.main.async { done(ok) }
            })
        }
    }
}

/// «У календар iPhone»: the date goes into the phone's own calendar with a reminder an hour before.
/// The app may only add events — it cannot read the calendar.
enum CalendarAdd {
    static func add(title: String, start: Date, end: Date, place: String, done: @escaping (Bool) -> Void) {
        let store = EKEventStore()
        store.requestWriteOnlyAccessToEvents { ok, _ in
            guard ok else {
                DispatchQueue.main.async { done(false) }
                return
            }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = start
            event.endDate = end
            event.location = place.isEmpty ? nil : place
            event.calendar = store.defaultCalendarForNewEvents
            event.addAlarm(EKAlarm(relativeOffset: -3600))
            var saved = true
            do { try store.save(event, span: .thisEvent) } catch { saved = false }
            DispatchQueue.main.async { done(saved) }
        }
    }
}
