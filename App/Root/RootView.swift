import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if state.me != nil && state.isPaired {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .task { await state.refresh() }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await state.refresh() } }
        }
    }
}

enum Tab: String, CaseIterable { case home, calendar, together, us
    var title: String {
        switch self { case .home: "Головна"; case .calendar: "Календар"; case .together: "Разом"; case .us: "Ми" }
    }
    var icon: String {
        switch self { case .home: "house.fill"; case .calendar: "calendar"; case .together: "popcorn.fill"; case .us: "heart.fill" }
    }
}

/// What the «+» sheet and other places can open.
enum Route: Identifiable, Hashable {
    case invite, event, watchSearch, wish, share(URL)
    var id: String {
        switch self {
        case .invite: "invite"; case .event: "event"; case .watchSearch: "watch"; case .wish: "wish"
        case .share(let u): "share-\(u.absoluteString)"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var store = Store()
    @State private var tab: Tab = .home
    @State private var showAdd = false
    @State private var route: Route?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home: HomeView(tab: $tab, route: $route)
                case .calendar: CalendarView(route: $route)
                case .together: TogetherView(route: $route)
                case .us: UsView(route: $route)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(tab: $tab) { showAdd = true }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
        .environmentObject(store)
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showAdd) {
            AddSheet { r in showAdd = false; route = r }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $route) { r in
            switch r {
            case .invite: InviteEditor(existing: nil)
            case .event: EventEditor(existing: nil)
            case .watchSearch: WatchSearchView(sourceUrl: nil)
            case .wish: WishEditor()
            case .share(let u): ShareFlowView(url: u) { route = nil; Task { await store.refreshAll() } }
            }
        }
        .task {
            Reminders.askPermission()
            await store.refreshAll()
        }
        .onChange(of: phase) { _, p in if p == .active { Task { await store.refreshAll() } } }
        .onChange(of: state.pendingShare) { _, u in
            if let u { route = .share(u); state.pendingShare = nil }
        }
        .environmentObject(store)
    }
}

/// Floating bar: the active tab expands with its name, «+» is a brown circle.
/// Floating bar with an elastic olive capsule: when you switch tabs the front edge jumps ahead,
/// the back edge catches up a moment later, so the capsule stretches and springs back.
struct TabBar: View {
    @Binding var tab: Tab
    var onAdd: () -> Void
    @State private var lead: CGFloat = 0
    @State private var trail: CGFloat = 1

    static let slots: [Tab?] = [.home, .calendar, nil, .together, .us]
    static func slot(_ t: Tab) -> CGFloat { CGFloat(slots.firstIndex(of: t) ?? 0) }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width / CGFloat(Self.slots.count)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.olive)
                    .frame(width: max(w * (trail - lead) - 8, 0), height: 48)
                    .offset(x: w * lead + 4)
                HStack(spacing: 0) {
                    ForEach(0..<Self.slots.count, id: \.self) { i in
                        if let t = Self.slots[i] { item(t).frame(width: w) } else { plus.frame(width: w) }
                    }
                }
            }
        }
        .frame(height: 48)
        .padding(8)
        .background(Theme.paper, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .onAppear { lead = Self.slot(tab); trail = lead + 1 }
        .onChange(of: tab) { _, t in move(to: Self.slot(t)) }
        .sensoryFeedback(.selection, trigger: tab)
    }

    private func move(to s: CGFloat) {
        let goingRight = s > lead
        let front = Animation.spring(response: 0.28, dampingFraction: 0.62)
        let back = Animation.spring(response: 0.5, dampingFraction: 0.6)
        withAnimation(goingRight ? back : front) { lead = s }
        withAnimation(goingRight ? front : back) { trail = s + 1 }
    }

    private var plus: some View {
        Button(action: onAdd) {
            Image(systemName: "plus").font(.system(size: 20, weight: .bold))
                .frame(width: 48, height: 48)
                .background(Theme.coffee, in: Circle())
                .foregroundStyle(Theme.cream)
        }
        .accessibilityLabel("Додати")
    }

    private func item(_ t: Tab) -> some View {
        Button { tab = t } label: {
            Image(systemName: t.icon)
                .font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
                .foregroundStyle(tab == t ? Theme.cream : Color(hex: 0x8E9280))
                .animation(.easeInOut(duration: 0.25), value: tab)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(tab == t ? .isSelected : [])
    }
}

/// «+» sheet: invitation highlighted, then the rest.
struct AddSheet: View {
    var pick: (Route) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Додати").font(.serif(30, .bold)).padding(.top, 22)
            Text("З'явиться у вас обох.").font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.bottom, 8)
            Button { pick(.invite) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.open.fill").font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Запрошення на побачення").font(.system(size: 16, weight: .semibold))
                        Text("Місце, час, що вдягнути").font(.system(size: 13)).opacity(0.8)
                    }
                    Spacer()
                    Text("Створити").font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.cream, in: Capsule()).foregroundStyle(Theme.olive)
                }
                .padding(16)
                .background(Theme.olive, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .foregroundStyle(Theme.cream)
            }
            row("calendar.badge.plus", "Подія в календар") { pick(.event) }
            row("popcorn", "Фільм / серіал / аніме") { pick(.watchSearch) }
            row("gift", "Бажання за посиланням") { pick(.wish) }
            Spacer()
        }
        .padding(.horizontal, 20)
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }

    private func row(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.muted).frame(width: 26)
                Text(title).font(.system(size: 17, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 18).frame(height: 60)
            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .foregroundStyle(Theme.ink)
    }
}
