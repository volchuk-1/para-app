import SwiftUI
import WebKit

// MARK: - Помодоро: arc of ticks, hours and minutes on two horizontal rulers; the partner sees it

struct PomodoroPage: View {
    var onClose: () -> Void = {}
    @EnvironmentObject var state: AppState
    @State private var pair: PomoPair?
    @State private var act = "Читання"
    @State private var hours: Int? = 0
    @State private var minutes: Int? = 25
    @State private var together = false
    @State private var busy = false
    @State private var presets: [PomoPreset] = []
    @State private var newPreset = false
    private let acts: [(String, String)] = [("Читання", "book.fill"), ("Робота", "briefcase.fill"), ("Спорт", "figure.run"), ("Англійська", "character.bubble.fill"), ("Прибирання", "sparkles"), ("Навчання", "graduationcap.fill")]
    private let bg = Color(hex: 0x141210)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button { Haptic.hit(.medium); onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44).background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                Text("Помодоро").font(.serif(30, .bold))
                Text("Обираєш справу й час. \(state.partner?.name ?? "") бачить, чим ти зайнятий, на головній; поки йде — оливковий острівець.").font(.system(size: 13.5)).opacity(0.6)
                TimelineView(.periodic(from: .now, by: 1)) { _ in gauge }
                if let me = pair?.me {
                    HStack(spacing: 8) {
                        bigButton(me.paused ? "Далі" : "Пауза", me.paused ? "play.fill" : "pause.fill", filled: true) { await pause() }
                        bigButton("Стоп", "stop.fill", filled: false) { await stop() }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // my own activities: one tap — the timer goes with its minutes
                            ForEach(presets, id: \.key) { pr in
                                Button { Task { await start(pr) } } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: pr.symbol)
                                        Text(pr.name)
                                        Text("\(pr.minutes) хв ▶").font(.system(size: 11.5)).opacity(0.8)
                                    }
                                    .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 15).frame(height: 40)
                                    .background(Theme.olive, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .contextMenu { Button("Прибрати", role: .destructive) { Task { await save(presets.filter { $0.key != pr.key }) } } }
                            }
                            ForEach(acts, id: \.0) { a in
                                Button { act = a.0 } label: {
                                    Label(a.0, systemImage: a.1).font(.system(size: 14, weight: .semibold)).padding(.horizontal, 15).frame(height: 40)
                                        .background(act == a.0 ? Theme.olive : Color(hex: 0x25221F), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            Button { newPreset = true } label: {
                                Label("Своє", systemImage: "plus").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 15).frame(height: 40)
                                    .background(Color(hex: 0x25221F), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    rulerLabel("Години", "\(hours ?? 0)")
                    Ruler(maxValue: 5, step: 1, value: $hours)
                    Text("Хвилини — веди пальцем по дузі вгорі.").font(.system(size: 12.5)).opacity(0.55)
                    Toggle("Разом із \(state.partner?.name ?? "") — покличу в боті", isOn: $together).tint(Theme.olive).font(.system(size: 14)).padding(.top, 4)
                    bigButton("Почати", "play.fill", filled: true) { await start() }.padding(.top, 4)
                }
                if let p = pair?.partner {
                    HStack(spacing: 10) {
                        Text(String(state.partner?.name.prefix(1) ?? "?")).font(.serif(16, .bold)).frame(width: 36, height: 36).background(Theme.coffee, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(state.partner?.name ?? ""): \(p.activity)").font(.system(size: 14, weight: .semibold))
                            if p.paused { Text("пауза").font(.system(size: 12.5)).opacity(0.65) }
                            else { Text(timerInterval: Date()...max(Date(), p.endsAt), countsDown: true).font(.system(size: 12.5)).monospacedDigit().opacity(0.65) }
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0x1F1C19), in: RoundedRectangle(cornerRadius: 22))
                }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 130)
        }
        .background(bg.ignoresSafeArea())
        .foregroundStyle(Color(hex: 0xF3EEE6))
        .task {
            pair = try? await API.current().pomo()
            presets = (try? await API.current().pomoPresets()) ?? presets
        }
        .sheet(isPresented: $newPreset) { PresetSheet { pr in Task { await save(presets + [pr]) } } }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1), trigger: hours)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: minutes)
    }

    private var gauge: some View {
        let me = pair?.me
        let total = me.map { Double($0.total) } ?? Double(((hours ?? 0) * 60 + (minutes ?? 0)) * 60)
        let left = me.map { Double($0.leftNow) } ?? total
        // running: how much is left; choosing: the minutes picked on the arc (0 … 60)
        let frac = me != nil ? (total > 0 ? left / total : 1) : Double(minutes ?? 0) / 60
        return VStack(spacing: 0) {
            HStack { Text((me?.activity ?? act).uppercased()).font(.system(size: 13, weight: .semibold)); Spacer(); Text(me == nil ? "ВЕДИ ПО ДУЗІ" : me!.paused ? "ПАУЗА" : me!.together ? "РАЗОМ" : "ФОКУС").font(.system(size: 13)).opacity(me == nil ? 0.6 : 1) }
            ZStack(alignment: .bottom) {
                Canvas { ctx, size in
                    let n = 46, cx = size.width / 2, cy = size.height - 4, r2 = min(size.width / 2 - 6, size.height - 10), r1 = r2 * 0.7
                    for i in 0..<n {
                        let c = Double(i) / Double(n - 1), a = Double.pi + Double.pi * c
                        let rr = i % 5 == 0 ? r1 : r1 + 8
                        var p = Path()
                        p.move(to: CGPoint(x: cx + rr * cos(a), y: cy + rr * sin(a)))
                        p.addLine(to: CGPoint(x: cx + r2 * cos(a), y: cy + r2 * sin(a)))
                        let col = c <= frac ? Color(red: (120 + c * 106) / 255, green: (160 + c * 39) / 255, blue: (190 - c * 23) / 255) : Color.white.opacity(0.14)
                        ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                    }
                    let na = Double.pi + Double.pi * frac
                    var needle = Path()
                    needle.move(to: CGPoint(x: cx + r1 * 0.72 * cos(na), y: cy + r1 * 0.72 * sin(na)))
                    needle.addLine(to: CGPoint(x: cx + (r2 + 10) * cos(na), y: cy + (r2 + 10) * sin(na)))
                    ctx.stroke(needle, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                .frame(height: 170)
                .overlay {
                    if me == nil {
                        GeometryReader { g in
                            Color.clear.contentShape(Rectangle())
                                .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { v in pickMinutes(v.location, g.size) })
                        }
                    }
                }
                Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60)).font(.system(size: 38, weight: .semibold)).monospacedDigit().padding(.bottom, 26)
            }
            HStack { Text("0 хв").foregroundStyle(Color(hex: 0x9DB27F)); Spacer(); Text(me == nil ? "60 хв" : "\(Int(total / 60)) хв").foregroundStyle(Theme.sand) }.font(.system(size: 14))
        }
        .padding(16).background(.black, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    /// A finger on the arc sets the minutes: the left end is 0, the right end 60.
    private func pickMinutes(_ at: CGPoint, _ size: CGSize) {
        let x = Double(at.x - size.width / 2), y = Double(size.height - 4 - at.y)
        let angle = atan2(max(0, y), x)
        let m = max(0, min(59, Int(((1 - angle / Double.pi) * 60).rounded())))
        if m != minutes { minutes = m }
    }

    private func rulerLabel(_ t: String, _ v: String) -> some View {
        HStack(alignment: .lastTextBaseline) { Text(t.uppercased()).font(.system(size: 12)).tracking(1.4).opacity(0.75); Spacer(); Text(v).font(.system(size: 22, weight: .semibold)).monospacedDigit() }.padding(.top, 8)
    }
    private func bigButton(_ t: String, _ icon: String, filled: Bool, _ a: @escaping () async -> Void) -> some View {
        Button { Task { await a() } } label: { Label(t, systemImage: icon).font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 56) }
            .background(filled ? Theme.olive : Color(hex: 0x25221F), in: Capsule()).foregroundStyle(Theme.cream).disabled(busy)
    }

    private func start() async {
        let m = (hours ?? 0) * 60 + (minutes ?? 0)
        guard m > 0 else { return }
        busy = true; defer { busy = false }
        if let me = try? await API.current().startPomo(act, minutes: m, together: together) {
            pair = PomoPair(me: me, partner: pair?.partner)
            LiveTasks.add(id: "pomo", title: "🍅 \(act)", start: Date(), end: me.endsAt)
        }
    }
    /// A preset of my own starts at once — its name and its minutes.
    private func start(_ pr: PomoPreset) async {
        busy = true; defer { busy = false }
        if let me = try? await API.current().startPomo(pr.name, minutes: pr.minutes, together: false) {
            Haptic.hit(.heavy)
            pair = PomoPair(me: me, partner: pair?.partner)
            LiveTasks.add(id: "pomo", title: "🍅 \(pr.name)", start: Date(), end: me.endsAt)
        }
    }

    private func save(_ list: [PomoPreset]) async {
        if let r = try? await API.current().savePomoPresets(list) { presets = r; Haptic.ok() }
    }

    private func pause() async {
        busy = true; defer { busy = false }
        let me = try? await API.current().pausePomo()
        pair = PomoPair(me: me, partner: pair?.partner)
        if let me, me.paused { LiveTasks.remove("pomo") } else if let me { LiveTasks.add(id: "pomo", title: "🍅 \(me.activity)", start: Date(), end: me.endsAt) }
    }
    private func stop() async {
        busy = true; defer { busy = false }
        try? await API.current().stopPomo()
        LiveTasks.remove("pomo")
        pair = PomoPair(me: nil, partner: pair?.partner)
    }
}

/// A horizontal ruler: ticks every unit, long ones on the step; it snaps under the sand marker.
struct Ruler: View {
    let maxValue: Int
    let step: Int
    @Binding var value: Int?
    var body: some View {
        GeometryReader { g in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0...maxValue, id: \.self) { i in
                        VStack(spacing: 4) {
                            Text(i % step == 0 ? "\(i)" : "").font(.system(size: 10)).opacity(0.6).frame(height: 12)
                            Capsule().fill(.white.opacity(i % step == 0 ? 0.6 : 0.28)).frame(width: 2, height: i % step == 0 ? 26 : 14)
                        }
                        .frame(width: 14, height: 64, alignment: .bottom).padding(.bottom, 10)
                        .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $value, anchor: .center)
            .contentMargins(.horizontal, g.size.width / 2 - 7, for: .scrollContent)
        }
        .frame(height: 64)
        .background(Color(hex: 0x1F1C19), in: RoundedRectangle(cornerRadius: 20))
        .overlay(Capsule().fill(Theme.sand).frame(width: 3).padding(.vertical, 8).shadow(color: Theme.sand.opacity(0.7), radius: 6).allowsHitTesting(false))
        .overlay(LinearGradient(stops: [.init(color: Color(hex: 0x1F1C19), location: 0), .init(color: .clear, location: 0.22), .init(color: .clear, location: 0.78), .init(color: Color(hex: 0x1F1C19), location: 1)], startPoint: .leading, endPoint: .trailing).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Статистика

struct StatsPage: View {
    @State private var s: Stats?
    private let mon = ["січ", "лют", "бер", "кві", "тра", "чер", "лип", "сер", "вер", "жов", "лис", "гру"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PageTitle(plain: "Наша", italic: "статистика", sub: "Ми, побачення, фільми й книжки.")
                if let s {
                    VStack(alignment: .leading, spacing: 2) { Text("\(s.daysTogether)").font(.system(size: 56)).tracking(-1.6); Text("днів разом у DaVincit").opacity(0.8) }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Theme.olive, in: RoundedRectangle(cornerRadius: 28)).foregroundStyle(Theme.cream)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        cell(s.dates, "побачень"); cell(s.films, "фільмів подивились"); cell(s.episodes, "серій оцінили")
                        cell(s.books, "книжок прочитали"); cell(s.memories, "спогадів і альбомів"); cell(s.touches, "«думаю про тебе»")
                    }
                    Text("Побачення за видом").font(.system(size: 15, weight: .semibold)).padding(.top, 8)
                    HStack(spacing: 6) {
                        ForEach([("cinema", "Кіно"), ("dinner", "Вечері"), ("walk", "Прогулянки"), ("other", "Інше")], id: \.0) { k in
                            VStack(spacing: 2) { Text("\(s.byKind[k.0] ?? 0)").font(.system(size: 22, weight: .semibold)); Text(k.1).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                                .frame(maxWidth: .infinity).padding(.vertical, 10).background(Theme.paper, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    Text("Останні півроку").font(.system(size: 15, weight: .semibold)).padding(.top, 8)
                    let mx = max(1, s.months.map { $0.dates + $0.films + $0.touches }.max() ?? 1)
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(s.months, id: \.month) { m in
                            VStack(spacing: 4) {
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    Rectangle().fill(Color(hex: 0xC9A27E)).frame(height: CGFloat(m.touches) / CGFloat(mx) * 110)
                                    Rectangle().fill(Theme.coffee).frame(height: CGFloat(m.films) / CGFloat(mx) * 110)
                                    Rectangle().fill(Theme.olive).frame(height: CGFloat(m.dates) / CGFloat(mx) * 110)
                                }
                                .frame(height: 110).frame(maxWidth: .infinity).background(Theme.ink.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(mon[(Int(m.month.suffix(2)) ?? 1) - 1]).font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(14).background(Theme.paper, in: RoundedRectangle(cornerRadius: 22))
                    HStack(spacing: 12) { legend(Theme.olive, "побачення"); legend(Theme.coffee, "фільми"); legend(Color(hex: 0xC9A27E), "«думаю про тебе»") }.font(.system(size: 11)).foregroundStyle(Theme.muted)
                    if !s.scores.isEmpty {
                        Text("Середня оцінка фільмів").font(.system(size: 15, weight: .semibold)).padding(.top, 8)
                        ForEach(s.scores, id: \.name) { x in
                            HStack(alignment: .firstTextBaseline) { Text(x.name); Spacer(); Text(String(format: "%.1f", x.avg)).font(.system(size: 22, weight: .semibold)); Text("\(x.count) оцінок").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                                .padding(12).background(Theme.paper, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    if s.cancelled > 0 { Text("Скасованих побачень: \(s.cancelled)").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                } else { ProgressView().tint(Theme.olive).frame(maxWidth: .infinity).padding(40) }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 130)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .task { s = try? await API.current().stats() }
    }
    private func cell(_ n: Int, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text("\(n)").font(.system(size: 32, weight: .medium)); Text(l).font(.system(size: 12.5)).foregroundStyle(Theme.muted) }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.paper, in: RoundedRectangle(cornerRadius: 22))
    }
    private func legend(_ c: Color, _ t: String) -> some View { HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 8); Text(t) } }
}

// MARK: - A poster flips to its trailer

struct FlipFilm: Identifiable { let id = UUID(); let title: String; let poster: String?; let watchId: String?; let tmdbId: Int?; let mediaType: String?; var fav: Bool }

struct TrailerFlip: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var film: FlipFilm
    var open: ((String) -> Void)? = nil
    @State private var turned = false
    @State private var trailer: Trailer?
    @State private var searched = false

    var body: some View {
        ZStack {
            Color.black.opacity(turned ? 0.72 : 0).ignoresSafeArea().onTapGesture { close() }
            ZStack {
                // front: the poster
                Color(hex: 0x333030).overlay { RemoteImage(url: film.poster) }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .opacity(turned ? 0 : 1)
                // back: the trailer
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        if let t = trailer { YouTubeView(key: t.key) }
                        else { Text(searched ? "Трейлера не знайшлось" : "Шукаю трейлер…").font(.system(size: 13)).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit).background(.black).clipShape(RoundedRectangle(cornerRadius: 14))
                    Text(film.title).font(.system(size: 18, weight: .bold))
                    HStack(spacing: 6) {
                        if let id = film.watchId, let open { pill("Відкрити", "arrow.up.right") { dismiss(); open(id) } }
                        pill(film.fav ? "В обраному" : "В обране", film.fav ? "star.fill" : "star", on: film.fav) { Task { await toggleFav() } }
                        pill("Закрити", "xmark") { close() }
                    }
                }
                .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: 0x161414), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .foregroundStyle(.white)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(turned ? 1 : 0)
            }
            .frame(width: turned ? min(UIScreen.main.bounds.width - 32, 420) : 150, height: turned ? 360 : 225)
            .rotation3DEffect(.degrees(turned ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
        .presentationBackground(.clear)
        .onAppear { withAnimation(.spring(response: 0.75, dampingFraction: 0.8)) { turned = true } }
        .task {
            if let id = film.watchId { trailer = try? await API.current().trailer(watchId: id) }
            else if let t = film.tmdbId, let m = film.mediaType { trailer = try? await API.current().trailer(tmdbId: t, mediaType: m) }
            else { trailer = try? await API.current().trailer(title: film.title) }
            searched = true
        }
        .sensoryFeedback(.impact(weight: .light), trigger: turned)
    }

    private func pill(_ t: String, _ icon: String, on: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Label(t, systemImage: icon).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).frame(height: 38).background(.white.opacity(0.14), in: Capsule()) }
            .foregroundStyle(on ? Color(hex: 0xF2B640) : .white)
    }
    private func close() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { turned = false }
        Task { try? await Task.sleep(for: .milliseconds(350)); dismiss() }
    }
    private func toggleFav() async {
        let on = !film.fav
        if let id = film.watchId { try? await API.current().setFav(id, on) }
        else if on { try? await API.current().fav(title: film.title, movieUrl: nil, poster: film.poster) }
        else { try? await API.current().unfav(title: film.title) }
        film.fav = on
        await store.refreshAll()
    }
}

/// YouTube embed (no-cookie) inside the app.
struct YouTubeView: UIViewRepresentable {
    let key: String
    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []
        let w = WKWebView(frame: .zero, configuration: c)
        w.isOpaque = false; w.backgroundColor = .black; w.scrollView.isScrollEnabled = false
        let html = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;background:#000;height:100%}iframe{border:0;width:100%;height:100%}</style></head>
        <body><iframe src="https://www.youtube-nocookie.com/embed/\(key)?playsinline=1&autoplay=1&rel=0" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe></body></html>
        """
        w.loadHTMLString(html, baseURL: URL(string: "https://davincit-167-233-130-88.sslip.io"))
        return w
    }
    func updateUIView(_ v: WKWebView, context: Context) {}
}

/// «+ Своє»: a name, minutes and an icon — saved as a button in pomodoro.
struct PresetSheet: View {
    var saved: (PomoPreset) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var minutes = 25
    @State private var icon = "sparkle"

    var body: some View {
        NavigationStack {
            SoftForm {
                Section {
                    TextField("Назва: гітара, код, медитація…", text: $name)
                    Stepper("\(minutes) хв", value: $minutes, in: 5...300, step: 5)
                } footer: { Text("Збережеться кнопкою в помодоро: один тап — і таймер іде. Прибрати — затиснути кнопку.") }
                Section("Іконка") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                        ForEach(PomoPreset.icons, id: \.self) { ic in
                            let pr = PomoPreset(name: "", icon: ic, minutes: 1)
                            Button { icon = ic; Haptic.hit(.light) } label: {
                                Image(systemName: pr.symbol).font(.system(size: 18)).frame(maxWidth: .infinity).frame(height: 40)
                                    .background(icon == ic ? Theme.olive : Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(icon == ic ? Theme.cream : Theme.olive)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Своя справа").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрити") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти") { saved(PomoPreset(name: name.trimmingCharacters(in: .whitespaces), icon: icon, minutes: minutes)); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .tint(Theme.olive)
    }
}
