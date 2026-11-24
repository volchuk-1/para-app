import SwiftUI

/// Every screen the bar can open.
enum Page: String, Hashable {
    case home, archive, week, month, invites, watch, books, wishes, me, finance, games
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
    @State private var width: CGFloat = 360
    @State private var foldTicket = 0
    private let spring = Animation.spring(response: 0.48, dampingFraction: 0.72)

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
        .background(GeometryReader { g in
            Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w }
        })
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .animation(spring, value: open)
        .animation(spring, value: active)
        .onAppear { active = section(of: page) }
        .onChange(of: page) { _, p in if !open { withAnimation(spring) { active = section(of: p) } } }
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.impact(weight: .light), trigger: open)
    }

    private var current: BarSection? { sections.first { $0.id == active } }
    private var small: CGFloat { open ? 36 : 44 }

    /// Subs share what is left of the row: 40…60 pt each.
    private var subWidth: CGFloat {
        guard open, let s = current, !s.subs.isEmpty else { return 0 }
        let others = CGFloat(sections.count - 1), n = CGFloat(s.subs.count)
        let room = width - 14 - 44 - others * small - (others + n) * 4
        return max(40, min(60, (room / n).rounded(.down)))
    }

    private var row: some View {
        HStack(spacing: 4) {
            ForEach(sections.reversed()) { s in
                if open, s.id == active {
                    ForEach(Array(s.subs.enumerated()), id: \.element.id) { i, x in
                        Button { pick(x, in: s) } label: { subItem(x) }
                            .buttonStyle(.plain)
                            .transition(AnyTransition.slideOut.animation(spring.delay(0.045 * Double(s.subs.count - 1 - i))))
                    }
                }
                Button { tap(s) } label: { item(s) }
                    .buttonStyle(.plain)
            }
        }
        .padding(7)
        .background(Theme.paper, in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 16, y: 10)
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
            Image(systemName: x.icon).font(.system(size: 18, weight: .semibold)).scaleEffect(on ? 1.08 : 1)
            Text(x.label).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(width: subWidth, height: 46)
        .background(on ? Theme.olive.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .foregroundStyle(Theme.olive)
        .contentShape(Rectangle())
    }

    private func tap(_ s: BarSection) {
        if s.id == active {
            if open { fold() } else if !s.subs.isEmpty { unfold() }
            return
        }
        withAnimation(spring) { active = s.id }
        page = lastPick[s.id] ?? s.start
        if s.subs.isEmpty { fold() } else { unfold() }
    }

    private func pick(_ x: BarSub, in s: BarSection) {
        fold(after: 0.65)
        guard let p = x.page else { onSheet(x.id); return }
        lastPick[s.id] = p
        page = p
    }

    private func unfold() {
        withAnimation(spring) { open = true }
        fold(after: 6)
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
        sections.first { $0.start == p || $0.subs.contains { $0.page == p } }?.id ?? "home"
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
