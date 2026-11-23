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
    @State private var calendarDay = Calendar.current.startOfDay(for: Date())
    @State private var wishOwner = ""
    @State private var menu: MeAction?
    @State private var showAdd = false
    @State private var route: Route?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home: HomeView(tab: $tab, route: $route)
                case .calendar: CalendarView(route: $route, day: $calendarDay)
                case .together: TogetherView(route: $route)
                case .us: UsView(route: $route, who: $wishOwner)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            NavDock(tab: $tab, calendarDay: $calendarDay, wishOwner: $wishOwner,
                    onAdd: { showAdd = true }, onMenu: { menu = $0 })
        }
        .environmentObject(store)
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showAdd) {
            AddSheet { r in showAdd = false; route = r }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $menu) { m in
            switch m {
            case .notifications: NotificationsView()
            case .code: CoupleCodeView().presentationDetents([.medium])
            case .settings: SettingsView()
            }
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
