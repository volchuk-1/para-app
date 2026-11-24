import SwiftUI

// MARK: - Widgets like Apple's: small (square), medium (wide), large. A stack of faces turns as a cube.
// Press and hold a widget — its settings: size, the stack, colours.

extension Color {
    /// "#rrggbb" → colour
    init?(hexString s: String?) {
        guard let s, s.hasPrefix("#"), s.count == 7, let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        self.init(hex: v)
    }
    /// colour → "#rrggbb"
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", c(r), c(g), c(b))
    }
}

enum WidgetKind {
    /// kind, name, SF symbol — in the order of the settings list
    static let all: [(String, String, String)] = [
        ("card", "Натхнення", "sparkles"),
        ("event", "Подія", "calendar"), ("evening", "Вечір", "moon.stars"), ("film", "Фільм", "film"),
        ("turn", "Чия черга обирати фільм", "arrow.left.arrow.right"), ("pomodoro", "Помодоро", "timer"),
        ("note", "Записка", "note.text"), ("coin", "Монетка", "circle.circle"),
        ("jar", "Банка", "banknote"), ("memory", "Спогад", "photo"), ("spotify", "Spotify", "music.note"),
    ]
    /// standard background and text colour of a face
    static func palette(_ f: String) -> (Color, Color) {
        switch f {
        case "event": return (Theme.olive, Theme.cream)
        case "jar": return (Theme.sand, Theme.ink)
        case "film": return (Color(hex: 0x211F1D), .white)
        case "evening": return (Theme.coffee, .white)
        case "pomodoro": return (.black, .white)
        case "note": return (Color(hex: 0xE6E2D6), Theme.ink)
        case "mood": return (Color(hex: 0xDCE3CF), Theme.ink)
        case "turn": return (Theme.ink, Theme.cream)
        case "coin": return (Color(hex: 0xC9A27E), Theme.ink)
        case "touch": return (Theme.paper, Theme.ink)
        case "spotify": return (Color(hex: 0x1F1F1F), .white)
        case "card": return (Color(hex: 0x2F3A24), Theme.cream)
        default: return (Color(hex: 0x555555), .white)
        }
    }
    /// Faces whose background is a picture — the background colour does not apply to them.
    static func hasPhoto(_ f: String) -> Bool { f == "memory" || f == "spotify" }
}

/// A card with two sides that turns over in 3D (not a flat fade): the far edge shrinks, the card dips a little.
struct Flip3D<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }
    var body: some View {
        let a = angle.truncatingRemainder(dividingBy: 360)
        let showFront = a < 90 || a > 270
        return ZStack {
            front.opacity(showFront ? 1 : 0)
            back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0)).opacity(showFront ? 0 : 1)
        }
        .scaleEffect(1 - 0.14 * abs(sin(a * .pi / 180)))
        .rotation3DEffect(.degrees(a), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}

/// The grid: small widgets go two in a row, medium and large take the whole row.
struct WidgetGrid: View {
    let layout: [DashWidget]
    let d: Dashboard
    let spot: SpotNow?
    var spotAt: Date = Date()
    var onTap: (String) -> Void
    var onEdit: (DashWidget) -> Void
    var onTouch: (String) -> Void
    var onQuick: (String, String, String) -> Void = { _, _, _ in }
    private let gap: CGFloat = 10

    var body: some View {
        let full = UIScreen.main.bounds.width - 32
        let side = ((full - gap) / 2).rounded(.down)
        return VStack(alignment: .leading, spacing: gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: gap) {
                    ForEach(row) { w in
                        WidgetCube(w: w, d: d, spot: spot, spotAt: spotAt, onTap: onTap, onEdit: { onEdit(w) }, onTouch: onTouch, onQuick: onQuick)
                            .frame(width: w.size == "s" ? side : full, height: w.size == "l" ? side * 2 + gap : side)
                            .id(w)
                    }
                }
                .frame(width: full, alignment: .leading)
            }
        }
    }

    private var rows: [[DashWidget]] {
        var out: [[DashWidget]] = []
        var open: Int?
        for w in layout {
            if w.size == "s" {
                if let i = open { out[i].append(w); open = nil } else { out.append([w]); open = out.count - 1 }
            } else {
                out.append([w])
            }
        }
        return out
    }
}

/// One widget. Several faces make a stack that flips like Apple's Smart Stack: a swipe up or down slides the face
/// away (it shrinks a little) and the next one in; the dots on the side show only while it moves.
struct WidgetCube: View {
    let w: DashWidget
    let d: Dashboard
    let spot: SpotNow?
    var spotAt: Date = Date()
    var onTap: (String) -> Void
    var onEdit: () -> Void
    var onTouch: (String) -> Void
    var onQuick: (String, String, String) -> Void = { _, _, _ in }
    @State private var idx = 0
    @State private var drag: CGFloat = 0
    @State private var showDots = false
    @State private var fin: Finance4?
    @State private var today: DayPlan?
    @State private var flipped = false
    @State private var lastTap = Date.distantPast
    @State private var pulse: String?

    private var faces: [String] { w.faces.isEmpty ? ["event"] : w.faces }
    private var big: Bool { w.size == "l" }
    private var wide: Bool { w.size != "s" }
    private var cur: String { faces[idx % faces.count] }
    /// font size for this widget's size
    private func fs(_ base: CGFloat) -> CGFloat { big ? base * 1.5 : wide ? base * 1.15 : base }

    var body: some View {
        GeometryReader { g in
            let h = g.size.height + 12
            // −1: the next face is fully in; +1: the previous one
            let p = max(-1, min(1, drag / h))
            ZStack {
                if faces.count > 1, p != 0 {
                    other(p, h)
                }
                face(cur, index: idx)
                    .scaleEffect(1 - 0.12 * abs(p))
                    .opacity(1 - 0.4 * abs(p))
                    .offset(y: p * h)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .trailing) { if faces.count > 1 { sideDots.opacity(showDots ? 1 : 0) } }
            .contentShape(Rectangle())
            .onTapGesture { tap() }
            .onLongPressGesture(minimumDuration: 0.45) { Haptic.hit(.heavy); onEdit() }
            .highPriorityGesture(stackDrag(h), including: faces.count > 1 ? .all : .subviews)
        }
        .task {
            if faces.contains("jar") { fin = try? await API.current().finance4() }
            if faces.contains("evening") {
                let t = Evening.iso(Date())
                today = (try? await API.current().availability(from: t, to: t))?.first
            }
        }
    }

    /// The face that comes in: from below when the finger goes up, from above when it goes down.
    private func other(_ p: CGFloat, _ h: CGFloat) -> some View {
        let i = p < 0 ? (idx + 1) % faces.count : (idx - 1 + faces.count) % faces.count
        return face(faces[i], index: i)
            .scaleEffect(0.88 + 0.12 * abs(p))
            .offset(y: (p < 0 ? h : -h) + p * h)
    }

    private var sideDots: some View {
        VStack(spacing: 4) {
            ForEach(0..<faces.count, id: \.self) { i in
                Circle().fill(Color.white.opacity(i == idx % faces.count ? 1 : 0.4)).frame(width: 5, height: 5)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 3)
        .background(Color.black.opacity(0.28), in: Capsule())
        .padding(.trailing, 6)
        .allowsHitTesting(false)
    }

    private func stackDrag(_ h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                guard drag != 0 || abs(v.translation.height) > abs(v.translation.width) else { return }
                if !showDots { withAnimation(.easeOut(duration: 0.2)) { showDots = true } }
                drag = v.translation.height
            }
            .onEnded { v in
                guard drag != 0 else { return }
                let far = abs(v.translation.height) > 44 || abs(v.predictedEndTranslation.height) > h * 0.6
                let go = far ? (v.translation.height < 0 ? 1 : -1) : 0
                if go == 0 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { drag = 0 }
                    hideDots()
                    return
                }
                Haptic.hit(.heavy)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { drag = CGFloat(-go) * h } completion: {
                    idx = (idx + go + faces.count) % faces.count
                    drag = 0
                    hideDots()
                }
            }
    }

    private func hideDots() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            if drag == 0 { withAnimation(.easeOut(duration: 0.3)) { showDots = false } }
        }
    }

    private func tap() {
        guard cur == "spotify" else { onTap(cur); return }
        // Spotify: a double tap turns the card over to the partner's side
        if Date().timeIntervalSince(lastTap) < 0.4 {
            lastTap = .distantPast
            Haptic.hit(.heavy)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) { flipped.toggle() }
        } else {
            lastTap = Date()
        }
    }

    // MARK: a face

    private func face(_ f: String, index: Int) -> some View {
        let std = WidgetKind.palette(f)
        let bg = WidgetKind.hasPhoto(f) ? std.0 : (Color(hexString: w.colors?.bg) ?? std.0)
        let fg = WidgetKind.hasPhoto(f) ? std.1 : (Color(hexString: w.colors?.fg) ?? std.1)
        let ac = Color(hexString: w.colors?.ac) ?? (f == "touch" || f == "jar" ? Theme.olive : fg)
        return ZStack(alignment: .topTrailing) {
            bg
            inner(f, fg: fg, ac: ac)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func dots(_ index: Int, _ fg: Color) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<faces.count, id: \.self) { i in
                Circle().fill(fg.opacity(i == index % faces.count ? 1 : 0.3)).frame(width: 5, height: 5)
            }
        }
        .padding(14)
    }

    @ViewBuilder private func inner(_ f: String, fg: Color, ac: Color) -> some View {
        if f == "spotify" {
            spotifyFace()
        } else if f == "touch" {
            touchFace(fg: fg, ac: ac)
        } else {
            ZStack(alignment: .bottomLeading) {
                backdrop(f)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(f).uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(1.2).opacity(0.75).lineLimit(1)
                    Spacer(minLength: 0)
                    content(f, ac: ac)
                }
                .padding(big ? 18 : 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .foregroundStyle(f == "memory" ? .white : fg)
            }
        }
    }

    /// The picture behind a face — it fills the widget and never spills out of it.
    @ViewBuilder private func backdrop(_ f: String) -> some View {
        if f == "memory", let u = d.photo?.url {
            Color.clear.overlay(AuthImage(url: u)).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
        } else if f == "card", let u = d.card?.image {
            Color.clear.overlay(RemoteImage(url: u).opacity(0.45)).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        } else if f == "film", w.colors?.bg == nil, let u = d.film?.backdropUrl {
            Color.clear.overlay(RemoteImage(url: u).opacity(0.55)).clipped()
        }
    }

    private func title(_ f: String) -> String {
        switch f {
        case "event": return "Подія"
        case "jar": return "Банка"
        case "film": return "Дивимось"
        case "evening": return "Сьогодні ввечері"
        case "pomodoro": return "Помодоро"
        case "note": return "Записка"
        case "mood": return "Настрій"
        case "turn": return "Обирає фільм"
        case "coin": return "Монетка"
        case "card": return (d.card?.tag ?? "Натхнення") + (d.card?.youtube != nil ? " · ▶ відео" : "")
        case "memory": return d.photo?.yearAgo == true ? "Рік тому" : "Спогад"
        default: return f
        }
    }

    private func head(_ s: String, _ size: CGFloat = 17, lines: Int = 2) -> some View {
        Text(s).font(.system(size: fs(size), weight: .bold)).lineLimit(big ? lines + 2 : lines).minimumScaleFactor(0.7)
    }
    private func sub(_ s: String) -> some View {
        Text(s).font(.system(size: fs(12))).opacity(0.8).lineLimit(1).minimumScaleFactor(0.7)
    }

    @ViewBuilder private func content(_ f: String, ac: Color) -> some View {
        switch f {
        case "event": eventFace()
        case "jar": jarFace(ac)
        case "film": filmFace()
        case "evening": eveningFace()
        case "pomodoro": pomoFace()
        case "note": noteFace()
        case "mood": moodFace()
        case "turn":
            Text(d.turn.name).font(.system(size: fs(26), weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
            sub(d.turn.memberId == d.me.id ? "твоя черга" : "черга партнера")
        case "coin":
            head(d.coin.map { "\($0.question) — \($0.winnerName)" } ?? "Підкинь монетку", 15, lines: 3)
        case "card":
            if let c = d.card {
                head(c.title, 16)
                if wide, !c.text.isEmpty { Text(c.text).font(.system(size: fs(12.5))).opacity(0.85).lineLimit(big ? 6 : 2) }
            } else {
                head("Скоро тут буде картка", 15)
            }
        case "memory":
            head(d.photo?.title ?? "Додай перше фото", 16)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func eventFace() -> some View {
        if let n = d.next {
            head(n.title)
            sub(n.startsAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "uk_UA"))) + " · " + n.startsAt.shortTime)
            if wide, let p = n.place { sub(p) }
        } else {
            head("Попереду пусто")
            sub("тап — запросити")
        }
    }

    @ViewBuilder private func jarFace(_ ac: Color) -> some View {
        if let j = (fin?.jars ?? []).first(where: { $0.goal != nil }) ?? fin?.jars.first {
            Text(MoneyText.uah(j.balance)).font(.system(size: fs(26), weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
            if let goal = j.goal, goal > 0 {
                ProgressView(value: min(1, max(0, j.balance / goal))).tint(ac)
                sub("\(j.title) · \(Int(min(1, max(0, j.balance / goal)) * 100))%")
            } else {
                sub(j.title)
            }
        } else {
            head("…")
        }
    }

    @ViewBuilder private func filmFace() -> some View {
        if let fl = d.film {
            head(fl.title)
            sub(fl.season.map { "S\($0)E\(fl.episode ?? 0)" } ?? "фільм")
        } else {
            head("Нічого зараз")
        }
    }

    private func eveningLabel(_ t: DayPlan) -> String {
        if t.isFree { let from: String? = t.freeFrom; return "♥ Обоє вільні" + (from.map { " з " + $0 } ?? "") }
        return t.status == "plan" ? "Вже є план" : t.status == "home" ? "Лише вдома" : "Зайнято"
    }

    @ViewBuilder private func eveningFace() -> some View {
        if let t = today {
            head(eveningLabel(t), 16)
            if t.isFree {
                HStack(spacing: 4) {
                    quick("cinema", "Кіно", t)
                    quick("home", "Вдома", t)
                    quick("walk", "Гуляти", t)
                }
            }
        } else {
            head("…")
        }
    }
    private func quick(_ kind: String, _ label: String, _ t: DayPlan) -> some View {
        Button(label) {
            Haptic.hit(.medium)
            onQuick(kind, label, t.freeFrom.isEmpty ? "19:30" : t.freeFrom)
        }
        .font(.system(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity).frame(height: 28).background(.white.opacity(0.2), in: Capsule())
        .buttonStyle(.plain)
    }

    @ViewBuilder private func pomoFace() -> some View {
        if let p = d.pomo.me {
            Text(timerInterval: Date()...max(Date(), p.endsAt), countsDown: true).font(.system(size: fs(28), weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            sub("ти · \(p.activity)")
        } else {
            head("Фокус?")
            sub("тап — справа й час")
        }
        if let p = d.pomo.partner { sub("\(d.partner?.name ?? ""): \(p.activity)") }
    }

    @ViewBuilder private func noteFace() -> some View {
        if let n = d.note {
            head(n.text.isEmpty ? "📷" : n.text, 16, lines: 3)
            sub(d.partner?.name ?? "")
        } else {
            head("Напиши \(d.partner?.name ?? "")", 16)
        }
    }

    private func moodFace() -> some View {
        HStack(spacing: wide ? 28 : 18) {
            VStack(spacing: 2) { Text(d.mood.me?.emoji ?? "·").font(.system(size: fs(34))); Text("ти").font(.system(size: 10)) }
            VStack(spacing: 2) { Text(d.mood.partner?.emoji ?? "·").font(.system(size: fs(34))); Text(d.partner?.name ?? "").font(.system(size: 10)).lineLimit(1) }
        }
    }

    // MARK: «думаю про тебе», «скучаю», монетка

    private func touchFace(fg: Color, ac: Color) -> some View {
        let lay = wide ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 5))
        return lay {
            touchButton("think", "heart.fill", "Думаю про тебе", fg: fg, ac: ac)
            touchButton("miss", "hand.raised.fill", "Скучаю", fg: fg, ac: ac)
            touchButton("coin", "circle.circle.fill", "Монетка", fg: fg, ac: ac)
        }
        .padding(10)
        .foregroundStyle(fg)
    }

    private func touchButton(_ k: String, _ icon: String, _ label: String, fg: Color, ac: Color) -> some View {
        Button { press(k) } label: {
            touchLabel(icon, label, ac)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(fg.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .scaleEffect(pulse == k ? 1.1 : 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func touchLabel(_ icon: String, _ label: String, _ ac: Color) -> some View {
        if wide {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: big ? 32 : 22)).foregroundStyle(ac)
                Text(label).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
        } else {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(ac).frame(width: 20)
                Text(label).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
        }
    }

    private func press(_ k: String) {
        if k == "coin" { onTap("coin"); return }
        Haptic.hit(.heavy)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { pulse = k }
        onTouch(k)
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation { pulse = nil }
        }
    }

    // MARK: Spotify — Spotify's own look; a double tap turns the card over in 3D to the partner's side

    @ViewBuilder private func spotifyFace() -> some View {
        if let s = spot, s.ready {
            Flip3D(angle: flipped ? 180 : 0,
                   front: spotSide(s.me, who: "Ти", tint: Color(hex: 0x1F1F1F)),
                   back: spotSide(s.partner, who: s.partner?.name ?? d.partner?.name ?? "", tint: Color(hex: 0x2F3A24)))
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("SPOTIFY").font(.system(size: 10.5, weight: .bold)).tracking(1.2).opacity(0.75)
                Spacer(minLength: 0)
                head(spot == nil ? "…" : "Ще не підключено", 16)
                sub("Налаштування → Spotify")
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(hex: 0xE6E2D6))
            .foregroundStyle(Theme.ink)
        }
    }

    private func spotSide(_ side: SpotSide?, who: String, tint: Color) -> some View {
        let t = side?.track
        let state = side?.linked == false ? "не підключено" : t?.playing == true ? "зараз грає" : "останнє"
        return ZStack {
            tint
            if let c = t?.cover {
                Color.clear.overlay(RemoteImage(url: c).blur(radius: 40).scaleEffect(1.7).opacity(0.8)).clipped()
                Color.black.opacity(0.3)
            }
            spotLayout(t, label: "\(who) · \(state)").padding(wide ? 14 : 12)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                if t?.playing == true { Image(systemName: "waveform").symbolEffect(.variableColor.iterative).font(.system(size: 12, weight: .bold)) }
                SpotifyGlyph().frame(width: 20, height: 20)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .foregroundStyle(.white)
    }

    @ViewBuilder private func spotLayout(_ t: SpotTrack?, label: String) -> some View {
        if w.size == "m" {
            HStack(spacing: 0) {
                spotArt(t).padding(.trailing, 44)
                spotText(t, label: label)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                spotArt(t)
                Spacer(minLength: 6)
                spotText(t, label: label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func spotArt(_ t: SpotTrack?) -> some View {
        let side: CGFloat = big ? 150 : wide ? 116 : 60
        let on = t?.playing == true
        return ZStack {
            VinylDisc(spinning: on).frame(width: side * 0.9, height: side * 0.9).offset(x: side * (on ? 0.4 : 0.26))
            Color(hex: 0x333333).overlay(RemoteImage(url: t?.cover)).frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
        }
        .frame(width: side, height: side)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: on)
    }

    private func spotText(_ t: SpotTrack?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.6).opacity(0.8).lineLimit(1).minimumScaleFactor(0.7)
            Text(t?.title ?? "Нічого не грає").font(.system(size: big ? 24 : wide ? 17 : 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(t?.artist ?? "").font(.system(size: big ? 15 : 12.5)).opacity(0.85).lineLimit(1)
            if let t, (t.duration ?? 0) > 0 { SpotProgress(track: t, at: spotAt, compact: !wide) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - A widget's settings (press and hold): size, the stack, colours

struct WidgetEdit: Identifiable {
    var w: DashWidget
    let isNew: Bool
    var id: String { w.id }
}

struct WidgetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var w: DashWidget
    let isNew: Bool
    let track: SpotTrack?
    let partner: String
    var onSave: (DashWidget) -> Void
    var onDelete: () -> Void

    var body: some View {
        NavigationStack {
            SoftForm {
                if let track, w.faces.contains("spotify") {
                    Section {
                        Button {
                            Task { try? await API.current().spotifySend(track); Haptic.ok(); dismiss() }
                        } label: { Label("Надіслати «\(track.title)» \(partner)", systemImage: "paperplane.fill") }
                    }
                }
                Section("Розмір") {
                    Picker("Розмір", selection: $w.size) {
                        Text("Малий").tag("s")
                        Text("Середній").tag("m")
                        Text("Великий").tag("l")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    ForEach(WidgetKind.all, id: \.0) { k in faceRow(k) }
                } header: { Text("Стос") } footer: {
                    Text("Кілька граней — віджет перевертається свайпом, як куб. Порядок — як обираєш.")
                }
                Section {
                    ColorPicker("Фон", selection: bind(\.bg, std.0), supportsOpacity: false)
                    ColorPicker("Текст", selection: bind(\.fg, std.1), supportsOpacity: false)
                    ColorPicker("Акцент", selection: bind(\.ac, Theme.olive), supportsOpacity: false)
                    Button("Стандартні кольори") { w.colors = nil }
                } header: { Text("Кольори") } footer: {
                    Text("Для віджетів без фото: «Спогад» і Spotify мають свій фон. Акцент — іконки, смужки, кнопки.")
                }
                if !isNew {
                    Section { Button("Прибрати віджет", role: .destructive) { onDelete(); dismiss() } }
                }
            }
            .navigationTitle(isNew ? "Новий віджет" : "Віджет").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрити") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { onSave(w); dismiss() } }
            }
        }
        .tint(Theme.olive)
    }

    private var std: (Color, Color) { WidgetKind.palette(w.faces.first ?? "event") }

    private func faceRow(_ k: (String, String, String)) -> some View {
        Button {
            Haptic.hit(.light)
            if let i = w.faces.firstIndex(of: k.0) {
                if w.faces.count > 1 { w.faces.remove(at: i) }
            } else if w.faces.count < 6 {
                w.faces.append(k.0)
            }
        } label: {
            HStack {
                Label(k.1, systemImage: k.2)
                Spacer()
                if let i = w.faces.firstIndex(of: k.0) {
                    Text("\(i + 1)").font(.system(size: 12, weight: .bold)).frame(width: 24, height: 24)
                        .background(Theme.olive, in: Circle()).foregroundStyle(Theme.cream)
                }
            }
        }
        .foregroundStyle(Theme.ink)
    }

    private func bind(_ key: WritableKeyPath<WidgetColors, String?>, _ fallback: Color) -> Binding<Color> {
        Binding(
            get: { Color(hexString: (w.colors ?? WidgetColors())[keyPath: key]) ?? fallback },
            set: { v in
                var c = w.colors ?? WidgetColors()
                c[keyPath: key] = v.hexString
                w.colors = c
            }
        )
    }
}
