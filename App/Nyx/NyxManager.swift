import Foundation
import UIKit
import CoreBluetooth
import ActivityKit
import WidgetKit

/// Magic Motion Nyx over our own Bluetooth (protocol «magic-motion-4» of buttplug.io).
/// Nothing goes to Magic Motion or to our server from here: the server only relays «На відстані» to the pages,
/// the pages hand it to this file. Every disconnection means strength 0.
///
/// One write at a time: while a write is waiting for its answer, only the newest strength waits behind it. An answer that
/// does not come in 0.6 s is not waited for any longer (the first build waited forever: connected, but silent).
/// The kind of write follows what the toy says it can do; a refused write switches to the other kind.
/// While the strength is above 0 the toy hears it again every second. Rhythms are counted by the wall clock: a write
/// every 0.12 s with the app in front, in the background the next one right after the answer to the last one.
final class NyxManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = NyxManager()

    static let svc = CBUUID(string: "78667579-7B48-43DB-B8C5-7928A6B0A335")
    static let txID = CBUUID(string: "78667579-A914-49A4-8333-AA3C0CD8FEDC")
    static let batSvc = CBUUID(string: "180F")
    static let batChr = CBUUID(string: "2A19")
    static let controlKind = "com.volchuk.para.control.nyx"
    static let presetKind = "com.volchuk.para.control.nyx.preset"
    static let playKind = "com.volchuk.para.control.nyx.stop"
    private var widgetShown = ""

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
    private var tickGen = 0
    private var writeSeq = 0
    private var changedWhileBusy = false
    private var writeType: CBCharacteristicWriteType = .withResponse
    /// what the screen shows under «Підключено»: how the writes go
    private var sent = 0, answered = 0, failed = 0, timedOut = 0
    private var lastError: String?
    /// when the rhythm began (the rise of «Наростання» and the drawn rhythm count from here)
    private var rhythmStart = Date()
    /// the timer: 0 at this moment
    private(set) var timerEnd: Date?
    private var timerCheck: Timer?
    private var batteryTimer: Timer?
    /// the preset that plays now (its name on the plate), until something else is chosen by hand
    private var presetName: String?
    private let sensors = NyxSensors()
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
            var r = rhythm.next
            if r == .custom && tune.pattern == nil { r = r.next }   // nothing drawn yet
            set(rhythm: r)
        case .stop:
            set(level: 0)
        case .power(let on):
            power(on)
        case .playPause:
            apply(.play(level == 0))
        case .play(let on):
            if !on { set(level: 0); return }
            let last = defaults.integer(forKey: "nyx.level")
            if phase != "on" { power(true) }
            set(level: level > 0 ? level : (last > 0 ? last : 40))
        case .preset(let id):
            guard let x = NyxPresets.find(id) else { return }
            apply(preset: x)
        case .nextPreset:
            let all = NyxPresets.all()
            guard !all.isEmpty else { return }
            let i = ((all.firstIndex { $0.name == presetName } ?? -1) + 1) % all.count
            apply(preset: all[i])
        }
    }

    /// A preset: its rhythm, its settings, its strength (or the last one), and its name on the plate.
    func apply(preset x: NyxPreset) {
        tune = x.tune; x.tune.save()
        if rhythm != x.rhythm { rhythmStart = Date() }
        rhythm = x.rhythm; defaults.set(x.rhythm.rawValue, forKey: "nyx.rhythm")
        sensorsFollow()
        let keep = level > 0 ? level : defaults.integer(forKey: "nyx.level")
        if phase != "on" { power(true) }
        set(level: x.level ?? (keep > 0 ? keep : 40))
        presetName = x.name
        changed()
    }

    /// «Вимкнути через…»: 0 minutes — no timer.
    func setTimer(minutes m: Double) {
        timerCheck?.invalidate(); timerCheck = nil
        timerEnd = m > 0 ? Date().addingTimeInterval(m * 60) : nil
        if let end = timerEnd {
            timerCheck = Timer.scheduledTimer(withTimeInterval: max(1, end.timeIntervalSinceNow), repeats: false) { [weak self] _ in self?.timeUp() }
        }
        holdBackground()
        changed()
    }

    private func timeUp() {
        guard let end = timerEnd, Date() >= end.addingTimeInterval(-0.5) else { return }
        timerEnd = nil; timerCheck?.invalidate(); timerCheck = nil
        set(level: 0)
    }

    /// The microphone and the tilt run only while their rhythm plays and the app is open.
    private func sensorsFollow() {
        switch rhythm {
        case .music where !background:
            sensors.stopTilt()
            sensors.startMic { [weak self] ok in
                guard let self, !ok else { return }
                self.error = "Немає доступу до мікрофона: Параметри → DaVincit → Мікрофон."
                self.changed()
            }
        case .tilt where !background:
            sensors.stopMic(); sensors.startTilt()
        default:
            sensors.stopAll()
        }
    }

    /// The page's own presets, for the buttons outside the app.
    func savePresets(_ list: [[String: Any]]) {
        NyxPresets.save(page: list)
        ParaShortcuts.updateAppShortcutParameters()   // Siri knows the new names
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadControls(ofKind: Self.presetKind) }
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
            sensors.stopAll()
            setTimer(minutes: 0)
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
        if r != rhythm { rhythmStart = Date() }
        rhythm = r
        presetName = nil
        defaults.set(r.rawValue, forKey: "nyx.rhythm")
        sensorsFollow()
        holdBackground()
        pump(); changed()
    }

    /// The settings of the rhythms (from this screen, or from the far partner's screen).
    func set(tune t: NyxTune) {
        if t != tune { presetName = nil }
        tune = t
        t.save()
        pump(); changed()
    }

    /// «На відстані»: the far partner's strength and rhythm. Silence for 5 s (or the app going to the background) → 0.
    func remote(level l: Int?, rhythm r: NyxRhythm?, on: Bool) {
        if !on { remoteAt = nil; set(level: 0); return }
        remoteAt = Date()
        if let r, r != rhythm { rhythm = r; rhythmStart = Date(); presetName = nil }
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
        if peripheral?.state == .connected, tx != nil {
            // past the queue: iOS keeps the order of writes, so this 0 is the last word even if one is on its way
            inFlight = false
            send(0)
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
        batteryTimer?.invalidate(); batteryTimer = nil
        sensors.stopAll()
        tx = nil; battChr = nil; inFlight = false; lastSent = -1; tickGen += 1; changedWhileBusy = false
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
            if ch.uuid == Self.txID {
                tx = ch
                // the toy says how it wants to be written to; «with an answer» when it can do both
                writeType = ch.properties.contains(.write) || !ch.properties.contains(.writeWithoutResponse) ? .withResponse : .withoutResponse
                ready(p)
            }
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
        batteryTimer?.invalidate()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, let p = self.peripheral, p.state == .connected, let b = self.battChr else { return }
            p.readValue(for: b)
        }
        pump(); changed()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == Self.batChr, let v = ch.value?.first { battery = Int(v); changed() }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == Self.txID else { return }
        if let error {
            failed += 1
            lastError = error.localizedDescription
            // refused «with an answer»: try the other kind if the toy has it
            if writeType == .withResponse, ch.properties.contains(.writeWithoutResponse) { writeType = .withoutResponse; lastSent = -1 }
        } else {
            answered += 1
        }
        inFlight = false
        afterWrite()
    }

    /// A write is done (answered, given up on, or sent without an answer): a change that waited goes now, else the next
    /// beat of the rhythm, else the same strength again in a second (so the toy never forgets it).
    private func afterWrite() {
        if changedWhileBusy { changedWhileBusy = false; pump(force: true); return }
        guard level > 0 else { return }
        let rhythmOn = (rhythm != .steady && !paused) || timerEnd != nil
        if rhythmOn && background && writeType == .withResponse { pump(force: true); return }   // in the background: right after the answer
        tickGen += 1
        let gen = tickGen
        DispatchQueue.main.asyncAfter(deadline: .now() + (rhythmOn ? 0.12 : 1.0)) { [weak self] in
            guard let self, self.tickGen == gen else { return }
            self.pump(force: true)
        }
    }

    static func cmd(_ s: Int) -> Data {
        let v = UInt8(max(0, min(100, s)))
        return Data([0x10, 0xff, 0x04, 0x0a, 0x32, 0x32, 0x00, 0x04, 0x08, v, 0x64, 0x00, 0x04, 0x08, v, 0x64, 0x01])
    }

    /// Sends what the toy should do now, unless a write is still waiting for its answer (then it goes right after).
    private func pump(force: Bool = false) {
        guard peripheral?.state == .connected, tx != nil else { return }
        if inFlight { changedWhileBusy = true; return }
        if let end = timerEnd, Date() >= end { timeUp(); return }
        let out = (paused ? NyxRhythm.steady : rhythm).output(level: level, at: Date().timeIntervalSince(rhythmStart), tune: tune, env: sensors.env)
        if out == lastSent && !force { return }
        if out == lastSent && out == 0 { return }   // 0 is not repeated
        send(out)
    }

    private func send(_ out: Int) {
        guard let p = peripheral, let tx, p.state == .connected else { return }
        lastSent = out
        sent += 1
        writeSeq += 1
        let seq = writeSeq
        tickGen += 1   // a beat that was waiting is not needed: this write starts the count again
        if writeType == .withResponse {
            inFlight = true
            p.writeValue(Self.cmd(out), for: tx, type: .withResponse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.inFlight, self.writeSeq == seq else { return }
                self.timedOut += 1
                self.inFlight = false
                self.afterWrite()
            }
        } else {
            p.writeValue(Self.cmd(out), for: tx, type: .withoutResponse)
            DispatchQueue.main.async { [weak self] in self?.afterWrite() }
        }
        if sent <= 3 || sent % 20 == 0 { changed() }   // the counters on the screen, without a flood
    }

    /// «Перевірити»: 60 % for two seconds with one kind of write, then two with the other, then back to what was set.
    func selfTest() {
        guard peripheral?.state == .connected, tx != nil else { return }
        let keep = writeType, back = level
        let kinds: [CBCharacteristicWriteType] = [.withResponse, .withoutResponse]
        level = 60   // the beat of «one second again» keeps 60 too, not the old strength
        inFlight = false
        writeType = kinds[0]; send(60)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.inFlight = false; self.writeType = kinds[1]; self.send(60)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.writeType = keep; self.inFlight = false; self.lastSent = -1
                self.level = back; self.pump(force: true); self.changed()
            }
        }
    }

    private func wentBack() {
        // «На відстані» needs the app open: in the background nobody could stop it
        if remoteAt != nil { remoteAt = nil; set(level: 0) }
        sensors.stopAll()   // the microphone and the tilt: only with the app open (the last value stays)
        holdBackground()
        pump(force: true)
    }

    /// A rhythm in the background lives as long as iOS lets the app run (about half a minute after the app leaves the
    /// screen or after a button of the plate). Then: the chosen strength, steady, and the plate says so.
    private func holdBackground() {
        guard background, rhythm != .steady || timerEnd != nil, level > 0, bgTask == .invalid else { return }
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
        sensorsFollow()
        if let end = timerEnd, Date() >= end { timeUp() }
        if paused { paused = false; pump(force: true); changed() }
    }

    private func endBg() {
        if bgTask != .invalid { let t = bgTask; MainActor.assumeIsolated { UIApplication.shared.endBackgroundTask(t) }; bgTask = .invalid }
    }

    // MARK: the plate and the pages

    private func changed() {
        onChange?(snapshot())
        syncActivity()
        syncWidgets()
    }

    /// The lock-screen and home widgets and the Control Center button: only on a real change (not on every beat).
    private func syncWidgets() {
        let key = "\(phase)|\(level)|\(rhythm.rawValue)|\(battery ?? -1)"
        guard key != widgetShown else { return }
        let wasOn = widgetShown.hasPrefix("on|"), nowOn = phase == "on"
        let wasPlaying = wasOn && !widgetShown.hasPrefix("on|0|"), nowPlaying = nowOn && level > 0
        widgetShown = key
        var d: [String: Any] = ["phase": phase, "level": level, "rhythm": rhythm.rawValue]
        if let battery { d["battery"] = battery }
        defaults.set(d, forKey: NyxState.key)
        WidgetCenter.shared.reloadTimelines(ofKind: "nyx")
        if wasOn != nowOn, #available(iOS 18.0, *) { ControlCenter.shared.reloadControls(ofKind: Self.controlKind) }
        if wasPlaying != nowPlaying, #available(iOS 18.0, *) { ControlCenter.shared.reloadControls(ofKind: Self.playKind) }
    }

    func snapshot() -> [String: Any] {
        var s: [String: Any] = ["phase": phase, "level": level, "rhythm": rhythm.rawValue, "remote": remoteAt != nil, "background": background, "paused": paused, "tune": tune.dict]
        if let battery { s["battery"] = battery }
        if let error { s["error"] = error }
        if let n = peripheral?.name { s["name"] = n }
        if let timerEnd { s["endsAt"] = timerEnd.timeIntervalSince1970 * 1000 }
        if let presetName { s["preset"] = presetName }
        var d: [String: Any] = ["write": writeType == .withResponse ? "з відповіддю" : "без відповіді", "sent": sent, "ok": answered, "failed": failed, "timeout": timedOut, "last": lastSent]
        if let tx { d["props"] = Self.props(tx.properties) }
        if let lastError { d["error"] = lastError }
        s["diag"] = d
        return s
    }

    static func props(_ p: CBCharacteristicProperties) -> String {
        let all: [(CBCharacteristicProperties, String)] = [(.write, "write"), (.writeWithoutResponse, "writeNoResp"), (.read, "read"), (.notify, "notify")]
        return all.filter { p.contains($0.0) }.map { $0.1 }.joined(separator: ",")
    }

    private func syncActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard phase == "on" else { return }
        let st = NyxAttributes.ContentState(level: level, rhythm: rhythm, battery: battery, remote: remoteAt != nil, paused: paused, endsAt: timerEnd, preset: presetName)
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
