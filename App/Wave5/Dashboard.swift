import SwiftUI
import PhotosUI

// MARK: - The dashboard (Головна) in the shape of Viktor's reference

private let sageColor = Color(hex: 0xC7CABC)

/// The stat block: left column, a wide band under the photo with a concave fillet, and a short foot on the left.
struct StatShape: Shape {
    var leftW: CGFloat, photoH: CGFloat, footW: CGFloat, footH: CGFloat, gap: CGFloat = 8, r: CGFloat = 26
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, mainB = h - footH, top = photoH + gap
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r))
        p.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: leftW - r, y: 0))
        p.addArc(center: CGPoint(x: leftW - r, y: r), radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: leftW, y: top - r))
        p.addArc(center: CGPoint(x: leftW + r, y: top - r), radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: w - r, y: top))
        p.addArc(center: CGPoint(x: w - r, y: top + r), radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: w, y: mainB - r))
        p.addArc(center: CGPoint(x: w - r, y: mainB - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: footW + r, y: mainB))
        p.addArc(center: CGPoint(x: footW + r, y: mainB + r), radius: r, startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: footW, y: h - r))
        p.addArc(center: CGPoint(x: footW - r, y: h - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r, y: h))
        p.addArc(center: CGPoint(x: r, y: h - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The photo card below: its top-left is cut out around the foot of the stat block.
struct NotchCard: Shape {
    var notchW: CGFloat, notchH: CGFloat, r: CGFloat = 26
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: notchW, y: r))
        p.addArc(center: CGPoint(x: notchW + r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addArc(center: CGPoint(x: w - r, y: r), radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addArc(center: CGPoint(x: w - r, y: h - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r, y: h))
        p.addArc(center: CGPoint(x: r, y: h - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: 0, y: notchH + r))
        p.addArc(center: CGPoint(x: r, y: notchH + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: notchW - r, y: notchH))
        p.addArc(center: CGPoint(x: notchW - r, y: notchH - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.closeSubpath()
        return p
    }
}

enum DashSheet: String, Identifiable { case mood, note, coin, card; var id: String { rawValue } }
/// «Кіно / Вдома / Гуляти» on the evening face: asked first, sent after a yes.
struct QuickAsk { let kind: String; let label: String; let time: String }

struct DashboardPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Binding var route: Route?
    @Binding var page: Page
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var d: Dashboard?
    @State private var spot: SpotNow?
    @State private var spotAt = Date()
    @State private var quick: QuickAsk?
    @State private var sheet: DashSheet?
    @State private var editing: WidgetEdit?
    @State private var slide = 0
    @State private var pulse: String?
    @State private var error: String?
    @State private var invite = false
    @State private var filmOpen: WatchItem?
    @State private var watchIndex = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let d {
                    if d.soon, let n = d.next { soonCard(n) }
                    shape(d)
                    WidgetGrid(layout: layout(d), d: d, spot: spot, spotAt: spotAt,
                               onTap: { tapFace($0) },
                               onEdit: { editing = WidgetEdit(w: $0, isNew: false) },
                               onTouch: { k in Task { await touch(k) } },
                               onQuick: { kind, label, time in quick = QuickAsk(kind: kind, label: label, time: time) })
                    sentSong
                    touchRow
                    addButton
                } else {
                    RoundedRectangle(cornerRadius: 30).fill(Theme.tan.opacity(0.5)).frame(height: 420).overlay(ProgressView().tint(Theme.olive))
                }
                if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coffee) }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 130)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .onAppear { if d == nil { d = store.dash; spot = store.spot } }
        .task { await load() }
        .fullScreenCover(item: $filmOpen) { w in FilmPage(item: w, route: $route) }
        // Spotify stays live: every 12 s while the screen is open, and at once when the app comes back
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                if phase == .active, spot?.ready == true, let s = try? await API.current().spotifyNow() { spot = s; spotAt = Date() }
            }
        }
        .onChange(of: phase) { _, p in if p == .active { Task { await load() } } }
        .refreshable { await load() }
        .confirmationDialog(quick.map { "\($0.label) сьогодні о \($0.time)?" } ?? "", isPresented: Binding(get: { quick != nil }, set: { if !$0 { quick = nil } }), titleVisibility: .visible) {
            Button("Надіслати запрошення") {
                if let q = quick { Task { try? await API.current().quickEvening(q.kind, time: q.time); state.banner = "Запрошення надіслано"; await load() } }
            }
        } message: {
            Text("\(d?.partner?.name ?? "") отримає запрошення, а подія з'явиться в календарі. За годину до неї прийде нагадування.")
        }
        .sheet(item: $sheet, onDismiss: { Task { await load() } }) { s in
            switch s {
            case .mood: MoodSheet()
            case .note: NoteSheet(partnerNote: d?.note, partner: d?.partner?.name ?? "")
            case .coin: CoinSheet(partner: d?.partner?.name ?? "")
            case .card: if let c = d?.card { CardSheet(card: c) }
            }
        }
        .sheet(item: $editing) { e in
            WidgetEditSheet(w: e.w, isNew: e.isNew, track: spot?.me.track, partner: d?.partner?.name ?? "",
                            onSave: { w in Task { await save(w) } },
                            onDelete: { Task { await remove(e.w.id) } })
        }
        .fullScreenCover(isPresented: $invite) { InviteBooking(start: .blank) }
        .sensoryFeedback(.impact(weight: .heavy), trigger: pulse)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "uk_UA"))).capitalizedFirst)
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                Text("Привіт, \(state.me?.name ?? "")").font(.serif(28, .bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            // on the bell's level: the partner's mood on the left, mine on the right (tap to change)
            Button { Haptic.hit(.medium); sheet = .mood } label: {
                HStack(spacing: 2) {
                    Text(d?.mood.partner?.emoji ?? "·").font(.system(size: 22)).frame(width: 38, height: 38)
                    Text(d?.mood.me?.emoji ?? "🙂").font(.system(size: 22)).frame(width: 38, height: 38).background(Theme.tan.opacity(0.7), in: Circle())
                }
                .padding(4).background(Theme.paper, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 58).offset(y: -4)
        }
    }

    private func soonCard(_ n: DashEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((n.inMinutes ?? 0) < 120 ? "ВЖЕ СКОРО" : "СЬОГОДНІ").font(.system(size: 11, weight: .bold)).tracking(1.6).opacity(0.8)
            Text(n.title).font(.system(size: 22, weight: .semibold))
            Text(timerInterval: Date()...max(Date(), n.startsAt), countsDown: true).font(.system(size: 30, weight: .semibold)).monospacedDigit()
            Text(n.startsAt.formatted(.dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "uk_UA"))) + (n.place.map { " · \($0)" } ?? ""))
                .font(.system(size: 13)).opacity(0.8)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.olive, in: RoundedRectangle(cornerRadius: 28, style: .continuous)).foregroundStyle(Theme.cream)
    }

    // MARK: the shape

    private func shape(_ d: Dashboard) -> some View {
        GeometryReader { g in
            let W = g.size.width, gap: CGFloat = 8
            let leftW = (W * 0.57).rounded(), photoH: CGFloat = 168, mainH = photoH + gap + 206, footH: CGFloat = 44, cardH: CGFloat = 220
            ZStack(alignment: .topLeading) {
                StatShape(leftW: leftW, photoH: photoH, footW: leftW, footH: footH).fill(sageColor)
                    .frame(width: W, height: mainH + footH)
                // top-left: pen (widgets), chip, names
                VStack(alignment: .leading, spacing: 0) {
                    circleButton("plus") { addWidget() }
                    Spacer()
                    HStack(spacing: 5) { Image(systemName: "checkmark.seal.fill"); Text("Разом") }
                        .font(.system(size: 12.5, weight: .semibold)).padding(.horizontal, 11).padding(.vertical, 5).background(.white, in: Capsule())
                    Text("\(d.me.name) і \(d.partner?.name ?? "") · \(d.daysTogether) \(daysWord(d.daysTogether))").font(.system(size: 15)).foregroundStyle(Color(hex: 0x76786F)).padding(.top, 6)
                }
                .padding(16).frame(width: leftW, height: photoH + gap, alignment: .topLeading)
                // top-right photo
                Button { page = .archive } label: {
                    Color(hex: 0x9A9A90).overlay { if let u = d.photo?.url { AuthImage(url: u) } else { Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(.white.opacity(0.7)) } }
                        .overlay(alignment: .bottomLeading) {
                            if let p = d.photo { Text(p.yearAgo ? "рік тому" : p.title).font(.system(size: 11.5)).foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 3).background(.black.opacity(0.45), in: Capsule()).padding(10) }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(width: W - leftW - gap, height: photoH).offset(x: leftW + gap)
                // the band: month, wave, numbers
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(monthName()).font(.system(size: 48, weight: .regular)).tracking(-1.6).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer()
                        circleButton("info") { page = .stats }
                    }
                    waveView(d.wave).frame(height: 58)
                    HStack(alignment: .lastTextBaseline) {
                        Text("\(d.month.evenings)").font(.system(size: 64, weight: .regular)).tracking(-2)
                        Spacer()
                        numBox(d.month.films, "фільми"); numBox(d.month.books, "книжки")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 10)
                .frame(width: W, height: mainH - photoH - gap, alignment: .topLeading).offset(y: photoH + gap)
                Text("вечорів разом цього місяця").font(.system(size: 12.5)).foregroundStyle(Color(hex: 0x55574F))
                    .padding(.horizontal, 16).frame(width: leftW, height: footH, alignment: .leading).offset(y: mainH)
                // bottom card with the notch around the foot
                bottomCard(d).frame(width: W, height: cardH)
                    .clipShape(NotchCard(notchW: leftW + gap, notchH: footH))
                    .offset(y: mainH + gap)
            }
        }
        .frame(height: 168 + 8 + 206 + 8 + 220)
    }

    /// The big card under the shape: a stack of everything we are watching now. Tap — the film page;
    /// «На ноутбук» — open it on the laptop. Nothing on — the next date.
    private func bottomCard(_ d: Dashboard) -> some View {
        let list = (d.watching?.isEmpty == false ? d.watching : d.film.map { [$0] }) ?? []
        return Group {
            if list.isEmpty {
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(colors: [Theme.olive, Color(hex: 0x2F3A24)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    caption(d.next == nil ? "" : "Наступне", d.next?.title ?? "Тут буде те, що ви зараз дивитесь")
                }
            } else {
                StackPager(count: list.count, index: $watchIndex, onTap: { i in openFilm(list[i].id) }) { i in watchPage(list[i]) }
            }
        }
    }

    private func watchPage(_ f: DashFilm) -> some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [Theme.olive, Color(hex: 0x2F3A24)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Color.clear.overlay { if let u = f.backdropUrl ?? f.posterUrl { RemoteImage(url: u) } }.clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .trailing, spacing: 10) {
                caption(f.play?.since != nil ? "Дивимось зараз" : "Дивимось", f.title + (f.season.map { " · S\($0)E\(f.episode ?? 0)" } ?? ""))
                HStack(spacing: 6) {
                    if f.mediaType == "tv" {
                        Button("+1 серія") { Task { _ = try? await API.current().nextEpisode(f.id); await load(); await store.refreshAll() } }
                            .font(.system(size: 12.5, weight: .bold)).padding(.horizontal, 12).frame(height: 32)
                            .background(.white.opacity(0.92), in: Capsule()).foregroundStyle(Theme.ink)
                    }
                    Button { laptop(f) } label: {
                        Label("На ноутбук", systemImage: "laptopcomputer").font(.system(size: 12.5, weight: .bold))
                            .padding(.horizontal, 12).frame(height: 32).background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
    }

    private func caption(_ small: String, _ title: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if !small.isEmpty { Text(small.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.4).opacity(0.85) }
            Text(title).font(.system(size: 17, weight: .bold)).multilineTextAlignment(.trailing).lineLimit(2)
        }
        .foregroundStyle(.white).frame(maxWidth: 220, alignment: .trailing)
        .padding(.trailing, 2)
    }

    private func openFilm(_ id: String) {
        Haptic.hit(.medium)
        if let w = store.watch.first(where: { $0.id == id }) { filmOpen = w } else { page = .watch }
    }

    private func laptop(_ f: DashFilm) {
        Task {
            do {
                let r = try await API.current().remoteOpen(f.id)
                Haptic.ok()
                state.banner = r.online ? "Відкриваю на ноутбуці" : "Надіслано — запусти програму на ноутбуці"
                await load()
            } catch {
                state.banner = "Спершу підключи ноутбук: Налаштування → Системні"
            }
        }
    }

    private func circleButton(_ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44).background(.white, in: Circle()).foregroundStyle(Theme.ink) }
            .buttonStyle(.plain)
    }
    private func numBox(_ n: Int, _ l: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(n)").font(.system(size: 36)).foregroundStyle(Color(hex: 0x6E7066))
            Text(l).font(.system(size: 12)).foregroundStyle(Color(hex: 0x6E7066))
        }
        .padding(.leading, 14)
    }
    private func waveView(_ w: [Int]) -> some View {
        let mx = max(1, w.max() ?? 1)
        let top = Set(w.enumerated().sorted { $0.element > $1.element }.prefix(8).filter { $0.element > 0 }.map(\.offset))
        return HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(w.enumerated()), id: \.offset) { i, v in
                Capsule().fill(top.contains(i) ? Theme.ink : .white.opacity(0.55))
                    .frame(height: CGFloat(14 + Int(Double(v) / Double(mx) * 38) + (i % 3) * 3))
            }
        }
    }
    private func monthName() -> String {
        ["Січень", "Лютий", "Березень", "Квітень", "Травень", "Червень", "Липень", "Серпень", "Вересень", "Жовтень", "Листопад", "Грудень"][Calendar.current.component(.month, from: Date()) - 1]
    }
    private func daysWord(_ n: Int) -> String {
        let a = n % 10, b = n % 100
        return a == 1 && b != 11 ? "день" : (2...4).contains(a) && !(12...14).contains(b) ? "дні" : "днів"
    }

    // MARK: widgets: the layout, adding, saving

    /// The saved layout; an old server without it — the faces as small widgets.
    private func layout(_ d: Dashboard) -> [DashWidget] {
        if let l = d.layout { return l }
        return (d.faces.isEmpty ? ["event"] : d.faces).enumerated().map { DashWidget(id: "f\($0.offset)", size: "s", faces: [$0.element]) }
    }

    @ViewBuilder private var sentSong: some View {
        if let sent = spot?.me.sent, sent.at.timeIntervalSinceNow > -3 * 86400 {
            Button { if let u = sent.url?.asURL { openURL(u) } } label: {
                Label("Тобі надіслали: \(sent.title)", systemImage: "music.note").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.olive).lineLimit(1)
            }
        }
    }

    /// «Думаю про тебе», «Скучаю», монетка — three quiet buttons under the widgets.
    private var touchRow: some View {
        HStack(spacing: 6) {
            quiet("heart.fill", "Думаю про тебе") { Task { await touch("think") } }
            quiet("hand.raised.fill", "Скучаю") { Task { await touch("miss") } }
            quiet("circle.circle.fill", "Монетка") { sheet = .coin }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func quiet(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptic.hit(.heavy); action() } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.olive.opacity(0.8))
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(Theme.ink.opacity(0.045), in: Capsule())
            .foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        VStack(spacing: 8) {
            Button { addWidget() } label: {
                Label("Додати віджет", systemImage: "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            }
            .buttonStyle(.plain)
            Text("Затисни віджет — розмір, стос і кольори. Стос гортається вгору-вниз.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }

    private func addWidget() {
        Haptic.hit(.medium)
        editing = WidgetEdit(w: DashWidget(id: "w\(Int(Date().timeIntervalSince1970))", size: "s", faces: ["event"]), isNew: true)
    }

    private func save(_ w: DashWidget) async {
        guard let d else { return }
        var l = layout(d)
        if let i = l.firstIndex(where: { $0.id == w.id }) { l[i] = w } else { l.append(w) }
        await put(l)
    }

    private func remove(_ id: String) async {
        guard let d else { return }
        await put(layout(d).filter { $0.id != id })
    }

    private func put(_ l: [DashWidget]) async {
        do { _ = try await API.current().setLayout(l); Haptic.ok(); await load() }
        catch { self.error = error.localizedDescription }
    }

    private func touch(_ kind: String) async {
        pulse = kind + "\(Date().timeIntervalSince1970)"
        do { try await API.current().touch(kind); state.banner = kind == "miss" ? "Надіслано: скучаю" : "\(d?.partner?.name ?? "") отримає сердечко" }
        catch { self.error = "Зачекай трохи перед наступним" }
    }

    private func tapFace(_ f: String) {
        switch f {
        case "event": invite = true
        case "pomodoro": page = .pomo
        case "tasks": page = .tasks
        case "note": sheet = .note
        case "mood": sheet = .mood
        case "coin": sheet = .coin
        case "turn", "film": page = .watch
        case "memory": page = .archive
        case "card": sheet = .card
        case "jar": page = .finance
        default: break
        }
    }

    private func load() async {
        do {
            async let a = API.current().dashboard()
            async let b = API.current().spotifyNow()
            d = try await a
            spot = try? await b
            spotAt = Date()
            store.dash = d
            store.spot = spot
            if let d { Cache.save(d, "dash") }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - sheets

struct MoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let moods = ["😊", "🥰", "😴", "🤒", "😤", "🥲", "🤩", "😌", "🫠", "🔥"]
    @State private var custom = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Мій настрій").font(.serif(28, .bold))
            Text("Партнер побачить його на дашборді й у кубику.").font(.system(size: 14)).foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                EmojiField(text: $custom).frame(width: 76, height: 64).background(Theme.cream, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Будь-який смайлик").font(.system(size: 14, weight: .semibold))
                    Text("Тапни ліворуч — відкриється клавіатура емодзі.").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Готово") { Task { try? await API.current().setMood(custom); Haptic.ok(); dismiss() } }
                    .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 40).background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                    .disabled(custom.isEmpty).opacity(custom.isEmpty ? 0.4 : 1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(moods, id: \.self) { m in
                    Button { Task { try? await API.current().setMood(m); dismiss() } } label: { Text(m).font(.system(size: 32)).frame(maxWidth: .infinity, minHeight: 60).background(Theme.cream, in: RoundedRectangle(cornerRadius: 18)) }
                }
            }
            Spacer()
        }
        .padding(20).background(Theme.paper.ignoresSafeArea()).presentationDetents([.medium])
    }
}

struct NoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let partnerNote: NoteItem?
    let partner: String
    @State private var text = ""
    @State private var pick: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            SoftForm {
                if let n = partnerNote {
                    Section(partner) {
                        if let u = n.photoUrl { AuthImage(url: u).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 14)) }
                        Text(n.text)
                    }
                }
                Section("Пара слів для \(partner)") { TextField("Пара слів", text: $text, axis: .vertical).lineLimit(2...5) }
                Section {
                    PhotosPicker(selection: $pick, matching: .images) {
                        if let image { Image(uiImage: image).resizable().scaledToFill().frame(height: 160).clipped().clipShape(RoundedRectangle(cornerRadius: 14)) }
                        else { Label("Додати фото", systemImage: "photo") }
                    }
                } footer: { Text("Фото зберігається на сервері зашифрованим.") }
            }
            .navigationTitle("Записка").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрити") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Надіслати") { Task { await send() } }.disabled(busy || (text.isEmpty && image == nil)) }
            }
            .onChange(of: pick) { _, p in Task { if let p, let d = try? await p.loadTransferable(type: Data.self) { image = UIImage(data: d) } } }
        }
        .tint(Theme.olive)
    }
    private func send() async {
        busy = true; defer { busy = false }
        guard let n = try? await API.current().sendNote(text) else { return }
        if let image, let jpeg = image.resizedJPEG(maxSide: 1600) { try? await API.current().noteURLPhoto(n.id, jpeg: jpeg) }
        dismiss()
    }
}

struct CoinSheet: View {
    let partner: String
    @State private var q = ""
    @State private var spin = 0.0
    @State private var lift: CGFloat = 0
    @State private var result: String?
    var body: some View {
        VStack(spacing: 16) {
            Text("Монетка").font(.serif(28, .bold)).frame(maxWidth: .infinity, alignment: .leading)
            Text("Підкидає сервер — ви обоє бачите той самий результат, \(partner) отримає сповіщення в боті.").font(.system(size: 14)).foregroundStyle(Theme.muted)
            TextField("Питання", text: $q).padding(.horizontal, 14).frame(height: 46).background(Theme.cream, in: Capsule())
            Circle().fill(RadialGradient(colors: [Color(hex: 0xF2D08A), Color(hex: 0xC9A27E), Theme.coffee], center: .topLeading, startRadius: 4, endRadius: 120))
                .frame(width: 120, height: 120)
                .overlay(Text(result ?? "?").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink))
                .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0))
                .offset(y: -lift)
                .shadow(color: Theme.coffee.opacity(0.4), radius: 14, y: 10)
            Button { Task { await flip() } } label: { Text("Підкинути").frame(maxWidth: .infinity).frame(height: 50) }
                .font(.system(size: 16, weight: .semibold)).background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
            Spacer()
        }
        .padding(20).background(Theme.paper.ignoresSafeArea()).presentationDetents([.medium, .large])
        .sensoryFeedback(.impact(weight: .heavy), trigger: result)
    }
    private func flip() async {
        result = nil
        withAnimation(.easeOut(duration: 0.5)) { spin += 900; lift = 60 }
        let r = try? await API.current().coin(q.isEmpty ? "Хто обирає?" : q)
        try? await Task.sleep(for: .milliseconds(500))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { spin += 900; lift = 0 }
        try? await Task.sleep(for: .milliseconds(350))
        result = r.map { $0.winnerName }
    }
}

// MARK: - Splash: stays until the first screen has its data

struct SplashView: View {
    @State private var on = false
    var body: some View {
        ZStack {
            Theme.olive.ignoresSafeArea()
            VStack(spacing: 10) {
                (Text("Da").font(.serif(46, .bold)) + Text("Vi").font(.serif(46, .bold)).italic().foregroundColor(Theme.sand) + Text("ncit").font(.serif(46, .bold)))
                Text("AMOR VINCIT OMNIA").font(.system(size: 12, weight: .medium)).tracking(3.6).opacity(0.8)
                ProgressView().tint(Theme.cream).padding(.top, 20)
            }
            .foregroundStyle(Theme.cream)
            .scaleEffect(on ? 1 : 0.94).opacity(on ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { on = true } }
    }
}


/// One emoji from the system emoji keyboard.
struct EmojiField: UIViewRepresentable {
    @Binding var text: String
    func makeUIView(context: Context) -> EmojiTextField {
        let f = EmojiTextField()
        f.delegate = context.coordinator
        f.font = .systemFont(ofSize: 38)
        f.textAlignment = .center
        f.placeholder = "🙂"
        f.tintColor = .clear
        return f
    }
    func updateUIView(_ v: EmojiTextField, context: Context) { if v.text != text { v.text = text } }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: EmojiField
        init(_ p: EmojiField) { parent = p }
        func textField(_ tf: UITextField, shouldChangeCharactersIn range: NSRange, replacementString s: String) -> Bool {
            let v = s.last.map { String($0) } ?? ""
            tf.text = v
            parent.text = v
            return false
        }
    }
}

final class EmojiTextField: UITextField {
    override var textInputContextIdentifier: String? { "" }
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}

/// Spotify's mark: a white disc with three arcs.
struct SpotifyGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            ctx.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(.white))
            for (i, y) in [0.36, 0.52, 0.67].enumerated() {
                var p = Path()
                let inset = w * (0.2 + Double(i) * 0.04)
                p.move(to: CGPoint(x: inset, y: w * y))
                p.addQuadCurve(to: CGPoint(x: w - inset, y: w * (y + 0.05)), control: CGPoint(x: w / 2, y: w * (y - 0.13 + Double(i) * 0.02)))
                ctx.stroke(p, with: .color(Color(hex: 0x1F1F1F)), style: StrokeStyle(lineWidth: w * (0.085 - Double(i) * 0.012), lineCap: .round))
            }
        }
    }
}
