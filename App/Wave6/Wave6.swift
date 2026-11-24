import SwiftUI

// MARK: - Wave 6: the day's own card, trips as a page, where we stopped in a film + «На ноутбук»,
// a Spotify record and progress, invitations that swipe into the archive.

/// The day's card in the calendar — bigger than the hour rows: who is busy when on a scale with hours,
/// both names in full, and the same plan in words.
struct DayCard: View {
    let d: DayPlan
    let isToday: Bool
    let me: String
    let partner: String
    var onInvite: () -> Void
    private let from = 6 * 60, to = 24 * 60

    var body: some View {
        let date = Evening.date(d.date) ?? Date()
        let uk = Locale(identifier: "uk_UA")
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? "СЬОГОДНІ" : date.formatted(.dateTime.weekday(.wide).locale(uk)).uppercased())
                        .font(.system(size: 11, weight: .bold)).tracking(1.5).opacity(0.65)
                    Text(date.formatted(.dateTime.day().month(.wide).locale(uk))).font(.serif(28, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                Button(action: onInvite) {
                    Text(statusText).font(.system(size: 12.5, weight: .bold)).multilineTextAlignment(.center).lineLimit(2)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(statusColor, in: Capsule()).foregroundStyle(statusInk)
                }
                .buttonStyle(.plain).disabled(!d.isFree)
            }
            scale.padding(.top, 14)
            lane(me, d.blocks.me, off: d.meOff, known: d.meKnown ?? true)
            lane(partner, d.blocks.partner, off: d.partnerOff, known: d.partnerKnown ?? true)
            plan.padding(.top, 12)
            Text(Evening.note(d, partner: partner)).font(.system(size: 12.5)).opacity(0.7).padding(.top, 10)
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isToday ? Theme.ink : Theme.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .foregroundStyle(isToday ? Theme.cream : Theme.ink)
        .shadow(color: Theme.ink.opacity(isToday ? 0.22 : 0), radius: 16, y: 10)
    }

    private var statusText: String {
        switch d.status {
        case "free": return d.freeFrom.isEmpty ? "♥ Обоє вільні" : "♥ Обоє вільні з \(d.freeFrom)"
        case "day": return "♥ Вільні весь день"
        case "plan": return d.plan ?? "Є план"
        case "home": return "Лише вдома"
        case "maybe": return "Може бути"
        default: return "Вечір зайнятий"
        }
    }
    private var statusColor: Color {
        if d.isFree { return Theme.olive }
        if d.status == "plan" { return Theme.coffee }
        return Color.gray.opacity(0.25)
    }
    private var statusInk: Color {
        if d.isFree || d.status == "plan" { return Theme.cream }
        return isToday ? Theme.cream : Theme.ink
    }

    private func x(_ minutes: Int) -> CGFloat { CGFloat(max(0, min(1, Double(minutes - from) / Double(to - from)))) }

    private func tint(_ kind: String) -> Color {
        switch kind {
        case "work": return Color(hex: 0xCFC5B6)
        case "event": return Theme.coffee
        case "ours": return Theme.olive
        default: return Color(hex: 0xA59E91)
        }
    }

    /// The hours above the lanes: 6 … 24.
    private var scale: some View {
        GeometryReader { g in
            ForEach([6, 9, 12, 15, 18, 21, 24], id: \.self) { h in
                Text("\(h)").font(.system(size: 10, weight: .semibold)).monospacedDigit().opacity(0.55)
                    .position(x: 64 + (g.size.width - 64) * x(h * 60), y: 7)
            }
        }
        .frame(height: 14)
    }

    private func lane(_ name: String, _ blocks: [DayBlock], off: Bool, known: Bool) -> some View {
        let nowM = Dock.calendar.component(.hour, from: Date()) * 60 + Dock.calendar.component(.minute, from: Date())
        return HStack(spacing: 0) {
            Text(name).font(.system(size: 12.5, weight: .bold)).lineLimit(1).frame(width: 64, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.gray.opacity(0.18))
                    if blocks.isEmpty {
                        Text(!known ? "графік не внесено" : off ? "вихідний" : "вільно весь день")
                            .font(.system(size: 11)).opacity(0.6).frame(maxWidth: .infinity)
                    }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                        laneBlock(b, width: g.size.width)
                    }
                    if isToday, nowM > from {
                        Capsule().fill(Color(hex: 0xE2553F)).frame(width: 2, height: 30).offset(x: g.size.width * x(nowM))
                    }
                }
            }
            .frame(height: 30)
        }
        .padding(.top, 6)
    }

    private func laneBlock(_ b: DayBlock, width: CGFloat) -> some View {
        let x0 = x(Evening.minutes(b.start)), x1 = x(Evening.minutes(b.end))
        return Text(b.kind == "work" ? "робота" : b.label ?? "")
            .font(.system(size: 10.5, weight: .bold)).lineLimit(1).padding(.horizontal, 5)
            .frame(width: max(4, width * (x1 - x0)), height: 30, alignment: .leading)
            .background(tint(b.kind), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(b.kind == "work" ? Theme.ink : Color.white)
            .offset(x: width * x0)
    }

    private var rows: [(String, DayBlock)] {
        let mine = d.blocks.me.map { ($0.kind == "ours" ? "♥" : me, $0) }
        let hers = d.blocks.partner.filter { $0.kind != "ours" }.map { (partner, $0) }
        return (mine + hers).sorted { Evening.minutes($0.1.start) < Evening.minutes($1.1.start) }
    }

    /// The same in words: «09:00–18:00 Віктор · робота».
    private var plan: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty { Text("Нічого не заплановано — день вільний.").font(.system(size: 13.5)).opacity(0.85) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 8) {
                    Circle().fill(tint(r.1.kind)).frame(width: 9, height: 9)
                    Text("\(r.1.start)–\(r.1.end)").font(.system(size: 13, weight: .bold)).monospacedDigit()
                    Text("\(r.0) · \(r.1.kind == "work" ? "робота" : r.1.label ?? "справа")").font(.system(size: 13.5)).opacity(0.85).lineLimit(1)
                }
            }
        }
    }
}

/// Поїздки — a page of the calendar group (they used to hang under «Вечір»).
struct TripsPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageTitle(plain: "Наші", italic: "поїздки", sub: "Чернетку заповнюєте разом, поступово: куди, коли, що взяти.")
                TripsBlock()
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 130)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }
}

/// Where we stopped in the film — a stopwatch both of us see — and «На ноутбук».
struct PlayRow: View {
    @EnvironmentObject var store: Store
    @Binding var item: WatchItem
    @State private var busy = false
    @State private var message: String?

    static func hms(_ s: Int) -> String {
        let h = s / 3600, m = s % 3600 / 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s % 60) : String(format: "%d:%02d", m, s % 60)
    }

    var body: some View {
        let p = item.play ?? PlayState(position: 0, since: nil, runtime: nil)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.playing ? "ДИВИМОСЬ ЗАРАЗ" : p.position > 0 ? "ЗУПИНИЛИСЬ НА" : item.mediaType == "tv" ? "СЕРІЯ" : "ФІЛЬМ")
                        .font(.system(size: 10.5, weight: .bold)).tracking(1).opacity(0.65)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(PlayRow.hms(p.seconds(at: ctx.date))).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                    }
                    if let r = p.runtime { Text(length(r)).font(.system(size: 11.5)).opacity(0.6) }
                }
                Spacer(minLength: 4)
                Button { act(p.playing ? "pause" : "start", position: nil) } label: {
                    Label(p.playing ? "Пауза" : p.position > 0 ? "Далі" : "Старт", systemImage: p.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold)).padding(.horizontal, 13).frame(height: 40)
                        .background(Theme.cream, in: Capsule()).foregroundStyle(Theme.ink)
                }
                Button { laptop() } label: {
                    Label("На ноутбук", systemImage: "laptopcomputer")
                        .font(.system(size: 13, weight: .bold)).padding(.horizontal, 13).frame(height: 40)
                        .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                }
            }
            .buttonStyle(.plain).disabled(busy)
            .padding(12)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .foregroundStyle(Theme.cream)
            if p.playing || p.position > 0 {
                HStack(spacing: 6) {
                    seek("−10 хв", -600, p)
                    seek("−1 хв", -60, p)
                    seek("+1 хв", 60, p)
                    seek("+10 хв", 600, p)
                    Spacer(minLength: 0)
                    Button("Додивились") { act("done", position: nil) }
                        .font(.system(size: 12.5, weight: .bold)).padding(.horizontal, 12).frame(height: 32)
                        .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                }
                .buttonStyle(.plain).disabled(busy)
            }
            if let message { Text(message).font(.system(size: 12.5)).foregroundStyle(Theme.muted) }
        }
    }

    private func length(_ r: Int) -> String {
        r >= 60 ? "з \(r / 60) год \(r % 60) хв" : "з \(r) хв"
    }

    private func seek(_ title: String, _ delta: Int, _ p: PlayState) -> some View {
        Button(title) { act("seek", position: max(0, p.seconds() + delta)) }
            .font(.system(size: 12.5, weight: .semibold)).padding(.horizontal, 10).frame(height: 32)
            .background(Theme.ink.opacity(0.07), in: Capsule()).foregroundStyle(Theme.ink)
    }

    private func act(_ action: String, position: Int?) {
        Task {
            busy = true
            defer { busy = false }
            guard let r = try? await API.current().play(item.id, action, position: position) else { message = "Не вдалося — спробуй ще раз"; return }
            item.play = r.play
            item.status = r.status
            store.upsert(item)
            message = action == "done" ? "Позначено. Партнер отримає прохання оцінити." : nil
            Haptic.hit(.medium)
        }
    }

    private func laptop() {
        Task {
            busy = true
            defer { busy = false }
            do {
                let r = try await API.current().remoteOpen(item.id)
                if let p = r.play {
                    item.play = p
                    if item.status == .want { item.status = .watching }
                    store.upsert(item)
                }
                message = r.online ? "Відкриваю на ноутбуці" : "Надіслано — запусти програму на ноутбуці"
                Haptic.ok()
            } catch {
                message = "Спершу підключи ноутбук: Налаштування → Системні → Ноутбук"
            }
        }
    }
}

/// A record that slides out from behind the cover and spins while the song plays.
struct VinylDisc: View {
    let spinning: Bool
    @State private var angle = 0.0

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0x111111))
            Circle().strokeBorder(Color.white.opacity(0.09), lineWidth: 1).padding(5)
            Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1).padding(11)
            Circle().strokeBorder(Color.white.opacity(0.05), lineWidth: 1).padding(17)
            Circle().trim(from: 0.04, to: 0.16).stroke(Color.white.opacity(0.16), lineWidth: 3).padding(9)
            Circle().fill(Color(hex: 0xD9C8A9)).scaleEffect(0.3)
            Circle().fill(Color(hex: 0x111111)).scaleEffect(0.06)
        }
        .rotationEffect(.degrees(angle))
        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        .onAppear { if spinning { start() } }
        .onChange(of: spinning) { _, on in
            if on { start() } else { withAnimation(.easeOut(duration: 0.6)) { angle = 0 } }
        }
    }

    private func start() {
        angle = 0
        withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { angle = 360 }
    }
}

/// How far into the song: the bar moves every second from what Spotify last told us.
struct SpotProgress: View {
    let track: SpotTrack
    let at: Date
    let compact: Bool

    static func mmss(_ ms: Double) -> String {
        let s = Int(max(0, ms) / 1000)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let dur = max(1, Double(track.duration ?? 1))
            let ms = min(dur, Double(track.progress ?? 0) + (track.playing ? ctx.date.timeIntervalSince(at) * 1000 : 0))
            VStack(spacing: 3) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white).frame(width: g.size.width * CGFloat(ms / dur))
                    }
                }
                .frame(height: 3)
                if !compact {
                    HStack {
                        Text(SpotProgress.mmss(ms))
                        Spacer()
                        Text(SpotProgress.mmss(dur))
                    }
                    .font(.system(size: 10)).monospacedDigit().opacity(0.7)
                }
            }
            .padding(.top, 8)
        }
    }
}

/// A row that slides left into the archive («В архів» shows behind it).
struct SwipeToArchive<Content: View>: View {
    var onArchive: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var dx: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 6) {
                Image(systemName: "archivebox.fill")
                Text("В архів")
            }
            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white).padding(.trailing, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .background(Theme.coffee, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(dx < 0 ? 1 : 0)
            content().offset(x: dx)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 18)
            .onChanged { v in
                guard dx != 0 || abs(v.translation.width) > abs(v.translation.height) * 1.4 else { return }
                dx = min(0, v.translation.width)
            }
            .onEnded { _ in
                if dx < -110 {
                    Haptic.hit(.medium)
                    withAnimation(.easeIn(duration: 0.2)) { dx = -600 }
                    onArchive()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dx = 0 }
                }
            })
    }
}
