import SwiftUI

/// Every screen the bar can open.
enum Page: String, Hashable {
    case home, archive, week, month, invites, watch, books, wishes, me, finance, games, money, evening, cinema, cal, pomo, stats, trips
}

/// One group of the bar: a circle at rest, a pill when it is where you are, a sub-menu on the second tap.
struct BarSection: Identifiable, Equatable {
    let id: String
    let icon: String?
    let avatar: String?
    let label: String
    let note: String
    let start: Page
    let subs: [BarSub]
}

struct BarSub: Identifiable, Equatable {
    let id: String
    let icon: String
    let label: String
    let page: Page?   // nil = opens a sheet (settings, code)
}

/// Bottom bar from Viktor's reference video, mirrored: «+» on the left, the circles on the right.
/// Tapping a circle turns it olive (dark icon) and slides its sub-menu out to its LEFT, pushing the row;
/// the other circles stay (a little smaller) and «+» steps aside. The row folds back after a pick or a pause.
struct WaveBar: View {
    @Binding var page: Page
    let sections: [BarSection]
    var onAdd: () -> Void
    var onSheet: (String) -> Void

    @State private var active = "home"
    @State private var open = false
    @State private var lastPick: [String: Page] = [:]
    /// Fixed by the screen, never measured from the bar itself (that fed back and blew the row up).
    private var width: CGFloat { UIScreen.main.bounds.width - 28 }
    @State private var foldTicket = 0
    @State private var extrasFor: String?
    @State private var extraHot: Page?
    @State private var extraFrames: [Page: CGRect] = [:]
    @State private var holdTask: Task<Void, Never>?
    @State private var holdStart: Date?
    @State private var itemFrames: [String: CGRect] = [:]
    private let spring = Animation.spring(response: 0.48, dampingFraction: 0.72)
    /// Pages that do not fit the row: a long press on the circle shows them above it.
    private let extras: [String: [(Page, String, String)]] = [
        "together": [(.wishes, "gift.fill", "Бажання"), (.finance, "piggy", "Банки"), (.archive, "photo.on.rectangle", "Спогади"), (.games, "gamecontroller.fill", "Ігри")],
        "me": [(.stats, "chart.bar.fill", "Статистика"), (.pomo, "timer", "Помодоро")],
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onAdd) {
                Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(Theme.coffee, in: Circle())
                    .foregroundStyle(Theme.cream)
                    .shadow(color: Theme.coffee.opacity(0.35), radius: 14, y: 10)
            }
            .frame(width: open ? 0 : 52)
            .opacity(open ? 0 : 1).blur(radius: open ? 8 : 0).scaleEffect(open ? 0.4 : 1)
            .allowsHitTesting(!open)
            .accessibilityLabel("Додати")
            Spacer(minLength: 0)
            row
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        // the hidden pages: placed by the pressed circle's position on the screen — the pill's bottom 14 pt above
        // the circle, its right edge 10 pt past the circle's (exactly as the Telegram version does it)
        .overlay {
            GeometryReader { g in
                if let k = extrasFor, let ex = extras[k], let cf = itemFrames[k] {
                    let o = g.frame(in: .global).origin
                    let w = CGFloat(ex.count) * 58 + CGFloat(ex.count - 1) * 8 + 16, h: CGFloat = 74
                    extrasPopup(ex)
                        .position(x: min(cf.maxX + 10, UIScreen.main.bounds.width - 8) - w / 2 - o.x, y: cf.minY - 14 - h / 2 - o.y)
                        .transition(.modifier(active: PopIn(shown: false), identity: PopIn(shown: true)))
                }
            }
            .allowsHitTesting(false)
        }
        .animation(spring, value: open)
        .animation(spring, value: active)
        .onAppear { active = section(of: page) }
        .onChange(of: page) { _, p in if !open { withAnimation(spring) { active = section(of: p) } } }
        .sensoryFeedback(.impact(weight: .medium, intensity: 1), trigger: page)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: open)
    }

    private var current: BarSection? { sections.first { $0.id == active } }
    private var small: CGFloat { open ? 36 : 44 }

    /// Each sub is as wide as its label (at least 38 pt); squeezed evenly when the row would not fit.
    private func labelWidth(_ t: String) -> CGFloat {
        max(38, (t as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .semibold)]).width + 10)
    }
    private var room: CGFloat {
        guard let s = current else { return 0 }
        let others = CGFloat(sections.count - 1), n = CGFloat(s.subs.count)
        return width - 14 - 44 - others * small - (others + n) * 4
    }
    /// Too many subs for their labels (Разом has 7): icons only, the open page keeps its label.
    private var compact: Bool {
        guard let s = current else { return false }
        return s.subs.map { labelWidth($0.label) }.reduce(0, +) > room * 1.25
    }
    private func subWidth(_ x: BarSub) -> CGFloat {
        guard open, let s = current, !s.subs.isEmpty else { return 0 }
        guard compact else {
            let total = s.subs.map { labelWidth($0.label) }.reduce(0, +)
            return (labelWidth(x.label) * min(1, room / max(1, total))).rounded(.down)
        }
        let cur = s.subs.first { $0.page != nil && $0.page == page }
        let curW = cur.map { min(labelWidth($0.label), room * 0.3) } ?? 0
        if x.id == cur?.id { return curW.rounded(.down) }
        return ((room - curW) / CGFloat(max(1, s.subs.count - (cur == nil ? 0 : 1)))).rounded(.down)
    }

    private var row: some View {
        HStack(spacing: 4) {
            ForEach(sections.reversed()) { s in
                if open, s.id == active {
                    // reversed: the first sub ends up right next to its circle (and slides out first)
                    ForEach(Array(s.subs.reversed().enumerated()), id: \.element.id) { i, x in
                        Button { pick(x, in: s) } label: { subItem(x) }
                            .buttonStyle(.plain)
                            .transition(AnyTransition.slideOut.animation(spring.delay(0.045 * Double(s.subs.count - 1 - i))))
                    }
                }
                item(s)
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { itemFrames[s.id] = g.frame(in: .global) }
                            .onChange(of: g.frame(in: .global)) { _, f in itemFrames[s.id] = f }
                    })
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { v in
                            // shown the moment the finger lands on the circle
                            if holdStart == nil && extrasFor == nil, extras[s.id] != nil {
                                holdStart = Date()
                                Haptic.hit(.heavy)
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.62)) { extrasFor = s.id }
                            }
                            if extrasFor != nil { extraHot = extraFrames.first { $0.value.insetBy(dx: -6, dy: -6).contains(v.location) }?.key }
                        }
                        .onEnded { v in
                            holdTask?.cancel(); holdTask = nil
                            let quick = holdStart.map { Date().timeIntervalSince($0) < 0.45 } ?? true
                            holdStart = nil
                            let still = abs(v.translation.width) < 12 && abs(v.translation.height) < 12
                            if extrasFor != nil {
                                if let p = extraHot { Haptic.hit(.medium); page = p; withAnimation(spring) { active = s.id } }
                                withAnimation(.easeOut(duration: 0.18)) { extrasFor = nil }
                                // a plain quick tap: the circle does what it always did
                                if extraHot == nil && quick && still { tap(s) }
                                extraHot = nil
                            } else if abs(v.translation.width) < 12 && abs(v.translation.height) < 12 {
                                tap(s)
                            }
                        })
            }
        }
        .padding(7)
        .background(Theme.paper, in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 16, y: 10)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1), trigger: extraHot)
    }

    /// The same as in the Telegram version: a light pill of round buttons; the one under the finger turns olive and grows.
    private func extrasPopup(_ ex: [(Page, String, String)]) -> some View {
        HStack(spacing: 8) {
            ForEach(ex, id: \.0) { e in
                let hot = extraHot == e.0
                VStack(spacing: 1) {
                    Group { if e.1 == "piggy" { PiggyIcon().frame(width: 24, height: 20) } else { Image(systemName: e.1).font(.system(size: 20, weight: .semibold)) } }
                    Text(e.2).font(.system(size: 9, weight: .bold)).foregroundStyle(hot ? Theme.cream : Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(width: 58, height: 58)
                .background(hot ? Theme.olive : Theme.tan, in: Circle())
                .foregroundStyle(hot ? Theme.cream : Theme.olive)
                .scaleEffect(hot ? 1.14 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: hot)
                .background(GeometryReader { g in Color.clear.onAppear { extraFrames[e.0] = g.frame(in: .global) }.onChange(of: g.frame(in: .global)) { _, f in extraFrames[e.0] = f } })
            }
        }
        .padding(8)
        .background(Theme.paper, in: Capsule())
        .shadow(color: Theme.ink.opacity(0.25), radius: 20, y: 14)
        .fixedSize()
    }

    private func item(_ s: BarSection) -> some View {
        let on = s.id == active
        let size = on ? 44 : small
        return ZStack {
            Circle().fill(on ? Theme.olive : Theme.tan)
            if let a = s.avatar {
                Text(a).font(.serif(15, .bold)).frame(width: 34, height: 34)
                    .background(Theme.coffee, in: Circle()).foregroundStyle(Theme.cream)
                    .scaleEffect(on || !open ? 1 : 0.84)
            } else if let i = s.icon {
                Image(systemName: i).font(.system(size: open && !on ? 17 : 19, weight: .semibold)).foregroundStyle(Theme.ink)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .accessibilityLabel(s.label)
    }

    private func subItem(_ x: BarSub) -> some View {
        let on = x.page != nil && x.page == page
        return VStack(spacing: 2) {
            Group { if x.icon == "piggy" { PiggyIcon().frame(width: 22, height: 18) } else { Image(systemName: x.icon).font(.system(size: 18, weight: .semibold)) } }.scaleEffect(on ? 1.08 : 1)
            if !compact || on { Text(x.label).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75) }
        }
        .frame(width: subWidth(x), height: 46)
        .background(on ? Theme.olive.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .foregroundStyle(Theme.olive)
        .contentShape(Rectangle())
    }

    /// A circle always opens its first page (В / Д → Головна), whatever was open in that group before.
    private func tap(_ s: BarSection) {
        let first = s.subs.first?.page ?? s.start
        if s.id == active, open { fold(); return }
        withAnimation(spring) { active = s.id }
        if page != first { page = first }
        if s.subs.isEmpty { fold() } else { unfold() }
    }

    /// The row stays open after a pick — it closes only by tapping its circle or choosing another group.
    private func pick(_ x: BarSub, in s: BarSection) {
        guard let p = x.page else { onSheet(x.id); return }
        lastPick[s.id] = p
        page = p
    }

    private func unfold() {
        foldTicket += 1
        withAnimation(spring) { open = true }
    }

    /// Folds the row now or after a pause; a newer tap cancels an older pause.
    private func fold(after seconds: Double = 0) {
        foldTicket += 1
        let ticket = foldTicket
        Task { @MainActor in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard ticket == foldTicket, open else { return }
            withAnimation(spring) { open = false; active = section(of: page) }
        }
    }

    private func section(of p: Page) -> String {
        sections.first { $0.start == p || $0.subs.contains { $0.page == p } }?.id
            ?? extras.first { $0.value.contains { $0.0 == p } }?.key
            ?? ([.week, .month].contains(p) ? "calendar" : "me")
    }
}

/// The hidden pages pop up from the bottom-right corner, a little springy — as in the Telegram version.
private struct PopIn: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.7, anchor: .bottomTrailing)
            .offset(y: shown ? 0 : 14)
            .opacity(shown ? 1 : 0)
    }
}

/// Sub-items slide out from behind their circle: from the right, small and blurred.
private struct SlideOut: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 6)
            .scaleEffect(shown ? 1 : 0.45, anchor: .trailing)
            .offset(x: shown ? 0 : 22)
    }
}

extension AnyTransition {
    static var slideOut: AnyTransition { .modifier(active: SlideOut(shown: false), identity: SlideOut(shown: true)) }
}

/// Bell, top right of every screen.
struct BellButton: View {
    let unread: Int
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "bell.fill").font(.system(size: 19))
                .frame(width: 46, height: 46)
                .background(Theme.paper, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .overlay(alignment: .topTrailing) {
                    if unread > 0 {
                        Text("\(min(unread, 99))").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                            .background(Color(hex: 0xC0453A), in: Capsule())
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .foregroundStyle(Theme.ink)
        .accessibilityLabel(unread > 0 ? "Сповіщення: \(unread)" : "Сповіщення")
    }
}


/// A piggy bank (SF Symbols has none): body, ear, snout, legs and a coin slot.
struct PiggyIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var body = Path(ellipseIn: CGRect(x: w * 0.08, y: h * 0.18, width: w * 0.78, height: h * 0.62))
            body.addPath(Path(roundedRect: CGRect(x: w * 0.8, y: h * 0.36, width: w * 0.18, height: h * 0.24), cornerRadius: w * 0.05))
            body.addPath(Path(roundedRect: CGRect(x: w * 0.2, y: h * 0.68, width: w * 0.12, height: h * 0.3), cornerRadius: 1.5))
            body.addPath(Path(roundedRect: CGRect(x: w * 0.58, y: h * 0.68, width: w * 0.12, height: h * 0.3), cornerRadius: 1.5))
            var ear = Path()
            ear.move(to: CGPoint(x: w * 0.56, y: h * 0.24)); ear.addLine(to: CGPoint(x: w * 0.66, y: 0)); ear.addLine(to: CGPoint(x: w * 0.76, y: h * 0.3)); ear.closeSubpath()
            body.addPath(ear)
            ctx.fill(body, with: .foreground)
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.36, y: h * 0.26, width: w * 0.2, height: h * 0.07), cornerRadius: 1), with: .color(Theme.paper))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.66, y: h * 0.38, width: w * 0.06, height: w * 0.06)), with: .color(Theme.paper))
        }
    }
}


/// Strong, immediate taps (the system «selection» tick is too faint for Viktor).
enum Haptic {
    static func hit(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, _ intensity: CGFloat = 1) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.impactOccurred(intensity: intensity)
    }
    static func ok() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
