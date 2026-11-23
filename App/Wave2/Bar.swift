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

/// Bottom bar from Viktor's reference video, mirrored: «+» on the left, the row on the right.
/// A tapped circle grows into a pill and pushes the others; tapping the open pill unfolds its sub-menu in place
/// (the other circles blur away, the section circle stays as «back»).
struct WaveBar: View {
    @Binding var page: Page
    let sections: [BarSection]
    var onAdd: () -> Void
    var onSheet: (String) -> Void

    @State private var active = "home"
    @State private var sub = false
    @State private var lastPick: [String: Page] = [:]
    private let spring = Animation.spring(response: 0.5, dampingFraction: 0.7)

    var body: some View {
        HStack(alignment: .bottom) {
            Button(action: onAdd) {
                Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(Theme.coffee, in: Circle())
                    .foregroundStyle(Theme.cream)
                    .shadow(color: Theme.coffee.opacity(0.35), radius: 14, y: 10)
            }
            .opacity(sub ? 0 : 1).blur(radius: sub ? 8 : 0).scaleEffect(sub ? 0.6 : 1)
            .allowsHitTesting(!sub)
            .accessibilityLabel("Додати")
            Spacer(minLength: 8)
            row
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .onAppear { active = section(of: page) }
        .onChange(of: page) { _, p in if !sub { withAnimation(spring) { active = section(of: p) } } }
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.impact(weight: .light), trigger: sub)
    }

    private var row: some View {
        HStack(spacing: 6) {
            if sub, let s = sections.first(where: { $0.id == active }) {
                Button { withAnimation(spring) { sub = false } } label: { circle(s, back: true) }
                    .transition(.blurReplace)
                ForEach(Array(s.subs.enumerated()), id: \.element.id) { i, x in
                    Button { pick(x, in: s) } label: { subItem(x) }
                        .buttonStyle(.plain)
                        .transition(.blurReplace.animation(spring.delay(0.05 * Double(i))))
                }
            } else {
                ForEach(sections.reversed()) { s in
                    Button { tap(s) } label: { item(s) }
                        .buttonStyle(.plain)
                        .transition(.blurReplace)
                }
            }
        }
        .padding(7)
        .background(Theme.paper, in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 16, y: 10)
        .animation(spring, value: active)
        .animation(spring, value: sub)
    }

    private func item(_ s: BarSection) -> some View {
        let open = s.id == active
        return HStack(spacing: 0) {
            if open {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(s.label).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(s.note).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .frame(maxWidth: 112, alignment: .trailing)
                .padding(.leading, 12)
                .transition(.blurReplace)
            }
            icon(s, open: open)
        }
        .frame(height: 44)
        .background(Theme.tan, in: Capsule())
        .foregroundStyle(Theme.ink)
        .contentShape(Capsule())
        .accessibilityLabel(s.label)
    }

    private func circle(_ s: BarSection, back: Bool) -> some View {
        icon(s, open: false)
            .frame(width: 44, height: 44)
            .background(Theme.olive, in: Circle())
            .foregroundStyle(Theme.cream)
            .accessibilityLabel("Назад")
    }

    @ViewBuilder private func icon(_ s: BarSection, open: Bool) -> some View {
        if let a = s.avatar {
            Text(a).font(.serif(15, .bold)).frame(width: 34, height: 34)
                .background(Theme.coffee, in: Circle()).foregroundStyle(Theme.cream)
                .frame(width: 44, height: 44)
        } else if let i = s.icon {
            Image(systemName: i).font(.system(size: 19, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(open ? Theme.olive : Theme.ink)
        }
    }

    private func subItem(_ x: BarSub) -> some View {
        let on = x.page != nil && x.page == page
        return VStack(spacing: 2) {
            Image(systemName: x.icon).font(.system(size: 20, weight: .semibold)).scaleEffect(on ? 1.08 : 1)
            Text(x.label).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(width: 62, height: 52)
        .background(on ? Theme.tan.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundStyle(on ? Theme.olive : Theme.muted)
    }

    private func tap(_ s: BarSection) {
        if s.id == active {
            if !s.subs.isEmpty { withAnimation(spring) { sub = true } }
            return
        }
        withAnimation(spring) { active = s.id }
        page = lastPick[s.id] ?? s.start
    }

    private func pick(_ x: BarSub, in s: BarSection) {
        guard let p = x.page else { onSheet(x.id); return }
        lastPick[s.id] = p
        page = p
    }

    private func section(of p: Page) -> String {
        sections.first { $0.start == p || $0.subs.contains { $0.page == p } }?.id ?? "home"
    }
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
