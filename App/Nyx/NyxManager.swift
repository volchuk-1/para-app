import Foundation
import UIKit
import CoreBluetooth
import ActivityKit
import WidgetKit

/// Magic Motion Nyx over our own Bluetooth (protocol «magic-motion-4» of buttplug.io).
/// Nothing goes to Magic Motion or to our server from here: the server only relays «На відстані» to the pages,
/// the pages hand it to this file. Every disconnection means strength 0.
///
/// One write at a time: while a write is waiting for its answer, only the newest strength waits behind it.
/// Rhythms are counted by the wall clock; with the app in front a write goes every 0.12 s, in the background the next
/// write goes right after the answer to the last one (the answers are what keeps iOS letting the app run).
final class NyxManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = NyxManager()

    static let svc = CBUUID(string: "78667579-7B48-43DB-B8C5-7928A6B0A335")
    static let txID = CBUUID(string: "78667579-A914-49A4-8333-AA3C0CD8FEDC")
    static let batSvc = CBUUID(string: "180F")
    static let batChr = CBUUID(string: "2A19")
    static let controlKind = "com.volchuk.para.control.nyx"

    private let defaults = UserDefaults(suiteName: Shared.group) ?? .standard
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var tx: CBCharacteristic?
    private var battChr: CBCharacteristic?

    private(set) var level = 0
    private(set) var rhythm: NyxRhythm = .steady
    private(set) var battery: Int?
    private(set) var tune = NyxTune.load()
    /// off · scanning · connecting · on
    private(set) var phase = "off"
    private var error: String?
    private var wantOn = false
    private var inFlight = false
    private var lastSent = -1
    private var tickScheduled = false
    private let t0 = Date()
    /// Every call here comes on the main queue (Bluetooth too: its queue is nil), so UIKit may be asked directly.
    private var background: Bool { MainActor.assumeIsolated { UIApplication.shared.applicationState == .background } }
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    /// iOS took the background time back: the rhythm waits, the toy holds the chosen strength (not a random step of it).
    private var paused = false
    private var scanTimer: Timer?
    private var watch: Timer?
    /// «На відстані»: the last word from the far partner; 5 s of silence → 0.
    private var remoteAt: Date?
    private var activity: Activity<NyxAttributes>?
    private var shown: NyxAttributes.ContentState?

    /// The pages listen: `DV.nyxNative(state)`.
    var onChange: (([String: Any]) -> Void)?

    private override init() {
        super.init()
        rhythm = NyxRhythm(rawValue: defaults.string(forKey: "nyx.rhythm") ?? "") ?? .steady
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.wentBack() }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in self?.cameBack() }
        nc.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.halt() }
    }

    /// At launch: the buttons of the plate and of «Пункт керування» come here. If the toy was paired before, iOS may also
    /// wake the app for it — the Bluetooth manager is made at once then (it asks no permission: it was given already).
    static func install() {
        NyxHook.run = { cmd in await MainActor.run { NyxManager.shared.apply(cmd) } }
        if UserDefaults(suiteName: Shared.group)?.string(forKey: "nyx.id") != nil { _ = shared.manager() }
    }

    private func manager() -> CBCentralManager {
        if let central { return central }
        let c = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.volchuk.para.nyx"])
        central = c
        return c
    }

    // MARK: commands

    func apply(_ cmd: NyxCmd) {
        switch cmd {
        case .step(let d):
            if phase != "on" { power(true) }
            set(level: level + d)
        case .nextRhythm:
            set(rhythm: rhythm.next)
        case .stop:
            set(level: 0)
        case .power(let on):
            power(on)
        }
    }

    func power(_ on: Bool) {
        wantOn = on
        defaults.set(on, forKey: NyxHook.onKey)
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadControls(ofKind: Self.controlKind) }
        if on {
            error = nil
            if phase == "on" { set(level: max(level, defaults.integer(forKey: "nyx.level"))); return }
            level = defaults.integer(forKey: "nyx.level")   // «увімкнути» — with the last strength
            connect()
        } else {
            halt()
            if let p = peripheral { manager().cancelPeripheralConnection(p) }
            phase = "off"
            endActivity()
            changed()
        }
    }

    func set(level l: Int) {
        level = max(0, min(100, l))
        if level > 0 { defaults.set(level, forKey: "nyx.level") }
        holdBackground()
        pump(); changed()
    }

    func set(rhythm r: NyxRhythm) {
        rhythm = r
        defaults.set(r.rawValue, forKey: "nyx.rhythm")
        holdBackground()
        pump(); changed()
    }

    /// The settings of the rhythms (from this screen, or from the far partner's screen).
    func set(tune t: NyxTune) {
        tune = t
        t.save()
        pump(); changed()
    }

    /// «На відстані»: the far partner's strength and rhythm. Silence for 5 s (or the app going to the background) → 0.
    func remote(level l: Int?, rhythm r: NyxRhythm?, on: Bool) {
        if !on { remoteAt = nil; set(level: 0); return }
        remoteAt = Date()
        if let r, r != rhythm { rhythm = r }
        if let l { level = max(0, min(100, l)) }
        pump(); changed()
        if watch == nil {
            watch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, let at = self.remoteAt else { return }
                if Date().timeIntervalSince(at) > 5 { self.remoteAt = nil; self.set(level: 0) }
            }
        }
    }

    /// 0 at once, whatever is going on.
    func halt() {
        level = 0
        remoteAt = nil
        if let p = peripheral, let tx, p.state == .connected {
            // past the queue: iOS keeps the order of writes, so this 0 is the last word even if one is on its way
            p.writeValue(Self.cmd(0), for: tx, type: .withResponse)
            inFlight = true
            lastSent = 0
        }
        changed()
    }

    // MARK: Bluetooth

    private func connect() {
        let c = manager()
        guard c.state == .poweredOn else {
            phase = "connecting"; changed()   // centralManagerDidUpdateState goes on from here
            return
        }
        if let p = peripheral, p.state == .connected { ready(p); return }
        if let s = defaults.string(forKey: "nyx.id"), let id = UUID(uuidString: s), let p = c.retrievePeripherals(withIdentifiers: [id]).first {
            peripheral = p; p.delegate = self
            phase = "connecting"; changed()
            c.connect(p)   // never times out: it connects the moment the toy is near and awake
            scan()        // a new toy, or the old one renamed: look around too
            return
        }
        scan()
    }

    private func scan() {
        let c = manager()
        guard !c.isScanning else { return }
        if phase != "connecting" { phase = "scanning" }
        changed()
        // in the background iOS scans only for named services (a toy paired before is found by its id, above)
        c.scanForPeripherals(withServices: background ? [Self.svc] : nil)
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self, self.phase != "on" else { return }
            self.manager().stopScan()
            if self.peripheral?.state != .connecting {
                self.phase = "off"; self.wantOn = false
                self.defaults.set(false, forKey: NyxHook.onKey)
                self.error = "Не знайшла Nyx поруч. Увімкни її (коротко натисни кнопку) і спробуй ще."
                self.changed()
            }
        }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            if wantOn && phase != "on" { connect() }
        case .unauthorized:
            error = "DaVincit не має доступу до Bluetooth: Параметри → DaVincit → Bluetooth."
            phase = "off"; changed()
        case .poweredOff:
            error = "Bluetooth вимкнено."
            gone()
        default:
            break
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let p = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
            peripheral = p; p.delegate = self
            wantOn = defaults.bool(forKey: NyxHook.onKey)
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = (p.name ?? ad[CBAdvertisementDataLocalNameKey] as? String ?? "").lowercased()
        let svcs = ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard name.hasPrefix("nyx") || svcs.contains(Self.svc) else { return }
        c.stopScan(); scanTimer?.invalidate()
        if let old = peripheral, old.identifier != p.identifier { c.cancelPeripheralConnection(old) }
        peripheral = p; p.delegate = self
        phase = "connecting"; changed()
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        c.stopScan(); scanTimer?.invalidate()
        defaults.set(p.identifier.uuidString, forKey: "nyx.id")
        p.discoverServices([Self.svc, Self.batSvc])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        gone()
        if wantOn { c.connect(p) }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        gone()
        // it was not us: keep waiting for it (iOS connects when it is back in range)
        if wantOn { phase = "connecting"; changed(); c.connect(p) }
    }

    private func gone() {
        tx = nil; battChr = nil; inFlight = false; lastSent = -1; tickScheduled = false
        level = 0; remoteAt = nil
        phase = wantOn ? "connecting" : "off"
        endActivity()
        changed()
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            if s.uuid == Self.svc { p.discoverCharacteristics([Self.txID], for: s) }
            if s.uuid == Self.batSvc { p.discoverCharacteristics([Self.batChr], for: s) }
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == Self.txID { tx = ch; ready(p) }
            if ch.uuid == Self.batChr {
                battChr = ch
                p.readValue(for: ch)
                if ch.properties.contains(.notify) { p.setNotifyValue(true, for: ch) }
            }
        }
    }

    private func ready(_ p: CBPeripheral) {
        guard tx != nil else { return }
        phase = "on"; error = nil
        wantOn = true
        defaults.set(true, forKey: NyxHook.onKey)
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadControls(ofKind: Self.controlKind) }
        lastSent = -1
        pump(); changed()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == Self.batChr, let v = ch.value?.first { battery = Int(v); changed() }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        inFlight = false
        guard rhythm != .steady, level > 0, !paused else { pump(); return }
        if background { pump(force: true); return }   // in the background: right after the answer
        guard !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.tickScheduled = false
            self?.pump(force: true)
        }
    }

    static func cmd(_ s: Int) -> Data {
        let v = UInt8(max(0, min(100, s)))
        return Data([0x10, 0xff, 0x04, 0x0a, 0x32, 0x32, 0x00, 0x04, 0x08, v, 0x64, 0x00, 0x04, 0x08, v, 0x64, 0x01])
    }

    /// Sends what the toy should do now, unless a write is still waiting for its answer (then the answer calls this again).
    private func pump(force: Bool = false) {
        guard let p = peripheral, let tx, p.state == .connected, !inFlight else { return }
        let out = (paused ? NyxRhythm.steady : rhythm).output(level: level, at: Date().timeIntervalSince(t0), tune: tune)
        if out == lastSent && !force { return }
        if out == lastSent && (rhythm == .steady || level == 0) { return }
        inFlight = true
        lastSent = out
        p.writeValue(Self.cmd(out), for: tx, type: .withResponse)
    }

    private func wentBack() {
        // «На відстані» needs the app open: in the background nobody could stop it
        if remoteAt != nil { remoteAt = nil; set(level: 0) }
        holdBackground()
        pump(force: true)
    }

    /// A rhythm in the background lives as long as iOS lets the app run (about half a minute after the app leaves the
    /// screen or after a button of the plate). Then: the chosen strength, steady, and the plate says so.
    private func holdBackground() {
        guard background, rhythm != .steady, level > 0, bgTask == .invalid else { return }
        paused = false
        bgTask = MainActor.assumeIsolated { UIApplication.shared.beginBackgroundTask(withName: "nyx") { [weak self] in self?.pauseRhythm() } }
    }

    private func pauseRhythm() {
        paused = true
        lastSent = -1
        pump(force: true)   // if a write is on its way, its answer sends the steady strength
        changed()
        endBg()
    }

    private func cameBack() {
        endBg()
        if paused { paused = false; pump(force: true); changed() }
    }

    private func endBg() {
        if bgTask != .invalid { let t = bgTask; MainActor.assumeIsolated { UIApplication.shared.endBackgroundTask(t) }; bgTask = .invalid }
    }

    // MARK: the plate and the pages

    private func changed() {
        onChange?(snapshot())
        syncActivity()
    }

    func snapshot() -> [String: Any] {
        var s: [String: Any] = ["phase": phase, "level": level, "rhythm": rhythm.rawValue, "remote": remoteAt != nil, "background": background, "paused": paused, "tune": tune.dict]
        if let battery { s["battery"] = battery }
        if let error { s["error"] = error }
        if let n = peripheral?.name { s["name"] = n }
        return s
    }

    private func syncActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard phase == "on" else { return }
        let st = NyxAttributes.ContentState(level: level, rhythm: rhythm, battery: battery, remote: remoteAt != nil, paused: paused)
        if st == shown { return }
        shown = st
        let content = ActivityContent(state: st, staleDate: nil)
        if let a = activity ?? Activity<NyxAttributes>.activities.first {
            activity = a
            Task { await a.update(content) }
        } else {
            activity = try? Activity.request(attributes: NyxAttributes(name: peripheral?.name ?? "Nyx"), content: content, pushType: nil)
        }
    }

    private func endActivity() {
        shown = nil
        let all = Activity<NyxAttributes>.activities
        activity = nil
        for a in all { Task { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}
