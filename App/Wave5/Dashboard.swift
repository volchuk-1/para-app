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

enum DashSheet: String, Identifiable { case mood, note, coin, widgets; var id: String { rawValue } }

struct DashboardPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Binding var route: Route?
    @Binding var page: Page
    @Environment(\.openURL) private var openURL
    @State private var d: Dashboard?
    @State private var spot: SpotNow?
    @State private var spotPartner = false
    @State private var sheet: DashSheet?
    @State private var slide = 0
    @State private var sendSong: SpotTrack?
    @State private var pulse: String?
    @State private var error: String?
    @State private var invite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let d {
                    if d.soon, let n = d.next { soonCard(n) }
                    shape(d)
                    HStack(spacing: 10) {
                        let faces = d.faces.isEmpty ? ["event"] : d.faces
                        let a = faces.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
                        let b = faces.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
                        CubeWidget(faces: a, d: d) { tapFace($0) }
                        CubeWidget(faces: b.isEmpty ? faces : b, d: d) { tapFace($0) }
                    }
                    .frame(height: 172)
                    spotify
                    touchRow
                } else {
                    RoundedRectangle(cornerRadius: 30).fill(Theme.tan.opacity(0.5)).frame(height: 420).overlay(ProgressView().tint(Theme.olive))
                }
                if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coffee) }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 130)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $sheet, onDismiss: { Task { await load() } }) { s in
            switch s {
            case .mood: MoodSheet()
            case .note: NoteSheet(partnerNote: d?.note, partner: d?.partner?.name ?? "")
            case .coin: CoinSheet(partner: d?.partner?.name ?? "")
            case .widgets: WidgetsSheet()
            }
        }
        .confirmationDialog("Надіслати пісню \(d?.partner?.name ?? "")?", isPresented: Binding(get: { sendSong != nil }, set: { if !$0 { sendSong = nil } }), titleVisibility: .visible) {
            Button("Надіслати «\(sendSong?.title ?? "")»") { if let t = sendSong { Task { try? await API.current().spotifySend(t) } } }
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
                    circleButton("pencil") { sheet = .widgets }
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

    private func bottomCard(_ d: Dashboard) -> some View {
        var slides: [(String?, String, String, String?)] = []
        if let f = d.film {
            var t = f.title
            if let se = f.season { t += " · S\(se)E\(f.episode ?? 0)" }
            slides.append((f.backdropUrl, "Дивимось", t, f.mediaType == "tv" ? f.id : nil))
        }
        if let n = d.next { slides.append((nil, "Наступне", n.title, nil)) }
        if let n = d.note, let u = n.photoUrl { slides.append((u, "Записка · \(d.partner?.name ?? "")", n.text, nil)) }
        return ZStack(alignment: .bottom) {
            TabView(selection: $slide) {
                ForEach(Array(slides.enumerated()), id: \.offset) { i, s in
                    ZStack(alignment: .bottomTrailing) {
                        LinearGradient(colors: [Theme.olive, Color(hex: 0x2F3A24)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        if let u = s.0 { if u.contains("/files/") { AuthImage(url: u) } else { RemoteImage(url: u) } }
                        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(s.1.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.4).opacity(0.85)
                            Text(s.2).font(.system(size: 17, weight: .bold)).multilineTextAlignment(.trailing).lineLimit(2)
                        }
                        .foregroundStyle(.white).padding(.trailing, 16).padding(.bottom, 30).frame(maxWidth: 220, alignment: .trailing)
                    }
                    .overlay(alignment: .topTrailing) {
                        if let id = s.3 {
                            Button("+1 серія") { Task { _ = try? await API.current().nextEpisode(id); await load(); await store.refreshAll() } }
                                .font(.system(size: 12.5, weight: .semibold)).padding(.horizontal, 12).frame(height: 30).background(.white.opacity(0.9), in: Capsule()).foregroundStyle(Theme.ink).padding(14)
                        }
                    }
                    .tag(i)
                }
                if slides.isEmpty {
                    Text("Тут будуть фільм, наступне побачення й записки").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: 0x6F7266))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 8) {
                ForEach(0..<max(slides.count, 1), id: \.self) { i in Circle().strokeBorder(.white, lineWidth: 1.5).background(Circle().fill(i == slide ? .white : .clear)).frame(width: 7, height: 7) }
            }
            .padding(.bottom, 10)
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

    // MARK: Spotify — one widget; double tap: the other one; long press: send the song

    private var spotify: some View {
        let side = spotPartner ? spot?.partner : spot?.me
        let t = side?.track
        return Group {
            if let s = spot, !s.ready {
                Button { sheet = .widgets } label: { spotRow(nil, small: "Spotify", title: "Ще не підключено", sub: "Налаштування → Віджети", dark: false) }.buttonStyle(.plain)
            } else {
                spotCard(t, small: (spotPartner ? (spot?.partner?.name ?? "") : "Ти") + (side?.linked == false ? " · не підключено" : t?.playing == true ? " · зараз грає" : " · останнє"))
                    .rotation3DEffect(.degrees(spotPartner ? 360 : 0), axis: (x: 1, y: 0, z: 0))
                    .onTapGesture(count: 2) { Haptic.hit(.heavy); withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { spotPartner.toggle() } }
                    .onLongPressGesture(minimumDuration: 0.45) { Haptic.hit(.heavy); if let t { sendSong = t } }
            }
            if let sent = spot?.me.sent, sent.at.timeIntervalSinceNow > -3 * 86400 {
                Button { if let u = sent.url?.asURL { openURL(u) } } label: {
                    Label("Тобі надіслали: \(sent.title)", systemImage: "music.note").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.olive)
                }
            }
        }
    }
    /// Like Spotify's own widget: the cover's colours behind, the cover, the logo, the track.
    private func spotCard(_ t: SpotTrack?, small: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: 0x1F1F1F)
            if let c = t?.cover { RemoteImage(url: c).blur(radius: 44).scaleEffect(1.7).opacity(0.8); Color.black.opacity(0.28) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    RemoteImage(url: t?.cover).frame(width: 66, height: 66).clipShape(RoundedRectangle(cornerRadius: 8)).shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                    Spacer()
                    if t?.playing == true { Image(systemName: "waveform").symbolEffect(.variableColor.iterative).font(.system(size: 15, weight: .bold)).padding(.top, 4).padding(.trailing, 6) }
                    SpotifyGlyph().frame(width: 26, height: 26)
                }
                Spacer(minLength: 12)
                Text(small.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(0.8).opacity(0.8)
                Text(t?.title ?? "Нічого не грає").font(.system(size: 18, weight: .bold)).lineLimit(1)
                Text(t?.artist ?? "").font(.system(size: 14)).opacity(0.85).lineLimit(1)
            }
            .padding(16)
        }
        .frame(height: 164)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }

    private func spotRow(_ cover: String?, small: String, title: String, sub: String, dark: Bool, playing: Bool = false) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: cover).frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .bottomTrailing) { Circle().fill(Color(hex: 0x1DB954)).frame(width: 16, height: 16).overlay(Circle().stroke(Theme.cream, lineWidth: 2)).offset(x: 5, y: 5) }
            VStack(alignment: .leading, spacing: 2) {
                Text(small).font(.system(size: 11.5)).opacity(0.7)
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(sub).font(.system(size: 12.5)).opacity(0.75).lineLimit(1)
            }
            Spacer()
            if playing { Image(systemName: "waveform").symbolEffect(.variableColor.iterative).foregroundStyle(Color(hex: 0x1DB954)) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(dark ? (spotPartner ? Color(hex: 0x2F3A24) : Theme.ink) : Color(hex: 0xE6E2D6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .foregroundStyle(dark ? Theme.cream : Theme.ink)
        .overlay(alignment: .topTrailing) { if dark { Text("2× тап — інший · затисни — надіслати").font(.system(size: 9)).opacity(0.4).padding(.trailing, 16).padding(.top, 7).foregroundStyle(Theme.cream) } }
    }

    // MARK: «думаю про тебе», «скучаю», coin

    private var touchRow: some View {
        HStack(spacing: 8) {
            touchButton("heart.fill", "Думаю про тебе") { await touch("think") }
            touchButton("hand.raised.fill", "Скучаю") { await touch("miss") }
            touchButton("circle.circle.fill", "Монетка") { sheet = .coin }
        }
        .padding(.top, 6)
    }
    private func touchButton(_ icon: String, _ t: String, _ a: @escaping () async -> Void) -> some View {
        Button { Task { await a() } } label: {
            VStack(spacing: 4) { Image(systemName: icon).font(.system(size: 21)).foregroundStyle(Theme.olive); Text(t).font(.system(size: 11.5, weight: .semibold)) }
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .scaleEffect(pulse == t ? 1.12 : 1)
        }
        .buttonStyle(.plain)
    }
    private func touch(_ kind: String) async {
        Haptic.hit(.heavy)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { pulse = kind == "miss" ? "Скучаю" : "Думаю про тебе" }
        do { try await API.current().touch(kind); state.banner = kind == "miss" ? "Надіслано: скучаю" : "\(d?.partner?.name ?? "") отримає сердечко" }
        catch { self.error = "Зачекай трохи перед наступним" }
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation { pulse = nil }
    }

    private func tapFace(_ f: String) {
        switch f {
        case "event": invite = true
        case "pomodoro": page = .pomo
        case "note": sheet = .note
        case "mood": sheet = .mood
        case "coin": sheet = .coin
        case "turn", "film": page = .watch
        case "memory": page = .archive
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
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - A widget cube: swipe turns it a quarter to the next face (only when there is more than one)

struct CubeWidget: View {
    let faces: [String]
    let d: Dashboard
    var onTap: (String) -> Void
    @State private var idx = 0
    @State private var turn: CGFloat = 0
    @State private var dir: CGFloat = 1
    @State private var fin: Finance4?
    @State private var today: DayPlan?

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let next = faces.isEmpty ? 0 : (idx + Int(dir) + faces.count) % faces.count
            ZStack {
                if turn > 0 {
                    face(faces[next], index: next)
                        .rotation3DEffect(.degrees(Double(dir * 90 * (1 - turn))), axis: (x: 0, y: 1, z: 0), anchor: dir > 0 ? .leading : .trailing, perspective: 0.6)
                        .offset(x: dir * w * (1 - turn))
                }
                face(faces[idx % max(1, faces.count)], index: idx)
                    .rotation3DEffect(.degrees(Double(-dir * 90 * turn)), axis: (x: 0, y: 1, z: 0), anchor: dir > 0 ? .trailing : .leading, perspective: 0.6)
                    .offset(x: -dir * w * turn)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 20).onEnded { v in
                guard faces.count > 1, abs(v.translation.width) > 28 else { return }
                dir = v.translation.width < 0 ? 1 : -1
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { turn = 1 } completion: {
                    idx = (idx + Int(dir) + faces.count) % faces.count
                    turn = 0
                }
            })
            .onTapGesture { if !faces.isEmpty { onTap(faces[idx % faces.count]) } }
            .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: idx)
        }
        .task {
            if faces.contains("jar") { fin = try? await API.current().finance4() }
            if faces.contains("evening") { let t = Evening.iso(Date()); today = (try? await API.current().availability(from: t, to: t))?.first }
        }
    }

    @ViewBuilder private func face(_ f: String, index: Int) -> some View {
        let (bg, fg): (Color, Color) = {
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
            default: return (Color(hex: 0x555555), .white)
            }
        }()
        ZStack(alignment: .bottomLeading) {
            bg
            if f == "memory", let u = d.photo?.url { AuthImage(url: u); LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom) }
            if f == "film", let u = d.film?.backdropUrl { RemoteImage(url: u).opacity(0.55) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title(f).uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(1.2).opacity(0.75)
                Spacer(minLength: 0)
                content(f)
            }
            .padding(14).foregroundStyle(fg)
            if faces.count > 1 {
                HStack(spacing: 3) { ForEach(0..<faces.count, id: \.self) { i in Circle().fill(fg.opacity(i == index % faces.count ? 1 : 0.3)).frame(width: 5, height: 5) } }
                    .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func eveningLabel(_ t: DayPlan) -> String {
        if t.isFree { let from: String? = t.freeFrom; return "♥ Обоє вільні" + (from.map { " з " + $0 } ?? "") }
        return t.status == "plan" ? "Вже є план" : t.status == "home" ? "Лише вдома" : "Зайнято"
    }

    private func title(_ f: String) -> String {
        ["event": "Подія", "jar": "Банка", "film": "Дивимось", "evening": "Сьогодні ввечері", "pomodoro": "Помодоро", "note": "Записка", "mood": "Настрій", "turn": "Обирає фільм", "coin": "Монетка", "memory": d.photo?.yearAgo == true ? "Рік тому" : "Спогад"][f] ?? f
    }

    @ViewBuilder private func content(_ f: String) -> some View {
        switch f {
        case "event":
            if let n = d.next {
                Text(n.title).font(.system(size: 17, weight: .bold)).lineLimit(2)
                Text(n.startsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Locale(identifier: "uk_UA")))).font(.system(size: 12)).opacity(0.8)
            } else { Text("Попереду пусто").font(.system(size: 17, weight: .bold)); Text("тап — запросити").font(.system(size: 12)).opacity(0.8) }
        case "jar":
            if let j = (fin?.jars ?? []).first(where: { $0.goal != nil }) ?? fin?.jars.first {
                Text(MoneyText.uah(j.balance)).font(.system(size: 26, weight: .semibold))
                if let goal = j.goal { ProgressView(value: min(1, j.balance / goal)).tint(Theme.olive); Text("\(j.title) · \(Int(min(1, j.balance / goal) * 100))%").font(.system(size: 12)) }
                else { Text(j.title).font(.system(size: 12)) }
            } else { Text("…").font(.system(size: 17, weight: .bold)) }
        case "film":
            if let fl = d.film {
                Text(fl.title).font(.system(size: 17, weight: .bold)).lineLimit(2)
                Text(fl.season.map { "S\($0)E\(fl.episode ?? 0)" } ?? "фільм").font(.system(size: 12)).opacity(0.8)
            } else { Text("Нічого зараз").font(.system(size: 17, weight: .bold)) }
        case "evening":
            if let t = today {
                Text(eveningLabel(t)).font(.system(size: 16, weight: .bold))
                if t.isFree {
                    HStack(spacing: 4) {
                        ForEach([("cinema", "Кіно"), ("home", "Вдома"), ("walk", "Гуляти")], id: \.0) { k in
                            Button(k.1) { Task { let from: String? = t.freeFrom; try? await API.current().quickEvening(k.0, time: from ?? "19:30") } }
                                .font(.system(size: 11.5, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 28).background(.white.opacity(0.2), in: Capsule())
                        }
                    }
                }
            } else { Text("…").font(.system(size: 17, weight: .bold)) }
        case "pomodoro":
            if let p = d.pomo.me {
                Text(timerInterval: Date()...max(Date(), p.endsAt), countsDown: true).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                Text("ти · \(p.activity)").font(.system(size: 12)).opacity(0.8)
            } else { Text("Фокус?").font(.system(size: 17, weight: .bold)); Text("тап — справа й час").font(.system(size: 12)).opacity(0.8) }
            if let p = d.pomo.partner { Text("\(d.partner?.name ?? ""): \(p.activity)").font(.system(size: 11.5)).opacity(0.75) }
        case "note":
            if let n = d.note { Text(n.text.isEmpty ? "📷" : n.text).font(.system(size: 16, weight: .bold)).lineLimit(3); Text(d.partner?.name ?? "").font(.system(size: 12)).opacity(0.7) }
            else { Text("Напиши \(d.partner?.name ?? "")").font(.system(size: 16, weight: .bold)) }
        case "mood":
            HStack(spacing: 18) {
                VStack { Text(d.mood.me?.emoji ?? "·").font(.system(size: 34)); Text("ти").font(.system(size: 10)) }
                VStack { Text(d.mood.partner?.emoji ?? "·").font(.system(size: 34)); Text(d.partner?.name ?? "").font(.system(size: 10)) }
            }
        case "turn":
            Text(d.turn.name).font(.system(size: 26, weight: .semibold))
            Text(d.turn.memberId == d.me.id ? "твоя черга" : "черга партнера").font(.system(size: 12)).opacity(0.8)
        case "coin":
            Text(d.coin.map { "\($0.question) — \($0.winnerName)" } ?? "Підкинь монетку").font(.system(size: 15, weight: .bold)).lineLimit(3)
        case "memory":
            Text(d.photo?.title ?? "Додай перше фото").font(.system(size: 16, weight: .bold)).lineLimit(2)
        default: EmptyView()
        }
    }
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
                Section("Пара слів для \(partner)") { TextField("Кава о 8? ☕", text: $text, axis: .vertical).lineLimit(2...5) }
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
            TextField("Хто миє посуд?", text: $q).padding(.horizontal, 14).frame(height: 46).background(Theme.cream, in: Capsule())
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

/// Settings → Віджети: faces of the dashboard cubes (in order) and Spotify.
struct WidgetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var faces: [String] = []
    @State private var all: [String] = []
    @State private var spot: SpotConnect?
    private let names: [String: (String, String)] = ["event": ("Подія", "calendar"), "jar": ("Банка", "banknote"), "film": ("Фільм", "film"), "evening": ("Вечір", "moon.stars"),
        "pomodoro": ("Помодоро", "timer"), "note": ("Записка", "note.text"), "mood": ("Настрій", "face.smiling"), "turn": ("Чия черга обирати фільм", "arrow.left.arrow.right"),
        "coin": ("Монетка", "circle.circle"), "memory": ("Спогад", "photo")]
    var body: some View {
        NavigationStack {
            SoftForm {
                Section {
                    ForEach(all, id: \.self) { f in
                        Button { if let i = faces.firstIndex(of: f) { faces.remove(at: i) } else { faces.append(f) } } label: {
                            HStack {
                                Label(names[f]?.0 ?? f, systemImage: names[f]?.1 ?? "square")
                                Spacer()
                                if let i = faces.firstIndex(of: f) { Text("\(i + 1)").font(.system(size: 12, weight: .bold)).frame(width: 24, height: 24).background(Theme.olive, in: Circle()).foregroundStyle(Theme.cream) }
                            }
                        }
                        .foregroundStyle(Theme.ink)
                    }
                } header: { Text("Грані кубиків") } footer: { Text("Порядок — як обираєш. Свайп по кубику перевертає на наступну грань; з однією гранню кубик не крутиться.") }
                Section {
                    if spot?.ready == true, let u = spot?.url?.asURL {
                        Button { openURL(u) } label: { Label("Підключити мій Spotify", systemImage: "music.note") }
                    } else {
                        Text("Spotify ще не налаштовано на сервері — Віктор вставить ключі, і тут з'явиться кнопка.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                } header: { Text("Spotify") }
            }
            .navigationTitle("Віджети").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрити") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { try? await API.current().setWidgets(faces); dismiss() } } }
            }
            .task {
                if let w = try? await API.current().widgets() { faces = w.faces; all = w.all ?? w.faces }
                spot = try? await API.current().spotifyConnect()
            }
        }
        .tint(Theme.olive)
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
