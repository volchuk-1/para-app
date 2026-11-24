import SwiftUI

// MARK: - Multiplex feed models

struct FeedSession: Codable, Hashable { let date: String; let time: String; let tags: [String]; let buyUrl: String }
struct FeedFilm: Codable, Hashable, Identifiable {
    let title: String
    let poster: String?
    let age: String?
    let movieUrl: String?
    let watchId: String?
    let sessions: [FeedSession]
    var fav: Bool? = nil
    var id: String { title }
}
struct SoonFilm: Codable, Hashable, Identifiable {
    let when: String
    let day: String?
    let title: String
    let movieUrl: String?
    let poster: String?
    let onSale: Bool
    var date: String? = nil
    var remind: Bool? = nil
    var fav: Bool? = nil
    var id: String { title + when }
}
struct CinemaFeed: Codable { let cinema: String; let now: [FeedFilm]; let soon: [SoonFilm] }

extension API {
    func cinemaFeed() async throws -> CinemaFeed { try await get("/cinema/feed") }
    struct FavBody: Encodable { let title: String; let movieUrl: String?; let poster: String? }
    func fav(title: String, movieUrl: String?, poster: String?) async throws { let _: OkResult = try await send("POST", "/cinema/fav", FavBody(title: title, movieUrl: movieUrl, poster: poster)) }
    func unfav(title: String) async throws {
        let e = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? title
        let _: OkResult = try await send("DELETE", "/cinema/fav?title=\(e)", Empty())
    }
}

/// A session picked on the Multiplex page: the sheet is built from it, so it can never open empty.
struct BookPick: Identifiable { let film: FeedFilm; let session: FeedSession; var id: String { session.buyUrl } }

// MARK: - Разом → Вечір

/// Who is free this week, what we do, answers to the partner's requests, how our evenings went.
struct EveningPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @State private var days: [DayPlan] = []
    @State private var invite: String?
    @State private var reply: Event?
    @State private var busy = false
    private var cal: Calendar { Dock.calendar }

    var body: some View {
        let pn = state.partner?.name ?? ""
        let incoming = store.events.filter { $0.invitation?.status == .pending && $0.createdBy != state.me?.id && $0.startsAt > Date() }
        let answered = store.events.filter { $0.createdBy == state.me?.id && ($0.invitation?.replyNote?.isEmpty == false) && $0.startsAt > Date().addingTimeInterval(-86400) }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageTitle(plain: "Наш", italic: "вечір", sub: "Хто вільний і що робимо. Створити може кожен — другий підтверджує.")
                ForEach(incoming) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(pn.uppercased()) ПРОПОНУЄ").font(.system(size: 11, weight: .bold)).tracking(1).opacity(0.85)
                        Text(e.title).font(.serif(22, .bold))
                        Text(when(e)).font(.system(size: 13)).opacity(0.85)
                        HStack(spacing: 8) {
                            Button("Йдемо") { Task { await answer(e, "accept", nil) } }
                                .padding(.horizontal, 14).frame(height: 36).background(Theme.tan, in: Capsule()).foregroundStyle(Theme.ink)
                            Button("Відповісти інакше") { reply = e }
                                .padding(.horizontal, 14).frame(height: 36).background(.black.opacity(0.22), in: Capsule())
                        }
                        .font(.system(size: 13.5, weight: .semibold)).padding(.top, 8).disabled(busy)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.coffee, in: RoundedRectangle(cornerRadius: 24, style: .continuous)).foregroundStyle(Theme.cream)
                }
                ForEach(answered) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(pn.uppercased()) ВІДПОВІЛА").font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(Theme.muted)
                        Text(e.title).font(.serif(20, .bold))
                        Text("\(answerWord(e)) · «\(e.invitation?.replyNote ?? "")»").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                VStack(spacing: 0) {
                    ForEach(days) { d in dayRow(d) }
                    if days.isEmpty { ProgressView().tint(Theme.olive).padding(20) }
                }
                .padding(.horizontal, 14)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                history
                TripsBlock()
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 130)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .task { await load() }
        .refreshable { await load(); await store.refreshAll() }
        .fullScreenCover(item: Binding(get: { invite.map { DayID(id: $0) } }, set: { invite = $0?.id })) { d in InviteBooking(start: .day(d.id)) }
        .sheet(item: $reply) { e in ReplySheet(event: e, partner: pn) { Task { await store.refreshAll() } } }
    }

    private func dayRow(_ d: DayPlan) -> some View {
        let today = Evening.iso(Date())
        let date = Evening.date(d.date) ?? Date()
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text("\(cal.component(.day, from: date))").font(.system(size: 19, weight: .semibold))
                    Text(d.date == today ? "сьогодні" : date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "uk_UA")))).font(.system(size: 10.5))
                        .opacity(0.8)
                }
                .frame(width: 50, height: 52)
                .background(d.isFree ? Theme.olive : Theme.tan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(d.isFree ? Theme.cream : Theme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Evening.label(d)).font(.system(size: 14))
                    if d.status != "plan" { Text(Evening.note(d, partner: state.partner?.name ?? "")).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                }
                Spacer(minLength: 4)
                if d.isFree {
                    Button("Що робимо?") { invite = d.date }
                        .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 34).background(Theme.tan, in: Capsule())
                }
            }
            .padding(.vertical, 10)
            Divider()
        }
    }

    private var history: some View {
        let now = Date()
        let first = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let blanks = (cal.component(.weekday, from: first) + 5) % 7
        let n = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let done = Dictionary(store.events.filter { $0.invitation?.status == .accepted && cal.isDate($0.startsAt, equalTo: now, toGranularity: .month) }
            .map { (cal.component(.day, from: $0.startsAt), kind($0.title)) }, uniquingKeysWith: { a, _ in a })
        let todayN = cal.component(.day, from: now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Як ми проводили вечори").font(.system(size: 15, weight: .bold)); Spacer(); Text(now.formatted(.dateTime.month(.wide).locale(Locale(identifier: "uk_UA"))).capitalized).font(.system(size: 13)).foregroundStyle(Theme.muted) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(["пн", "вт", "ср", "чт", "пт", "сб", "нд"], id: \.self) { Text($0).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted) }
                ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: 32) }
                ForEach(1...n, id: \.self) { i in
                    let c = done[i].map(color)
                    Text("\(i)").font(.system(size: 11)).frame(maxWidth: .infinity, minHeight: 32)
                        .background(c ?? Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.coffee, lineWidth: i == todayN ? 1.5 : 0))
                        .foregroundStyle(c == nil ? Theme.muted : .white)
                }
            }
            HStack(spacing: 10) {
                legend("кіно", color("k")); legend("фільм удома", color("f")); legend("вечеря", color("p")); legend("прогулянка", color("w"))
            }
            .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(14).background(Theme.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func legend(_ t: String, _ c: Color) -> some View { HStack(spacing: 4) { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 10, height: 10); Text(t) } }
    private func kind(_ t: String) -> String {
        let l = t.lowercased()
        if l.hasPrefix("кіно") { return "k" }
        if l.contains("фільм") || l.contains("вдома") { return "f" }
        if l.contains("вечер") || l.contains("кава") || l.contains("кафе") || l.contains("ресторан") { return "p" }
        return "w"
    }
    private func color(_ k: String) -> Color {
        switch k { case "k": return Theme.coffee; case "f": return Theme.olive; case "p": return Color(hex: 0xB98A57); default: return Color(hex: 0x8DA06F) }
    }
    private func when(_ e: Event) -> String {
        e.startsAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "uk_UA"))) + (e.place.map { " · \($0)" } ?? "")
    }
    private func answerWord(_ e: Event) -> String {
        switch e.invitation?.status { case .accepted: return "Йдемо"; case .reschedule: return "Інший варіант"; case .cancelled: return "Не цього разу"; default: return "" }
    }

    private func load() async {
        let today = Date()
        let end = cal.date(byAdding: .day, value: 6, to: today) ?? today
        days = (try? await API.current().availability(from: Evening.iso(today), to: Evening.iso(end))) ?? []
    }

    private func answer(_ e: Event, _ action: String, _ note: String?) async {
        busy = true; defer { busy = false }
        _ = try? await API.current().answer(e.id, action: action, note: note)
        await store.refreshAll()
    }
}

/// «Йдемо, і ще…» / «Пропоную інше» / «Відмовитись».
struct ReplySheet: View {
    let event: Event
    let partner: String
    var done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "plus"
    @State private var pick: String?
    @State private var own = ""
    @State private var error: String?
    private let acts = [("Вечеря", "fork.knife"), ("Прогулянка", "tree.fill"), ("Кава", "cup.and.saucer.fill"), ("Фільм удома", "tv.fill"), ("Кіно", "film.fill"), ("Своє", "sparkles")]
    private let reasons = ["Хочу побути сам(а)", "Втомився(лась)", "Іншим разом"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(event.title).font(.serif(22, .bold))
                    Picker("", selection: $mode) { Text("Йдемо, і ще…").tag("plus"); Text("Пропоную інше").tag("other"); Text("Відмовитись").tag("no") }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { _, _ in pick = nil }
                    if mode == "no" {
                        Text("Можна й без пояснень — причину побачить лише \(partner).").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(reasons, id: \.self) { r in
                                Button(r) { pick = pick == r ? nil : r }
                                    .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 38)
                                    .background(pick == r ? Theme.ink : Theme.tan.opacity(0.5), in: Capsule())
                                    .foregroundStyle(pick == r ? Theme.paper : Theme.ink)
                            }
                        }
                    } else {
                        Text(mode == "plus" ? "Підтверджуєш і додаєш свою ідею до вечора:" : "Ні, але давай інакше:").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(acts, id: \.0) { a in
                                Button { pick = a.0 } label: {
                                    VStack(spacing: 4) { Image(systemName: a.1).font(.system(size: 20)); Text(a.0).font(.system(size: 12, weight: .semibold)) }
                                        .frame(maxWidth: .infinity, minHeight: 64)
                                        .background(pick == a.0 ? Theme.olive : Theme.tan.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .foregroundStyle(pick == a.0 ? Theme.cream : Theme.ink)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if pick == "Своє" { TextField(mode == "other" ? "Що й коли? Напр.: прогулянка в суботу о 18" : "Що ще? Напр.: після кіно — десерт", text: $own).field() }
                    }
                    if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coffee) }
                    Button { Task { await send() } } label: {
                        Text(mode == "plus" ? "Йдемо й пропоную" : mode == "other" ? "Надіслати пропозицію" : "Відмовитись")
                            .font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 52)
                            .background(mode == "no" ? Theme.coffee : Theme.ink, in: Capsule()).foregroundStyle(Theme.paper)
                    }
                }
                .padding(18)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Відповісти").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } } }
        }
        .tint(Theme.olive)
        .presentationDetents([.large])
    }

    private func send() async {
        let what = pick == "Своє" ? own.trimmingCharacters(in: .whitespaces) : pick
        if mode != "no", (what ?? "").isEmpty { error = "Обери, що пропонуєш"; return }
        let action = mode == "plus" ? "accept" : mode == "other" ? "reschedule" : "decline"
        let note = mode == "plus" ? "Ще пропоную: \(what ?? "")" : mode == "other" ? "Пропоную: \(what ?? "")" : what
        do { _ = try await API.current().answer(event.id, action: action, note: note); done(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - Календар → Кіно

/// Multiplex «Паннонія» in its own dark style: films now (by day) and coming soon. ♥ on sessions when both are free.
struct CinemaPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL
    @State private var feed: CinemaFeed?
    @State private var avail: [DayPlan] = []
    @State private var tab = "now"
    @State private var day = Evening.iso(Date())
    @State private var book: BookPick?
    @State private var flip: FlipFilm?
    @State private var favs: [String: Bool] = [:]
    @State private var error: String?
    @State private var reminded: Set<String> = []
    @State private var unreminded: Set<String> = []
    private let bg = Color(hex: 0x1C1A1A), card = Color(hex: 0x272424), accent = Color(hex: 0xF2B640)
    private var cal: Calendar { Dock.calendar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("MULTIPLEX").font(.system(size: 13, weight: .heavy)).tracking(4)
                    Text("\(feed?.cinema ?? "Паннонія") · Ужгород").font(.system(size: 13)).opacity(0.55)
                }
                Text(tab == "now" ? "Зараз у кіно" : "Скоро у прокаті").font(.system(size: 30, weight: .bold)).padding(.trailing, 60)
                HStack(spacing: 6) {
                    tabButton("now", "Зараз"); tabButton("soon", "Скоро")
                }
                .padding(4).background(card, in: Capsule())
                if let error { Text(error).font(.system(size: 13)).foregroundStyle(accent) }
                if feed == nil && error == nil { ProgressView().tint(.white).frame(maxWidth: .infinity).padding(30) }
                if let f = feed { tab == "now" ? AnyView(nowList(f)) : AnyView(soonGrid(f)) }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 130)
        }
        .background(bg.ignoresSafeArea())
        .foregroundStyle(.white)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $book) { b in CinemaInviteSheet(film: b.film, session: b.session, plan: avail.first { $0.date == b.session.date }) }
        .fullScreenCover(item: $flip, onDismiss: { Task { await load() } }) { f in TrailerFlip(film: f) }
        .overlay(alignment: .top) { bg.frame(height: 0).background(bg.ignoresSafeArea(edges: .top)) }
    }

    private func tabButton(_ k: String, _ l: String) -> some View {
        Button(l) { tab = k }.font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 36)
            .background(tab == k ? Color.white : .clear, in: Capsule()).foregroundStyle(tab == k ? bg : .white.opacity(0.65))
    }

    private func nowList(_ f: CinemaFeed) -> some View {
        let today = Evening.iso(Date())
        let dayList = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: Date()) }.map { Evening.iso($0) }
        let films = f.now.filter { $0.sessions.contains { $0.date == day } }
        let lastDay = dayList.last ?? today
        let later = f.now.filter { !$0.sessions.contains { $0.date <= lastDay } }
        let plan = avail.first { $0.date == day }
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(dayList, id: \.self) { d in
                        Button(dayLabel(d, today: today)) { day = d }
                            .font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
                            .background(d == day ? accent : card, in: Capsule()).foregroundStyle(d == day ? bg : .white)
                    }
                }
            }
            Text(plan?.partnerKnown == false ? "♥ з'явиться, коли \(state.partner?.name ?? "") внесе свій графік" : "♥ — сеанс, коли ви обоє вільні · тап — запросити")
                .font(.system(size: 12.5)).opacity(0.55)
            if films.isEmpty { Text("Цього дня сеансів нема.").font(.system(size: 13)).opacity(0.55) }
            ForEach(films) { film in filmRow(film, sessions: film.sessions.filter { $0.date == day }, plan: plan) }
            if !later.isEmpty {
                Text("Вже в розкладі, пізніше").font(.system(size: 15, weight: .semibold)).opacity(0.75).padding(.top, 14)
                ForEach(later) { film in filmRow(film, sessions: [], plan: nil) }
            }
        }
    }

    private func filmRow(_ film: FeedFilm, sessions: [FeedSession], plan: DayPlan?) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.white.opacity(0.08))
            HStack(alignment: .top, spacing: 12) {
                Color.clear.frame(width: 78, height: 112)
                    .overlay { if let p = film.poster { RemoteImage(url: p) } else { card } }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { flip = FlipFilm(title: film.title, poster: film.poster, watchId: film.watchId, tmdbId: nil, mediaType: nil, fav: favs[film.title] ?? (film.fav == true)) }
                    .overlay(alignment: .top) {
                        if film.watchId != nil {
                            Text("у «Хочемо»").font(.system(size: 9.5, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Theme.olive, in: RoundedRectangle(cornerRadius: 6)).padding(6)
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(film.title).font(.system(size: 15.5, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        heart(film.title, on: favs[film.title] ?? (film.fav == true)) { await toggleFav(film.title, film.movieUrl, film.poster, on: favs[film.title] ?? (film.fav == true)) }
                    }
                    Text([film.age, sessions.isEmpty ? film.sessions.first.map { "з \(MoneyText.date($0.date).split(separator: " ").prefix(2).joined(separator: " "))" } : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12)).opacity(0.55)
                    FlowRow(items: sessions.map { SessionChip(s: $0) }) { c in
                        let good = (plan?.bothFree ?? false) && c.s.time >= (plan?.freeFrom ?? "99")
                        Button { book = BookPick(film: film, session: c.s) } label: {
                            HStack(spacing: 4) {
                                Text(c.s.time).font(.system(size: 14, weight: .semibold))
                                if !c.s.tags.isEmpty { Text(c.s.tags.joined(separator: " ")).font(.system(size: 10, weight: .bold)).foregroundStyle(accent) }
                                if good { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(Color(hex: 0x9DB27F)) }
                            }
                            .padding(.horizontal, 11).frame(height: 34)
                            .background(card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(good ? Color(hex: 0x8DA06F) : Color.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
        }
    }

    private func soonGrid(_ f: CinemaFeed) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
            ForEach(f.soon) { s in
                VStack(alignment: .leading, spacing: 4) {
                    Color.clear.frame(height: 190)
                        .overlay { if let p = s.poster { RemoteImage(url: p) } else { card } }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { flip = FlipFilm(title: s.title, poster: s.poster, watchId: nil, tmdbId: nil, mediaType: nil, fav: favs[s.title] ?? (s.fav == true)) }
                        .overlay(alignment: .bottomLeading) {
                            if s.onSale { Text("Квитки у продажу").font(.system(size: 10.5, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 3).background(accent, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(bg).padding(8) }
                        }
                    HStack {
                        Text(s.when).font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                        Spacer()
                        heart(s.title, on: favs[s.title] ?? (s.fav == true)) { await toggleFav(s.title, s.movieUrl, s.poster, on: favs[s.title] ?? (s.fav == true)) }
                    }
                    .padding(.top, 4)
                    Text(s.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    HStack(spacing: 6) {
                        if let d = s.date {
                            let on = reminded.contains(s.title) || (s.remind == true && !unreminded.contains(s.title))
                            Button { Task { await toggleRemind(s, d, on) } } label: {
                                Label(on ? "Нагадаю" : "Нагадати", systemImage: on ? "bell.fill" : "bell")
                            }
                            .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).frame(height: 30)
                            .background(on ? accent : card, in: Capsule()).foregroundStyle(on ? bg : Color(hex: 0xF3EEE6))
                        }
                        if let u = s.movieUrl?.asURL {
                            Button("Детальніше") { openURL(u) }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: 30).background(card, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func heart(_ title: String, on: Bool, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: on ? "heart.fill" : "heart").font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on ? Color(hex: 0xE0715A) : .white.opacity(0.6)).frame(width: 34, height: 34)
                .background(card, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Прибрати з обраного" : "В обране")
    }

    private func toggleFav(_ title: String, _ url: String?, _ poster: String?, on: Bool) async {
        favs[title] = !on
        do { if on { try await API.current().unfav(title: title) } else { try await API.current().fav(title: title, movieUrl: url, poster: poster) } }
        catch { favs[title] = on; self.error = error.localizedDescription }
    }

    private func toggleRemind(_ s: SoonFilm, _ date: String, _ on: Bool) async {
        do {
            if on { try await API.current().unremind(title: s.title); reminded.remove(s.title); unreminded.insert(s.title) }
            else { try await API.current().remind(title: s.title, date: date, movieUrl: s.movieUrl); reminded.insert(s.title); unreminded.remove(s.title) }
        } catch { self.error = error.localizedDescription }
    }

    private func dayLabel(_ d: String, today: String) -> String {
        if d == today { return "Сьогодні" }
        if let t = Evening.date(today), let n = cal.date(byAdding: .day, value: 1, to: t), Evening.iso(n) == d { return "Завтра" }
        guard let date = Evening.date(d) else { return d }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "uk_UA")))) \(cal.component(.day, from: date))"
    }

    private func load() async {
        do {
            async let f = API.current().cinemaFeed()
            let today = Date()
            async let a = API.current().availability(from: Evening.iso(today), to: Evening.iso(cal.date(byAdding: .day, value: 6, to: today) ?? today))
            feed = try await f
            avail = (try? await a) ?? []
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct SessionChip: Identifiable { let s: FeedSession; var id: String { s.buyUrl } }

/// Confirm a cinema date: creates the invitation (and so the calendar event) with the session link.
struct CinemaInviteSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let film: FeedFilm
    let session: FeedSession
    let plan: DayPlan?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Кіно з \(state.partner?.name ?? "")").font(.serif(26, .bold))
            Text("\(film.title) · \(MoneyText.date(session.date)) о \(session.time) · Паннонія").font(.system(size: 14)).foregroundStyle(Theme.muted)
            Text((plan.map { Evening.note($0, partner: state.partner?.name ?? "") + "\n" } ?? "") + "Подія одразу з'явиться в календарі як «чекає відповіді». Після «Йдемо» — кнопка «Купити квитки».")
                .font(.system(size: 13.5)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.tan.opacity(0.4), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coffee) }
            Button { Task { await send() } } label: {
                Group { if busy { ProgressView().tint(Theme.paper) } else { Text("Надіслати запрошення") } }
                    .font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 54)
                    .background(Theme.ink, in: Capsule()).foregroundStyle(Theme.paper)
            }
            .disabled(busy)
        }
        .padding(20)
        .presentationDetents([.medium])
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }

    private func send() async {
        busy = true; defer { busy = false }
        let hm = session.time.split(separator: ":").compactMap { Int($0) }
        guard hm.count == 2, let base = Evening.date(session.date), let startsAt = Dock.calendar.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: base) else { return }
        var d = EventDraft(ownerId: nil, title: "Кіно: \(film.title)", startsAt: startsAt, endsAt: nil, place: "Multiplex «Паннонія»", mapUrl: nil, note: nil, dress: nil, message: nil)
        d.watchId = film.watchId
        d.buyUrl = session.buyUrl
        let ok = await store.run { let e = try await API.current().createInvitation(d); store.upsert(e) }
        if ok { dismiss() } else { error = store.error }
    }
}
