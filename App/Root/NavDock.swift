import SwiftUI

/// What the «Ми» menu opens.
enum MeAction: String, Identifiable {
    case notifications, code, settings
    var id: String { rawValue }
}

/// Bottom bar from Viktor's reference: three «pills» at rest — «+», the section you are in (with the nearest
/// event) and the two of you. A tapped pill grows into a panel: the section pill into a week strip, the nearest
/// event and tabs with the elastic olive capsule; the people pill into a menu (wishes, notifications, code, settings).
struct NavDock: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Binding var tab: Tab
    @Binding var calendarDay: Date
    @Binding var wishOwner: String
    var onAdd: () -> Void
    var onMenu: (MeAction) -> Void

    enum Panel { case sections, me }
    @State private var open: Panel?

    static let sections: [Tab] = [.home, .calendar, .together]
    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.74)

    var body: some View {
        ZStack(alignment: .bottom) {
            if open != nil {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .bottom) {
                    pills
                        .opacity(open == nil ? 1 : 0)
                        .scaleEffect(open == nil ? 1 : 0.92, anchor: .bottom)
                        .allowsHitTesting(open == nil)
                    if open == .sections {
                        SectionsPanel(tab: tab, events: store.events, me: state.me, partner: state.partner,
                                      pickTab: pick, pickDay: { d in calendarDay = d; pick(.calendar) })
                            .transition(.scale(scale: 0.55, anchor: .bottom).combined(with: .opacity))
                    }
                    if open == .me {
                        MeMenu(me: state.me, partner: state.partner, wishes: store.wishes, unread: store.unread) { choice in
                            close()
                            switch choice {
                            case .mine: wishOwner = state.me?.id ?? ""; tab = .us
                            case .partner: wishOwner = state.partner?.id ?? ""; tab = .us
                            case .action(let a): onMenu(a)
                            }
                        }
                        .transition(.scale(scale: 0.55, anchor: .bottomTrailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
        }
        .sensoryFeedback(.selection, trigger: tab)
        .sensoryFeedback(.impact(weight: .light), trigger: open)
    }

    // MARK: pills at rest

    private var pills: some View {
        HStack(spacing: 8) {
            Button(action: onAdd) {
                Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                    .frame(width: 60, height: 60)
                    .background(Theme.coffee, in: Circle())
                    .foregroundStyle(Theme.cream)
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
            }
            .accessibilityLabel("Додати")

            Button { withAnimation(spring) { open = .sections } } label: { sectionPill }
                .buttonStyle(PressStyle())
                .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded(swipe))
                .accessibilityLabel("\(sectionTitle). Розділи і тиждень")

            Button { withAnimation(spring) { open = .me } } label: { mePill }
                .buttonStyle(PressStyle())
                .accessibilityLabel(store.unread > 0 ? "Ми. Непрочитаних сповіщень: \(store.unread)" : "Ми")
        }
    }

    private var sectionTitle: String {
        switch tab {
        case .us: return wishOwner == state.me?.id ? "Мої бажання" : "Бажання \(state.partner?.name ?? "")"
        default: return tab.title
        }
    }

    private var sectionPill: some View {
        HStack(spacing: 10) {
            Image(systemName: tab == .us ? "gift.fill" : tab.icon)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Theme.olive, in: Circle())
                .foregroundStyle(Theme.cream)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(sectionTitle).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(Dock.nextLine(Dock.nextEvent(store.events))).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8).padding(.trailing, 14)
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .background(Theme.paper, in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        .foregroundStyle(Theme.ink)
    }

    private var mePill: some View {
        HStack(spacing: -16) {
            Avatar(member: state.me, size: 44)
            Avatar(member: state.partner, size: 44).overlay(Circle().stroke(Theme.paper, lineWidth: 3))
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .background(Theme.paper, in: Capsule())
        .overlay(alignment: .topTrailing) {
            if store.unread > 0 {
                Text("\(min(store.unread, 99))")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                    .background(Color(hex: 0xC0453A), in: Capsule())
                    .overlay(Capsule().stroke(Theme.paper, lineWidth: 2))
                    .offset(x: -4, y: 4)
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
    }

    // MARK: actions

    private func pick(_ t: Tab) {
        tab = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { close() }
    }

    private func close() { withAnimation(spring) { open = nil } }

    /// Swipe the section pill: left → next section, right → previous.
    private func swipe(_ v: DragGesture.Value) {
        guard abs(v.translation.width) > 40, abs(v.translation.width) > abs(v.translation.height) else { return }
        let i = Self.sections.firstIndex(of: tab) ?? 0
        let j = v.translation.width < 0 ? min(i + 1, Self.sections.count - 1) : max(i - 1, 0)
        withAnimation(.snappy) { tab = Self.sections[j] }
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - sections panel

private struct SectionsPanel: View {
    let tab: Tab
    let events: [Event]
    let me: Member?
    let partner: Member?
    var pickTab: (Tab) -> Void
    var pickDay: (Date) -> Void

    var body: some View {
        VStack(spacing: 0) {
            week.padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 6)
            if let next = Dock.nextEvent(events) {
                Button { pickDay(next.startsAt) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: next.isLiveInvitation ? "envelope.open.fill" : "calendar")
                            .font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Dock.nextLine(next).components(separatedBy: " · ").first ?? "")
                                .font(.system(size: 12)).opacity(0.75)
                            Text(next.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Theme.olive, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .foregroundStyle(Theme.cream)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).padding(.bottom, 8)
            }
            Divider().overlay(Theme.line)
            ElasticTabs(tab: tab, pick: pickTab).padding(8)
        }
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .foregroundStyle(Theme.ink)
    }

    private var week: some View {
        let today = Date()
        let cal = Dock.calendar
        return HStack(spacing: 4) {
            ForEach(Dock.week(containing: today), id: \.self) { d in
                let list = Dock.events(events, on: d)
                Button { pickDay(d) } label: {
                    VStack(spacing: 3) {
                        Text(d.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "uk_UA"))))
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Text("\(cal.component(.day, from: d))")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(list.contains { $0.isOurs } ? Theme.coffee : Theme.ink)
                        HStack(spacing: 3) {
                            ForEach(Array(list.prefix(3)), id: \.id) { e in
                                Circle().fill(color(e)).frame(width: 6, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(cal.isDate(d, inSameDayAs: today) ? Theme.sage.opacity(0.7) : .clear,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func color(_ e: Event) -> Color {
        guard let owner = e.ownerId else { return Theme.olive }
        return Theme.whose(owner == me?.id ? me?.role : partner?.role)
    }
}

/// The three sections with the olive capsule that stretches between them and springs back.
private struct ElasticTabs: View {
    let tab: Tab
    var pick: (Tab) -> Void
    @State private var lead: CGFloat = 0
    @State private var trail: CGFloat = 1
    @State private var shown: Tab?

    private func slot(_ t: Tab) -> CGFloat? { NavDock.sections.firstIndex(of: t).map { CGFloat($0) } }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width / CGFloat(NavDock.sections.count)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.olive)
                    .frame(width: max(w * (trail - lead), 0), height: 52)
                    .offset(x: w * lead)
                    .opacity(slot(shown ?? tab) == nil ? 0 : 1)
                HStack(spacing: 0) {
                    ForEach(NavDock.sections, id: \.self) { t in
                        let on = (shown ?? tab) == t
                        Button {
                            move(to: t)
                            pick(t)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: t.icon).font(.system(size: 17, weight: .semibold))
                                Text(t.title).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(width: w, height: 52)
                            .contentShape(Rectangle())
                            .foregroundStyle(on ? Theme.cream : Color(hex: 0x8E9280))
                            .animation(.easeInOut(duration: 0.25), value: shown)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(height: 52)
        .onAppear { if let s = slot(tab) { lead = s; trail = s + 1 } }
    }

    private func move(to t: Tab) {
        guard let s = slot(t) else { return }
        let goingRight = s > lead
        let front = Animation.spring(response: 0.28, dampingFraction: 0.62)
        let back = Animation.spring(response: 0.5, dampingFraction: 0.6)
        if slot(shown ?? tab) == nil { lead = s; trail = s + 1 }
        withAnimation(goingRight ? back : front) { lead = s }
        withAnimation(goingRight ? front : back) { trail = s + 1 }
        shown = t
    }
}

// MARK: - «Ми» menu

private enum MeChoice { case mine, partner, action(MeAction) }

private struct MeMenu: View {
    let me: Member?
    let partner: Member?
    let wishes: [Wish]
    let unread: Int
    var choose: (MeChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Avatar(member: me, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(me?.name ?? "").font(.system(size: 17, weight: .semibold))
                    Text("з \(partner?.name ?? "")").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 10)
            row("gift.fill", "Мої бажання", count(me)) { choose(.mine) }
            row("heart", "Бажання \(partner?.name ?? "")", count(partner)) { choose(.partner) }
            row("bell", "Сповіщення", unread > 0 ? "\(unread)" : nil, red: unread > 0) { choose(.action(.notifications)) }
            Divider().overlay(Theme.line).padding(.horizontal, 12).padding(.vertical, 4)
            row("key", "Код пари", nil) { choose(.action(.code)) }
            row("gearshape", "Налаштування", nil) { choose(.action(.settings)) }
        }
        .padding(10)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .foregroundStyle(Theme.ink)
    }

    private func count(_ m: Member?) -> String? {
        guard let m else { return nil }
        let n = wishes.filter { $0.ownerId == m.id && $0.status != "bought" }.count
        return n > 0 ? "\(n)" : nil
    }

    private func row(_ icon: String, _ title: String, _ trailing: String?, red: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(Theme.olive).frame(width: 26)
                Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13, weight: red ? .bold : .medium))
                        .foregroundStyle(red ? .white : Theme.muted)
                        .padding(.horizontal, red ? 8 : 0).padding(.vertical, red ? 2 : 0)
                        .background(red ? Color(hex: 0xC0453A) : .clear, in: Capsule())
                }
            }
            .padding(.horizontal, 12).frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - sheets the menu opens

struct NotificationsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.notifications.isEmpty {
                    Text("Поки тихо. Тут з'являться запрошення, нові бажання й знижки.").foregroundStyle(Theme.muted)
                }
                ForEach(store.notifications) { n in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.title).font(.system(size: 15, weight: n.read ? .regular : .semibold))
                        if let b = n.body, !b.isEmpty { Text(b).font(.system(size: 14)).foregroundStyle(Theme.muted) }
                        Text(n.createdAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "uk_UA"))))
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    .listRowBackground(n.read ? Theme.paper : Theme.sage.opacity(0.45))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle("Сповіщення")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .refreshable { await store.refreshNotifications() }
        }
        .tint(Theme.olive)
        .task { await store.markNotificationsRead() }
    }
}

struct CoupleCodeView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Код пари").font(.serif(30, .bold)).padding(.top, 28)
            Text("Для вас обох і для будь-якого пристрою: «У мене є код» → обрати себе.")
                .font(.system(size: 15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if let code {
                Text("\(code.prefix(3)) \(code.dropFirst(3))")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 8)
                ShareLink(item: "Код пари в DaVincit: \(code)") {
                    Label("Надіслати код", systemImage: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                }
            } else if let error {
                Text(error).foregroundStyle(Theme.coffee)
            } else {
                ProgressView().padding()
            }
            Spacer()
            Button("Готово") { dismiss() }.font(.system(size: 16, weight: .semibold)).padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .tint(Theme.olive)
        .task {
            do { code = try await state.api.coupleCode() } catch { self.error = error.localizedDescription }
        }
    }
}
