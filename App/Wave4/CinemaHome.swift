import SwiftUI

// MARK: - Разом → Дивимось: our own cinema

/// Dark hero with what we watch now, rows by status, advice «бо вам сподобалось», discover and roulette.
struct CinemaHome: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Binding var route: Route?
    @State private var open: WatchItem?
    @State private var advice: FoundList?
    @State private var add: Found?
    @State private var discover = false
    @State private var roulette = false
    @State private var flip: FlipFilm?
    private let bg = Color(hex: 0x1C1A1A), card = Color(hex: 0x272424), accent = Color(hex: 0xF2B640)

    var body: some View {
        let watching = store.watch.filter { $0.status == .watching }
        let hero = watching.first ?? store.watch.first { $0.status == .want }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let h = hero { heroCard(h) } else { emptyHero }
                HStack(spacing: 8) {
                    pill("Підбір", "slider.horizontal.3") { discover = true }
                    pill("Рулетка", "dice.fill") { roulette = true }
                    pill("Знайти", "magnifyingglass") { route = .watchSearch }
                }
                .padding(.horizontal, 18)
                row("⭐ Обране", store.watch.filter { $0.fav == true })
                row("Дивимось зараз", watching.filter { $0.id != hero?.id })
                row("Хочемо", store.watch.filter { $0.status == .want && $0.id != hero?.id })
                if let a = advice, !a.results.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Вам може сподобатись").font(.system(size: 19, weight: .bold)).padding(.horizontal, 18)
                        if let b = a.because, !b.isEmpty {
                            Text("Бо ви високо оцінили \(b.prefix(2).joined(separator: ", "))").font(.system(size: 13)).opacity(0.6).padding(.horizontal, 18)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(a.results.prefix(15)) { f in
                                    Button { add = f } label: { poster(f.posterUrl, f.title, sub: f.year.map(String.init)) }.buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                }
                row("Подивились", store.watch.filter { $0.status == .done })
                row("Кинули", store.watch.filter { $0.status == .dropped })
            }
            .padding(.bottom, 130)
        }
        .ignoresSafeArea(edges: .top)
        .background(bg.ignoresSafeArea())
        .foregroundStyle(Color(hex: 0xF3EEE6))
        .task { advice = try? await API.current().recommend() }
        .fullScreenCover(item: $open) { w in FilmPage(item: w, route: $route) }
        .sheet(item: $add) { f in FoundSheet(found: f) }
        .fullScreenCover(isPresented: $discover) { DiscoverPage() }
        .fullScreenCover(item: $flip) { f in TrailerFlip(film: f, open: { id in open = store.watch.first { $0.id == id } }) }
        .sheet(isPresented: $roulette) { RouletteSheet().presentationDetents([.large]) }
    }

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Наш кінотеатр").font(.serif(34, .bold))
            Text("Додайте фільм через «Знайти» або поділіться відео з TikTok — і він з'явиться тут.").font(.system(size: 14)).opacity(0.7)
        }
        .padding(.horizontal, 18).padding(.top, 90)
    }

    private func heroCard(_ h: WatchItem) -> some View {
        Button { open = h } label: {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: h.backdropUrl ?? h.posterUrl).frame(height: 460).frame(maxWidth: .infinity).clipped()
                LinearGradient(colors: [.black.opacity(0.35), .clear, bg.opacity(0.7), bg], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text(h.status == .watching ? "ДИВИМОСЬ ЗАРАЗ" : "ХОЧЕМО").font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(accent)
                    Text(h.title).font(.system(size: 30, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text([h.kindLabel, h.year.map(String.init), h.episodeLabel, h.rating?.tmdb.map { "★ " + String(format: "%.1f", $0) }].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13)).opacity(0.75)
                    Text(h.status == .watching && h.mediaType == "tv" ? "Відкрити й позначити серію" : "Відкрити").font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 40).background(Color(hex: 0xF3EEE6), in: Capsule()).foregroundStyle(bg).padding(.top, 6)
                }
                .padding(.horizontal, 18).padding(.bottom, 6)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func row(_ title: String, _ items: [WatchItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 19, weight: .bold))
                    Text("\(items.count)").font(.system(size: 14)).opacity(0.5)
                }
                .padding(.horizontal, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items) { w in
                            Button { flip = FlipFilm(title: w.title, poster: w.posterUrl ?? w.backdropUrl, watchId: w.id, tmdbId: w.tmdbId, mediaType: w.mediaType, fav: w.fav == true) } label: {
                                poster(w.posterUrl ?? w.backdropUrl, w.title, sub: w.status == .done ? (w.avg.map { "разом " + String(format: "%.1f", $0) } ?? "оцініть") : (w.status == .watching ? w.episodeLabel : w.year.map(String.init)))
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Відкрити сторінку", systemImage: "arrow.up.right") { open = w } }
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private func poster(_ url: String?, _ title: String, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RemoteImage(url: url).frame(width: 118, height: 172).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(2).frame(width: 118, alignment: .leading).multilineTextAlignment(.leading)
            if let sub { Text(sub).font(.system(size: 11.5)).opacity(0.55) }
        }
    }

    private func pill(_ t: String, _ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Label(t, systemImage: icon).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 42)
                .background(card, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A film from discover / advice: add it to «Хочемо» or start right away.
struct FoundSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let found: Found
    @State private var done = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                RemoteImage(url: found.posterUrl).frame(width: 110, height: 160).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(found.title).font(.system(size: 20, weight: .bold))
                    if let o = found.originalTitle, o != found.title { Text(o).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                    Text([found.isAnime ? "Аніме" : (found.mediaType == "tv" ? "Серіал" : "Фільм"), found.year.map(String.init), found.vote.map { "★ " + String(format: "%.1f", $0) }].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    if let b = found.because { Text("Бо вам сподобалось «\(b)»").font(.system(size: 13)).foregroundStyle(Theme.olive) }
                }
            }
            if found.inList == true || done {
                Text("Вже у вашому списку").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.olive)
            } else {
                Button { Task { await save(start: false) } } label: { Text("Додати в «Хочемо»").frame(maxWidth: .infinity).frame(height: 48) }
                    .background(Theme.ink, in: Capsule()).foregroundStyle(Theme.paper)
                Button { Task { await save(start: true) } } label: { Text("Почати дивитись").frame(maxWidth: .infinity).frame(height: 48) }
                    .background(Theme.tan, in: Capsule()).foregroundStyle(Theme.ink)
            }
            Spacer()
        }
        .font(.system(size: 15, weight: .semibold))
        .padding(20).padding(.top, 8)
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .presentationDetents([.medium])
    }

    private func save(start: Bool) async {
        if await store.run({
            var w = try await API.current().addWatch(found.candidate, sourceUrl: nil)
            if start { w = try await API.current().patchWatch(w.id, .init(status: WatchStatus.watching.rawValue)) }
            store.upsert(w)
        }) { done = true; dismiss() }
    }
}

// MARK: - Підбір: search and filters

struct DiscoverPage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var type = "movie"
    @State private var genres: [Genre] = []
    @State private var genre: Int?
    @State private var from = ""
    @State private var to = ""
    @State private var minRating = 0
    @State private var sort = "popular"
    @State private var query = ""
    @State private var results: [Found] = []
    @State private var page = 1
    @State private var loading = false
    @State private var add: Found?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField("Назва фільму чи серіалу", text: $query).submitLabel(.search).onSubmit { Task { await reload() } }
                        if !query.isEmpty { Button { query = ""; Task { await reload() } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) } }
                    }
                    .padding(.horizontal, 14).frame(height: 46).background(Theme.paper, in: Capsule())
                    if query.isEmpty { filters }
                    if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coffee) }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
                        ForEach(results) { f in
                            Button { add = f } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Color.clear.aspectRatio(2 / 3, contentMode: .fit).overlay { RemoteImage(url: f.posterUrl) }
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            if f.inList == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.olive).background(Circle().fill(.white)).padding(5) }
                                        }
                                    Text(f.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text([f.year.map(String.init), f.vote.map { "★ " + String(format: "%.1f", $0) }].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if loading { ProgressView().tint(Theme.olive).frame(maxWidth: .infinity).padding() }
                    else if query.isEmpty && !results.isEmpty {
                        Button("Показати ще") { Task { page += 1; await load(append: true) } }.frame(maxWidth: .infinity).padding().foregroundStyle(Theme.olive)
                    }
                    if !loading && results.isEmpty { EmptyCard(text: "Нічого не знайшлось. Спробуй інші фільтри.") }
                }
                .padding(.horizontal, 16).padding(.bottom, 40)
            }
            .background(Theme.cream.ignoresSafeArea())
            .foregroundStyle(Theme.ink)
            .navigationTitle("Підбір").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрити") { dismiss() } } }
            .task { await loadGenres(); await reload() }
            .sheet(item: $add, onDismiss: { Task { await reload() } }) { f in FoundSheet(found: f) }
        }
        .tint(Theme.olive)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $type) { Text("Фільми").tag("movie"); Text("Серіали").tag("tv"); Text("Аніме").tag("anime") }
                .pickerStyle(.segmented)
                .onChange(of: type) { _, _ in genre = nil; Task { await loadGenres(); await reload() } }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Menu {
                        Button("Усі жанри") { genre = nil; Task { await reload() } }
                        ForEach(genres) { g in Button(g.name) { genre = g.id; Task { await reload() } } }
                    } label: { chip(genres.first { $0.id == genre }?.name ?? "Жанр", on: genre != nil) }
                    Menu {
                        ForEach([("popular", "Популярні"), ("rating", "Найкращі"), ("new", "Нові")], id: \.0) { s in Button(s.1) { sort = s.0; Task { await reload() } } }
                    } label: { chip(["popular": "Популярні", "rating": "Найкращі", "new": "Нові"][sort] ?? "", on: true) }
                    Menu {
                        ForEach([0, 6, 7, 8], id: \.self) { r in Button(r == 0 ? "Будь-який рейтинг" : "від \(r)") { minRating = r; Task { await reload() } } }
                    } label: { chip(minRating == 0 ? "Рейтинг" : "★ від \(minRating)", on: minRating > 0) }
                    Menu {
                        Button("Будь-які роки") { from = ""; to = ""; Task { await reload() } }
                        ForEach([("2020", ""), ("2010", "2019"), ("2000", "2009"), ("1990", "1999"), ("", "1989")], id: \.0) { r in
                            Button(r.0.isEmpty ? "до 1990" : r.1.isEmpty ? "з \(r.0)" : "\(r.0)–\(r.1)") { from = r.0; to = r.1; Task { await reload() } }
                        }
                    } label: { chip(from.isEmpty && to.isEmpty ? "Роки" : from.isEmpty ? "до \(to)" : to.isEmpty ? "з \(from)" : "\(from)–\(to)", on: !(from.isEmpty && to.isEmpty)) }
                }
            }
        }
    }

    private func chip(_ t: String, on: Bool) -> some View {
        HStack(spacing: 4) { Text(t); Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)) }
            .font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 13).frame(height: 34)
            .background(on ? Theme.ink : Theme.tan.opacity(0.6), in: Capsule()).foregroundStyle(on ? Theme.paper : Theme.ink)
    }

    private func loadGenres() async { genres = (try? await API.current().genres(type)) ?? [] }
    private func reload() async { page = 1; await load(append: false) }

    private func load(append: Bool) async {
        loading = true; defer { loading = false }
        do {
            let list: [Found]
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                list = try await API.current().search(query).map { Found(tmdbId: $0.tmdbId, mediaType: $0.mediaType, title: $0.title, originalTitle: $0.originalTitle, year: $0.year, posterPath: $0.posterPath, posterUrl: $0.posterUrl, isAnime: $0.isAnime) }
            } else {
                list = try await API.current().discover(type: type, genre: genre, from: from.isEmpty ? nil : "\(from)-01-01", to: to.isEmpty ? nil : "\(to)-12-31", minRating: minRating == 0 ? nil : minRating, sort: sort, page: page)
            }
            results = append ? results + list.filter { n in !results.contains { $0.id == n.id } } : list
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Рулетка

/// Random pick: from our list (search, pick some or spin over all), anything found on TMDB, or by filters.
/// A strip of posters glides and slows down under the marker (~4.4 s); the one in the middle grows.
struct RouletteSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    enum Source: String { case list, any, filters }
    struct Slot: Identifiable, Equatable { let id: String; let title: String; let poster: String?; let item: WatchItem?; let found: Found? }
    @State private var source: Source = .list
    @State private var query = ""
    @State private var chosen: Set<String> = []
    @State private var picks: [Found] = []
    @State private var anyQuery = ""
    @State private var anyResults: [Found] = []
    @State private var type = "movie"
    @State private var minRating = 7
    @State private var reel: [Slot] = []
    @State private var offset: CGFloat = 0
    @State private var spinning = false
    @State private var result: Slot?
    @State private var winIndex = 0
    @State private var error: String?
    private let cardW: CGFloat = 104, gap: CGFloat = 12

    private var ours: [WatchItem] {
        let q = query.lowercased()
        return store.watch.filter { $0.status != .done && (q.isEmpty || $0.title.lowercased().contains(q)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("", selection: $source) { Text("Наш список").tag(Source.list); Text("Будь-що").tag(Source.any); Text("За фільтрами").tag(Source.filters) }
                        .pickerStyle(.segmented).disabled(spinning)
                    reelView
                    if let r = result, !spinning {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("СЬОГОДНІ ДИВИМОСЬ").font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(Theme.coffee)
                            Text(r.title).font(.system(size: 22, weight: .bold))
                            HStack(spacing: 8) {
                                Button { Task { await take(r) } } label: { Text("Беремо").frame(maxWidth: .infinity).frame(height: 48) }
                                    .background(Theme.ink, in: Capsule()).foregroundStyle(Theme.paper)
                                Button { Task { await spin() } } label: { Text("Ще раз").frame(maxWidth: .infinity).frame(height: 48) }
                                    .background(Theme.tan, in: Capsule()).foregroundStyle(Theme.ink)
                            }
                            .font(.system(size: 15, weight: .semibold))
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Button { Task { await spin() } } label: { Label("Крутити", systemImage: "dice.fill").frame(maxWidth: .infinity).frame(height: 50) }
                            .font(.system(size: 16, weight: .semibold)).background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream).disabled(spinning)
                    }
                    if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coffee) }
                    switch source {
                    case .list: listBox
                    case .any: anyBox
                    case .filters: filterBox
                    }
                }
                .padding(18)
            }
            .scrollDisabled(spinning)
            .background(Theme.cream.ignoresSafeArea())
            .foregroundStyle(Theme.ink)
            .navigationTitle("Рулетка").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрити") { dismiss() } } }
            .onChange(of: source) { _, _ in result = nil; reel = [] }
            .onAppear { if reel.isEmpty { reel = Array(ours.prefix(7).map(slot)) } }
        }
        .tint(Theme.olive)
    }

    // MARK: the reel

    private var reelView: some View {
        GeometryReader { g in
            let mid = g.size.width / 2
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(hex: 0x1C1A1A))
                HStack(spacing: gap) {
                    ForEach(Array(reel.enumerated()), id: \.offset) { i, s in
                        posterCard(s, winner: !spinning && result != nil && i == winIndex)
                            .visualEffect { content, proxy in
                                // the card under the marker grows, the others shrink and fade
                                let d = abs(proxy.frame(in: .named("reel")).midX - mid)
                                let k = max(0, 1 - d / 260)
                                return content.scaleEffect(0.78 + 0.26 * k).opacity(0.35 + 0.65 * k)
                            }
                    }
                }
                .offset(x: mid - cardW / 2 + offset)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(hex: 0xF2B640), lineWidth: 2)
                    .frame(width: cardW + 14, height: 176)
                    .shadow(color: Color(hex: 0xF2B640).opacity(result != nil && !spinning ? 0.6 : 0), radius: 18)
                    .position(x: mid, y: 100)
                    .allowsHitTesting(false)
                if reel.isEmpty {
                    Text("Натисни «Крутити»").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity)
                }
            }
            .coordinateSpace(.named("reel"))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(height: 200)
    }

    private func posterCard(_ s: Slot, winner: Bool) -> some View {
        Color(hex: 0x333030).frame(width: cardW, height: 156)
            .overlay { RemoteImage(url: s.poster) }
            .overlay(alignment: .bottomLeading) {
                Text(s.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                    .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
            .scaleEffect(winner ? 1.06 : 1)
    }

    // MARK: sources

    private var listBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Пошук у нашому списку", text: $query)
            }
            .padding(.horizontal, 14).frame(height: 44).background(Theme.paper, in: Capsule())
            Text(chosen.isEmpty ? "Тапни, щоб крутити лише серед обраних. Нічого не обрано — крутимо серед усіх (\(ours.count))." : "Крутимо серед обраних: \(chosen.count)")
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            ForEach(ours) { w in
                Button { if chosen.contains(w.id) { chosen.remove(w.id) } else { chosen.insert(w.id) } } label: {
                    row(w.posterUrl ?? w.backdropUrl, w.title, w.kindLabel + (w.status == .watching ? " · дивимось" : ""), on: chosen.contains(w.id))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var anyBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Знайди будь-який фільм чи серіал", text: $anyQuery).submitLabel(.search).onSubmit { Task { await find() } }
            }
            .padding(.horizontal, 14).frame(height: 44).background(Theme.paper, in: Capsule())
            ForEach(anyResults.prefix(8)) { f in
                Button { if !picks.contains(where: { $0.id == f.id }) { picks.append(f) } } label: {
                    row(f.posterUrl, f.title, [f.year.map(String.init), "+ додати"].compactMap { $0 }.joined(separator: " · "), on: picks.contains { $0.id == f.id })
                }
                .buttonStyle(.plain)
            }
            if !picks.isEmpty {
                Text("Кандидати (\(picks.count)) · тап — прибрати").font(.system(size: 13, weight: .semibold)).padding(.top, 6)
                ForEach(picks) { f in
                    Button { picks.removeAll { $0.id == f.id } } label: { row(f.posterUrl, f.title, f.year.map(String.init) ?? "", on: true) }.buttonStyle(.plain)
                }
            } else {
                Text("Додай хоча б двох кандидатів.").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var filterBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $type) { Text("Фільм").tag("movie"); Text("Серіал").tag("tv"); Text("Аніме").tag("anime") }.pickerStyle(.segmented)
            Stepper("Рейтинг від \(minRating)", value: $minRating, in: 5...9)
            Text("Випадкове з популярного на TMDB, чого ще нема у вашому списку.").font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .padding(14).background(Theme.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func row(_ poster: String?, _ title: String, _ sub: String, on: Bool) -> some View {
        HStack(spacing: 10) {
            RemoteImage(url: poster).frame(width: 40, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                Text(sub).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(on ? Theme.olive : Theme.ink.opacity(0.15))
        }
        .padding(6).background(on ? Theme.olive.opacity(0.12) : Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func slot(_ w: WatchItem) -> Slot { Slot(id: w.id, title: w.title, poster: w.posterUrl ?? w.backdropUrl, item: w, found: nil) }
    private func slot(_ f: Found) -> Slot { Slot(id: f.id, title: f.title, poster: f.posterUrl, item: nil, found: f) }

    private func find() async {
        let q = anyQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        anyResults = ((try? await API.current().search(q)) ?? []).map { Found(tmdbId: $0.tmdbId, mediaType: $0.mediaType, title: $0.title, originalTitle: $0.originalTitle, year: $0.year, posterPath: $0.posterPath, posterUrl: $0.posterUrl, isAnime: $0.isAnime) }
    }

    private func pool() async throws -> [Slot] {
        switch source {
        case .list:
            let c = ours.filter { chosen.contains($0.id) }
            return (c.isEmpty ? ours : c).map(slot)
        case .any:
            return picks.map(slot)
        case .filters:
            let list = try await API.current().discover(type: type, genre: nil, from: nil, to: nil, minRating: minRating, sort: "popular", page: Int.random(in: 1...3))
            return list.filter { $0.inList != true }.map(slot)
        }
    }

    private func spin() async {
        error = nil
        let p: [Slot]
        do { p = try await pool() } catch { self.error = error.localizedDescription; return }
        guard p.count >= 2 else {
            error = source == .any ? "Додай хоча б двох кандидатів." : source == .list ? "У списку замало фільмів." : "Нічого не знайшлось — зменш рейтинг."
            return
        }
        let winner = p.randomElement()!
        let n = 34
        var seq = (0..<n).map { _ in p.randomElement()! }
        seq.append(winner)
        seq += (0..<3).map { _ in p.randomElement()! }
        withAnimation(.easeOut(duration: 0.2)) { result = nil }
        spinning = true
        reel = seq
        winIndex = n
        offset = 0
        let target = -CGFloat(n) * (cardW + gap)
        // haptic ticks: fast at first, slower as the strip slows down
        Task { @MainActor in
            var t = 0.0, step = 0.05
            while t < 4.2 { UISelectionFeedbackGenerator().selectionChanged(); try? await Task.sleep(for: .seconds(step)); t += step; step *= 1.09 }
        }
        try? await Task.sleep(for: .milliseconds(60))
        withAnimation(.timingCurve(0.08, 0.82, 0.17, 1, duration: 4.4)) { offset = target }
        try? await Task.sleep(for: .seconds(4.45))
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { result = winner; spinning = false }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func take(_ s: Slot) async {
        if await store.run({
            if let w = s.item {
                store.upsert(try await API.current().patchWatch(w.id, .init(status: WatchStatus.watching.rawValue)))
                try? await API.current().turnDone(w.id)
            } else if let f = s.found {
                let w = try await API.current().addWatch(f.candidate, sourceUrl: nil)
                store.upsert(try await API.current().patchWatch(w.id, .init(status: WatchStatus.watching.rawValue)))
                try? await API.current().turnDone(w.id)
            }
        }) { dismiss() }
    }
}

// MARK: - Серії з оцінками

struct EpisodesSection: View {
    @EnvironmentObject var state: AppState
    let itemId: String
    @State private var data: EpisodesResult?
    @State private var season: Int?
    @State private var rate: EpisodeInfo?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Серії").font(.system(size: 17, weight: .semibold))
            if let d = data {
                overall(d)
                if d.seasons.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(d.seasons, id: \.n) { s in
                                Button { Task { await load(s.n) } } label: {
                                    Text("Сезон \(s.n)").font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 13).frame(height: 34)
                                        .background(d.season == s.n ? Theme.ink : Theme.tan.opacity(0.6), in: Capsule()).foregroundStyle(d.season == s.n ? Theme.paper : Theme.ink)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                ForEach(d.episodes) { e in
                    Button { rate = e } label: {
                        HStack(spacing: 10) {
                            Text("\(e.n)").font(.system(size: 13, weight: .bold)).frame(width: 28, height: 28).background(Theme.tan.opacity(0.6), in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.name ?? "Серія \(e.n)").font(.system(size: 14.5, weight: .medium)).lineLimit(1)
                                if let a = e.air { Text(MoneyText.date(a)).font(.system(size: 11.5)).foregroundStyle(Theme.muted) }
                            }
                            Spacer()
                            score(e.ratings[state.me?.id ?? ""], dark: true)
                            score(e.ratings[state.partner?.id ?? ""], dark: false)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } else if let error {
                Text(error).font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else {
                ProgressView().tint(Theme.olive)
            }
        }
        .task { await load(nil) }
        .confirmationDialog(rate.map { "Серія \($0.n): твоя оцінка" } ?? "", isPresented: Binding(get: { rate != nil }, set: { if !$0 { rate = nil } }), titleVisibility: .visible) {
            ForEach(Array((1...10).reversed()), id: \.self) { n in Button("\(n)") { Task { await set(n) } } }
            Button("Прибрати оцінку", role: .destructive) { Task { await set(nil) } }
        }
    }

    private func overall(_ d: EpisodesResult) -> some View {
        let me = d.overall.byMember[state.me?.id ?? ""], her = d.overall.byMember[state.partner?.id ?? ""]
        return HStack(spacing: 8) {
            box(me, state.me?.name ?? "я", false)
            box(her, state.partner?.name ?? "", false)
            box(d.overall.couple, "по серіях разом", true)
        }
    }

    private func box(_ v: Double?, _ who: String, _ dark: Bool) -> some View {
        VStack(spacing: 2) {
            Text(v.map { String(format: "%.1f", $0) } ?? "—").font(.system(size: 20, weight: .semibold))
            Text(who).font(.system(size: 11)).opacity(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(dark ? Theme.olive : Theme.tan.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(dark ? Theme.cream : Theme.ink)
    }

    private func score(_ v: Int?, dark: Bool) -> some View {
        Text(v.map(String.init) ?? "–").font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 28)
            .background(v == nil ? Theme.tan.opacity(0.35) : (dark ? Theme.coffee : Theme.tan), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(v != nil && dark ? Theme.cream : Theme.ink)
    }

    private func load(_ s: Int?) async {
        do { data = try await API.current().episodes(itemId, season: s); season = data?.season; error = nil }
        catch { self.error = "Список серій недоступний" }
    }

    private func set(_ n: Int?) async {
        guard let e = rate, let s = data?.season else { return }
        rate = nil
        try? await API.current().rateEpisode(itemId, season: s, episode: e.n, score: n)
        await load(s)
    }
}
