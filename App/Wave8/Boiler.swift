import SwiftUI

// MARK: - «Котел»: one shared state for the widget and its screen

struct BoilerSum: Codable, Equatable { let hours: Double; let kwh: Double; let cost: Double }
struct BoilerEvent: Codable, Equatable { let t: Date; let on: Bool }
struct BoilerStats: Codable, Equatable {
    let today: BoilerSum; let yesterday: BoilerSum; let week: BoilerSum
    let chart: [Double]; let events: [BoilerEvent]
    var vmin: Double? = nil; var vmax: Double? = nil; var temp: Double? = nil
}
extension API { func boilerStats() async throws -> BoilerStats { try await get("/boiler/stats") } }

final class BoilerStore: ObservableObject {
    static let shared = BoilerStore()
    @Published var s: BoilerState?
    @Published var stats: BoilerStats?
    @Published var busy = false
    private var at = Date.distantPast

    @MainActor func load(force: Bool = false) async {
        guard force || Date().timeIntervalSince(at) > 20 else { return }
        at = Date()
        if let r = try? await API.current().boiler() { s = r }
        if s?.configured == true { await addWidgetOnce() }
    }
    @MainActor func loadStats() async { stats = try? await API.current().boilerStats() }
    @MainActor func act(_ a: String) async {
        busy = true
        Haptic.hit(.heavy)
        if a == "toggle", var c = s { c.on = !(c.on ?? false); s = c }
        if let r = try? await API.current().boiler(a) { s = r } else { await load(force: true) }
        busy = false
        stats = nil
    }
    /// the first time the plug answers, its widget joins Головна (once; removed by hand — it stays away)
    @MainActor private func addWidgetOnce() async {
        let key = "dv-boiler-w"
        guard !UserDefaults.standard.bool(forKey: key), let d = try? await API.current().dashboard(), let l = d.layout else { return }
        if l.contains(where: { $0.faces.contains("boiler") }) { UserDefaults.standard.set(true, forKey: key); return }
        if (try? await API.current().setLayout([DashWidget(id: "wboiler", size: "s", faces: ["boiler"])] + l)) != nil {
            UserDefaults.standard.set(true, forKey: key)
        }
    }
}

func boilerPower(_ w: Double?) -> String {
    guard let w else { return "—" }
    return w >= 1000 ? String(format: "%.1f кВт", w / 1000).replacingOccurrences(of: ".", with: ",") : "\(Int(w)) Вт"
}
func boilerLeft(_ s: Int) -> String {
    let h = s / 3600, m = (s % 3600) / 60
    return h > 0 ? "\(h) год" + (m > 0 ? " \(m) хв" : "") : "\(max(1, m)) хв"
}

// MARK: - the screen: the same dark look as the timer

struct BoilerPage: View {
    @ObservedObject private var b = BoilerStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var whenOpen = false
    private let pale = Color(hex: 0xC7CCD3), dark = Color(hex: 0x111111), orange = Color(hex: 0xFF9F0A)

    var body: some View {
        let s = b.s
        let off = s?.online == false || s?.error != nil
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: -22) {
                    VStack(spacing: 4) {
                        Text("КОТЕЛ · " + (s == nil ? "…" : off ? "ОФЛАЙН" : s?.on == true ? "ГРІЄ" : "ВИМКНЕНО")).font(.system(size: 14)).tracking(0.8).opacity(0.85)
                        Text(bigText(s)).font(.system(size: 120, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                            .scaleEffect(x: 0.6, y: 1.25).frame(height: 190)
                        Text(unitText(s)).font(.system(size: 13)).foregroundStyle(Color(hex: 0x8D939B)).padding(.bottom, 8)
                    }
                    .foregroundStyle(pale).frame(maxWidth: .infinity)
                    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
                    .background(Color(hex: 0x0F0F10), in: RoundedRectangle(cornerRadius: 34, style: .continuous)).zIndex(1)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(off ? "НЕМАЄ ЗВʼЯЗКУ" : s?.on == true ? "УВІМКНЕНО" : "ВИМКНЕНО").font(.system(size: 30, weight: .heavy))
                        Text(subline).font(.system(size: 15, weight: .heavy)).tracking(0.6).padding(.top, 2)
                        Rectangle().frame(width: 110, height: 2).padding(.vertical, 14)
                        if let st = b.stats {
                            Text("Сьогодні \(hrs(st.today.hours)) · \(num(st.today.kwh, 2)) кВт·год · \(Int(st.today.cost.rounded())) ₴").font(.system(size: 14.5, weight: .bold))
                            Text("Учора \(hrs(st.yesterday.hours)) · 7 днів \(num(st.week.kwh, 1)) кВт·год · \(Int(st.week.cost.rounded())) ₴").font(.system(size: 12)).padding(.top, 2)
                        } else { Text("Рахую споживання…").font(.system(size: 14.5, weight: .bold)) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 38).padding(.bottom, 20)
                    .background(pale, in: UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
                    .foregroundStyle(dark)
                }
                HStack(spacing: 6) {
                    chip("1 год", "timer:1"); chip("2 год", "timer:2"); chip("3 год", "timer:3")
                    if (s?.countdown ?? 0) > 0 { chip("Стоп", "cancel") } else { chip("6 год", "timer:6") }
                    Button { whenOpen = true } label: { Text("До / о…").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 40).background(Color(hex: 0x3B3E43), in: Capsule()).foregroundStyle(Color(hex: 0xE9ECEF)) }
                        .buttonStyle(PressScale()).disabled(off)
                }
                VStack(spacing: 4) {
                    let chart = b.stats?.chart ?? Array(repeating: 0, count: 24)
                    let mx = max(1, chart.max() ?? 1)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(chart.indices, id: \.self) { i in
                            let v = chart[i]
                            RoundedRectangle(cornerRadius: 2).fill(v <= 0 ? Color(hex: 0x2A2C30) : (i == chart.count - 1 && s?.on == true ? orange : orange.opacity(0.55)))
                                .frame(height: max(3, CGFloat(v / mx) * 56))
                        }
                    }
                    .frame(height: 58)
                    HStack { Text("−24 год"); Spacer(); Text("зараз") }.font(.system(size: 10.5)).foregroundStyle(Color(hex: 0x8D939B))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color(hex: 0x1B1C1F), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                if let ev = b.stats?.events, !ev.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(ev.prefix(6)).indices, id: \.self) { i in
                            let e = ev[i]
                            HStack {
                                Text(e.on ? "Увімкнено" : "Вимкнено").foregroundStyle(e.on ? orange : pale)
                                Spacer()
                                Text(e.t.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "uk_UA")))).foregroundStyle(Color(hex: 0x8D939B))
                            }
                            .font(.system(size: 13.5)).padding(.vertical, 7)
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) } }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Color(hex: 0x1B1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                HStack {
                    roundBtn("xmark") { dismiss() }
                    Spacer()
                    Button { Task { await b.act("toggle") } } label: {
                        Image(systemName: "power").font(.system(size: 22, weight: .bold)).frame(width: 84, height: 58)
                            .background(s?.on == true ? orange : pale, in: Capsule()).foregroundStyle(dark)
                            .shadow(color: orange.opacity(s?.on == true ? 0.45 : 0), radius: 16)
                    }
                    .buttonStyle(PressScale()).disabled(off || b.busy)
                    Spacer()
                    roundBtn("arrow.clockwise") { Task { await b.load(force: true); await b.loadStats() } }
                }
                .padding(.horizontal, 10).padding(.top, 4)
            }
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(hex: 0x2A2D31).ignoresSafeArea())
        .task { await b.load(force: true); await b.loadStats() }
        .sheet(isPresented: $whenOpen) { BoilerWhenSheet().presentationDetents([.medium]) }
    }

    private var subline: String {
        var p: [String] = []
        if let t = b.stats?.temp { p.append("НАДВОРІ \(Int(t.rounded()))°") } else { p.append("ОПАЛЕННЯ") }
        if let v = b.s?.volts { p.append("\(Int(v)) В") }
        return p.joined(separator: " · ")
    }
    private func bigText(_ s: BoilerState?) -> String {
        guard let s else { return "…" }
        if let c = s.countdown, c > 0 { return String(format: "%d:%02d", c / 3600, (c % 3600) / 60) }
        return s.on == true ? String(format: "%.1f", (s.watts ?? 0) / 1000).replacingOccurrences(of: ".", with: ",") : "OFF"
    }
    private func unitText(_ s: BoilerState?) -> String {
        guard let s else { return "" }
        if (s.countdown ?? 0) > 0 { return "до вимкнення" }
        return s.on == true ? "кВт зараз" : ""
    }
    private func hrs(_ h: Double) -> String { h < 1 ? "\(Int((h * 60).rounded())) хв" : num(h, 1) + " год" }
    private func num(_ x: Double, _ d: Int) -> String { String(format: "%.\(d)f", x).replacingOccurrences(of: ".", with: ",") }
    private func chip(_ t: String, _ a: String) -> some View {
        Button { Task { await b.act(a) } } label: {
            Text(t).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 40)
                .background(Color(hex: 0x3B3E43), in: Capsule()).foregroundStyle(Color(hex: 0xE9ECEF))
        }
        .buttonStyle(PressScale()).disabled(b.busy || b.s?.online == false)
    }
    private func roundBtn(_ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).frame(width: 58, height: 58)
                .background(Color(hex: 0x3B3E43), in: Circle()).foregroundStyle(Color(hex: 0xE9ECEF))
        }
        .buttonStyle(PressScale())
    }
}

/// «До» — on now, off by itself then; «о» — the plug flips at that time (Kyiv time)
struct BoilerWhenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var until = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var at = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Котел за часом").font(.serif(26, .bold))
            DatePicker("Увімкнути до", selection: $until, displayedComponents: .hourAndMinute)
            Button("Увімкнути до цього часу") { go("until", until) }.buttonStyle(.borderedProminent).tint(Color(hex: 0xC8742A))
            DatePicker("Перемкнути о", selection: $at, displayedComponents: .hourAndMinute)
            Button("Запланувати") { go("at", at) }.buttonStyle(.bordered)
            Spacer()
        }
        .padding(20)
        .environment(\.locale, Locale(identifier: "uk_UA"))
    }
    private func go(_ kind: String, _ d: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let a = String(format: "%@:%02d:%02d", kind, c.hour ?? 0, c.minute ?? 0)
        dismiss()
        Task { await BoilerStore.shared.act(a) }
    }
}

/// the face on Головна: power (or «Вимк.») in orange, what it is doing, a small lamp
struct BoilerFace: View {
    let big: Bool, wide: Bool
    @ObservedObject private var b = BoilerStore.shared
    private func fs(_ x: CGFloat) -> CGFloat { big ? x * 1.5 : wide ? x * 1.15 : x }
    var body: some View {
        let s = b.s
        VStack(alignment: .leading, spacing: 2) {
            Text(main(s)).font(.system(size: fs(26), weight: .semibold)).monospacedDigit()
                .foregroundStyle(s?.on == true ? Color(hex: 0xFF9F0A) : Color(hex: 0xF2F2F2)).lineLimit(1).minimumScaleFactor(0.6)
            Text(line(s)).font(.system(size: fs(12))).opacity(0.8).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Circle().fill(s?.on == true ? Color(hex: 0xFF9F0A) : Color(hex: 0x3A3A3C)).frame(width: 10, height: 10)
                .shadow(color: Color(hex: 0xFF9F0A).opacity(s?.on == true ? 0.9 : 0), radius: 6)
                .offset(y: -fs(34))
        }
        .task { await b.load() }
    }
    private func main(_ s: BoilerState?) -> String {
        guard let s else { return "…" }
        if !s.configured { return "—" }
        if s.error != nil || s.online == false { return "Офлайн" }
        return s.on == true ? boilerPower(s.watts) : "Вимк."
    }
    private func line(_ s: BoilerState?) -> String {
        guard let s, s.configured else { return "не підключено" }
        if s.error != nil || s.online == false { return "немає звʼязку з розеткою" }
        if let c = s.countdown, c > 0 { return "ще " + boilerLeft(c) }
        return s.on == true ? "гріє · 2 тапи — меню" : "тап — увімкнути"
    }
}
