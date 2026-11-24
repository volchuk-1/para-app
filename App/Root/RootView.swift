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
    @State private var page: Page = .home
    @State private var calendarDay = Calendar.current.startOfDay(for: Date())
    @State private var wishOwner = ""
    @State private var menu: MeAction?
    @State private var showAdd = false
    @State private var route: Route?
    @State private var freeTonight: Int?
    @Environment(\.scenePhase) private var phase

    /// HomeView still talks in old tabs; map them onto pages.
    private var legacyTab: Binding<Tab> {
        Binding(get: {
            switch page { case .week, .month, .invites: return .calendar; case .watch, .books: return .together; case .wishes: return .us; default: return .home }
        }, set: { t in
            switch t { case .home: page = .home; case .calendar: page = .week; case .together: page = .watch; case .us: page = .wishes }
        })
    }

    private var sections: [BarSection] {
        let next = Dock.nextEvent(store.events).map { "\($0.title.prefix(14)) \($0.startsAt.shortTime)" } ?? "вільно"
        let watching = store.watch.first { $0.status == .watching }.map { "\($0.title.prefix(12))\($0.episodeLabel.map { " " + $0 } ?? "")" } ?? "фільми, книжки"
        return [
            BarSection(id: "me", icon: nil, avatar: String(state.me?.name.prefix(1) ?? "Я"), label: state.me?.name ?? "Я", note: "налаштування", start: .me,
                       subs: [BarSub(id: "settings", icon: "gearshape.fill", label: "Налашт.", page: nil), BarSub(id: "finance", icon: "dollarsign.circle.fill", label: "Фінанси", page: .finance),
                              BarSub(id: "games", icon: "gamecontroller.fill", label: "Ігри", page: .games)]),
            BarSection(id: "home", icon: "house.fill", avatar: nil, label: "Головна", note: next, start: .home,
                       subs: [BarSub(id: "home", icon: "house.fill", label: "Головна", page: .home), BarSub(id: "archive", icon: "square.stack.fill", label: "Історія", page: .archive)]),
            BarSection(id: "calendar", icon: "calendar", avatar: nil, label: "Календар", note: freeTonight.map { "\($0) вільн. вечори" } ?? "тиждень", start: .week,
                       subs: [BarSub(id: "week", icon: "list.bullet", label: "Тиждень", page: .week), BarSub(id: "month", icon: "calendar", label: "Місяць", page: .month),
                              BarSub(id: "invites", icon: "envelope.open.fill", label: "Запрош.", page: .invites)]),
            BarSection(id: "together", icon: "heart.fill", avatar: nil, label: "Разом", note: watching, start: .watch,
                       subs: [BarSub(id: "watch", icon: "popcorn.fill", label: "Дивимось", page: .watch), BarSub(id: "books", icon: "books.vertical.fill", label: "Книжки", page: .books),
                              BarSub(id: "wishes", icon: "gift.fill", label: "Бажання", page: .wishes)]),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch page {
                case .home: HomeView(tab: legacyTab, route: $route)
                case .archive: HistoryPage()
                case .week: WeekPage()
                case .month: MonthPage()
                case .invites: InvitesPage()
                case .watch: WatchPage(route: $route)
                case .books: BooksPage()
                case .wishes: UsView(route: $route, who: $wishOwner)
                case .me: MePage(page: $page) { menu = .settings }
                case .finance: FinancePage()
                case .games: ScrollView { VStack(alignment: .leading, spacing: 14) { PageTitle(plain: "Ігри", italic: "для двох"); EmptyCard(text: "Картки й інші ігри переїдуть сюди згодом.") }.padding(.horizontal, 18).padding(.top, 8) }.background(Theme.cream.ignoresSafeArea())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.blurReplace)
            .animation(.easeInOut(duration: 0.25), value: page)

            WaveBar(page: $page, sections: sections, onAdd: { showAdd = true },
                    onSheet: { id in menu = id == "code" ? .code : .settings })
        }
        .overlay(alignment: .topTrailing) {
            BellButton(unread: store.unread) { menu = .notifications }
                .padding(.trailing, 16).padding(.top, 4)
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
            case .invite: InviteBooking(start: .blank)
            case .event: EventEditor(existing: nil)
            case .watchSearch: WatchSearchView(sourceUrl: nil)
            case .wish: WishEditor()
            case .share(let u): ShareFlowView(url: u) { route = nil; Task { await store.refreshAll() } }
            }
        }
        .task {
            Reminders.askPermission()
            await store.refreshAll()
            await countFree()
        }
        .onChange(of: phase) { _, p in if p == .active { Task { await store.refreshAll(); await countFree() } } }
        .onChange(of: state.pendingShare) { _, u in
            if let u { route = .share(u); state.pendingShare = nil }
        }
        .environmentObject(store)
    }

    /// Free evenings left this week — the note on the calendar pill.
    private func countFree() async {
        let mon = Evening.monday(of: Date())
        let sun = Dock.calendar.date(byAdding: .day, value: 6, to: mon) ?? mon
        guard let days = try? await API.current().availability(from: Evening.iso(mon), to: Evening.iso(sun)) else { return }
        freeTonight = days.filter { $0.isFree && $0.date >= Evening.iso(Date()) }.count
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
