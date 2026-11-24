import SwiftUI

/// Разом: Дивимось → Хочемо → Подивились, cards with the picture on top.
struct WatchPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Binding var route: Route?
    @State private var tab: WatchStatus = .watching
    @State private var open: WatchItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(plain: "Разом", italic: "дивимось", sub: "Серіали, фільми, аніме")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([WatchStatus.watching, .want, .done, .dropped], id: \.self) { s in
                            OutlineChip(text: s.label, on: tab == s) { withAnimation(.snappy) { tab = s } }
                        }
                        OutlineChip(text: "Знайти", icon: "magnifyingglass", on: false) { route = .watchSearch }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.horizontal, -18)
                let list = store.watch.filter { $0.status == tab }
                if list.isEmpty {
                    EmptyCard(text: tab == .watching ? "Зараз нічого не дивитесь. Відкрий фільм із «Хочемо» й натисни «Почати»."
                              : tab == .want ? "Поділись відео з TikTok чи YouTube або знайди через «Знайти»."
                              : tab == .dropped ? "Тут те, що кинули. Передумали — відкрий і зміни статус." : "Тут будуть подивлені — з вашими оцінками й відгуками.")
                }
                ForEach(list) { w in
                    Button { open = w } label: { FilmCard(item: w) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 120)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .fullScreenCover(item: $open) { w in FilmPage(item: w, route: $route) }
    }
}

struct FilmCard: View {
    @EnvironmentObject var state: AppState
    let item: WatchItem
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: item.backdropUrl ?? item.posterUrl)
                .frame(height: 190).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if item.status == .watching, let ep = item.episodeLabel {
                        Text(ep).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.65), in: Capsule()).foregroundStyle(.white).padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let r = Release.line(item.releaseDate, inUkraine: item.releaseInUkraine) {
                        Text(r.replacingOccurrences(of: "У кіно в Україні з ", with: "з ")).font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Theme.paper.opacity(0.92), in: Capsule())
                            .foregroundStyle(Theme.coffee).padding(10)
                    }
                }
            HStack(alignment: .firstTextBaseline) {
                Text(item.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer()
                if let t = item.rating?.tmdb { Label(String(format: "%.1f", t), systemImage: "star.fill").font(.system(size: 14, weight: .semibold)).labelStyle(.titleAndIcon) }
            }
            .padding(.horizontal, 6).padding(.top, 10)
            Text([item.kindLabel, item.year.map(String.init), "додав(ла) \(item.addedBy == state.me?.id ? "ти" : state.partner?.name ?? "")"].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted).padding(.horizontal, 6).padding(.top, 2)
            if item.status == .done, let avg = item.avg {
                Text("разом \(String(format: "%.1f", avg))").font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Theme.tan.opacity(0.6), in: Capsule()).padding(.horizontal, 6).padding(.top, 8)
            }
        }
        .padding(8).padding(.bottom, 4)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Film page like a listing: gallery, ratings, status, our scores and reviews, a dark bar with the main action.
struct FilmPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State var item: WatchItem
    @Binding var route: Route?
    @State private var review = ""
    @State private var invite = false
    @State private var confirmDelete = false

    init(item: WatchItem, route: Binding<Route?>) { _item = State(initialValue: item); _route = route }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    gallery
                    VStack(alignment: .leading, spacing: 14) {
                        Text(item.title).font(.system(size: 24, weight: .bold))
                        rates
                        Text([item.kindLabel, item.year.map(String.init)].compactMap { $0 }.joined(separator: " · ") + ((item.genres ?? []).isEmpty ? "" : " · " + (item.genres ?? []).prefix(2).joined(separator: ", ")))
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        Picker("Статус", selection: Binding(get: { item.status }, set: { s in Task { await patch { try await API.current().patchWatch(item.id, .init(status: s.rawValue)) } } })) {
                            ForEach(WatchStatus.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Divider()
                        Text("Додав(ла) \(item.addedBy == state.me?.id ? "ти" : state.partner?.name ?? "")").font(.system(size: 15, weight: .semibold))
                        if let o = item.overview, !o.isEmpty {
                            Divider()
                            Text("Про що").font(.system(size: 17, weight: .semibold))
                            Text(o).font(.system(size: 14.5)).foregroundStyle(Theme.ink.opacity(0.8))
                        }
                        if let g = item.genres, !g.isEmpty {
                            FlowChips(items: g)
                        }
                        Divider()
                        scores
                        reviews
                        if let src = item.sourceUrl?.asURL {
                            Button { openURL(src) } label: { Label("Відео, звідки додали", systemImage: "play.rectangle") }.foregroundStyle(Theme.olive)
                        }
                        Button("Видалити зі списку", role: .destructive) { confirmDelete = true }
                    }
                    .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 130)
                    .background(Theme.paper, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
                    .padding(.top, -34)
                }
            }
            .ignoresSafeArea(edges: .top)
            bottomBar
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .onAppear { review = item.reviews?[state.me?.id ?? ""] ?? "" }
        .fullScreenCover(isPresented: $invite) { InviteBooking(start: .film(item.id)) }
        .confirmationDialog("Видалити?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Видалити", role: .destructive) { Task { await remove() } }
        }
    }

    private var gallery: some View {
        let urls = [item.backdropUrl, item.posterUrl].compactMap { $0 }
        return TabView {
            ForEach(urls.isEmpty ? [""] : urls, id: \.self) { u in RemoteImage(url: u.isEmpty ? nil : u) }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 440)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .top) { LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom).frame(height: 120).allowsHitTesting(false) }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 40, height: 40)
                    .background(Theme.paper.opacity(0.9), in: Circle())
            }
            .foregroundStyle(Theme.ink).padding(.leading, 18).padding(.top, 58)
        }
    }

    private var rates: some View {
        let r = item.rating
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let t = r?.tmdb { rateChip("TMDB \(String(format: "%.1f", t))", Color(hex: 0x0D7C5F)) }
                if let i = r?.imdb { rateChip("IMDb \(String(format: "%.1f", i))", Color(hex: 0xB8860B)) }
                if let rt = r?.rt { rateChip("🍅 \(rt)%", Color(hex: 0xC0392B)) }
                if let rel = Release.line(item.releaseDate, inUkraine: item.releaseInUkraine) { rateChip(rel, Theme.coffee) }
                if r?.tmdb == nil && r?.imdb == nil && Release.line(item.releaseDate, inUkraine: item.releaseInUkraine) == nil { rateChip("Рейтингу ще нема", Theme.muted) }
            }
        }
    }

    private func rateChip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 13, weight: .semibold)).foregroundStyle(c)
            .padding(.horizontal, 11).padding(.vertical, 6).background(Theme.tan.opacity(0.55), in: Capsule())
    }

    private var scores: some View {
        let mine = item.ratings[state.me?.id ?? ""] ?? 0
        let hers = item.ratings[state.partner?.id ?? ""]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Наша оцінка").font(.system(size: 17, weight: .semibold))
            HStack(spacing: 10) {
                scoreBox(mine > 0 ? "\(mine)" : "—", state.me?.name ?? "", false)
                scoreBox(hers.map(String.init) ?? "—", state.partner?.name ?? "", false)
                scoreBox(item.avg.map { String(format: "%.1f", $0) } ?? "—", "разом", true)
            }
            HStack(spacing: 4) {
                ForEach(1...10, id: \.self) { n in
                    Button { Task { await patch { try await API.current().rate(item.id, n) } } } label: {
                        Text("\(n)").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 36)
                            .background(n <= mine ? Theme.coffee : Theme.tan.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(n <= mine ? Theme.cream : Theme.ink)
                    }
                }
            }
        }
    }

    private func scoreBox(_ v: String, _ who: String, _ dark: Bool) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 26, weight: .semibold))
            Text(who).font(.system(size: 12)).opacity(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(dark ? Theme.olive : Theme.tan.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .foregroundStyle(dark ? Theme.cream : Theme.ink)
    }

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Мій відгук").font(.system(size: 13, weight: .semibold))
                TextField("Що сподобалось, з ким дивились, де…", text: $review, axis: .vertical).lineLimit(2...6)
                Button("Зберегти") { Task { await patch { try await API.current().review(item.id, text: review) } } }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.olive)
            }
            .padding(14).background(Theme.tan.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if let p = state.partner, let t = item.reviews?[p.id], !t.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).font(.system(size: 13, weight: .semibold))
                    Text(t).font(.system(size: 14))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).background(Theme.tan.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(barCaption).font(.system(size: 12)).opacity(0.7)
                Text(barValue).font(.system(size: 17, weight: .semibold)).lineLimit(1)
            }
            Spacer()
            Button(barButton) { Task { await barAction() } }
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 20).frame(height: 48)
                .background(Theme.paper, in: Capsule()).foregroundStyle(Theme.ink)
        }
        .padding(.leading, 20).padding(.trailing, 10).padding(.vertical, 10)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .foregroundStyle(Theme.paper)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var barCaption: String {
        switch item.mainAction {
        case .nextEpisode: return "Зараз"
        case .invite: return Release.line(item.releaseDate, inUkraine: item.releaseInUkraine) != nil ? "Скоро в кіно" : "Кіно"
        case .start: return "Хочемо"
        case .done: return "Разом"
        }
    }
    private var barValue: String {
        switch item.mainAction {
        case .nextEpisode: return item.episodeLabel ?? "Ще не почали"
        case .invite: return Release.line(item.releaseDate, inUkraine: item.releaseInUkraine)?.replacingOccurrences(of: "У кіно в Україні з ", with: "з ") ?? "Multiplex"
        case .start: return "Почнемо?"
        case .done: return item.avg.map { String(format: "%.1f / 10", $0) } ?? "Оцініть"
        }
    }
    private var barButton: String {
        switch item.mainAction {
        case .nextEpisode: return "+1 серія"
        case .invite: return "Запросити"
        case .start: return "Почати"
        case .done: return "Готово"
        }
    }
    private func barAction() async {
        switch item.mainAction {
        case .nextEpisode: await patch { try await API.current().nextEpisode(item.id) }
        case .invite: invite = true
        case .start: await patch { try await API.current().patchWatch(item.id, .init(status: WatchStatus.watching.rawValue)) }
        case .done: dismiss()
        }
    }

    private func patch(_ work: @escaping () async throws -> WatchItem) async {
        await store.run { let w = try await work(); item = w; store.upsert(w) }
    }

    private func remove() async {
        if await store.run({ try await API.current().deleteWatch(item.id); store.watch.removeAll { $0.id == item.id } }) { dismiss() }
    }
}

// MARK: - small shared pieces

struct PageTitle: View {
    let plain: String
    let italic: String
    var sub: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plain + " " + italic).font(.serif(34, .bold)).padding(.trailing, 60)
            if let sub { Text(sub).font(.system(size: 15)).foregroundStyle(Theme.muted) }
        }
    }
}

struct OutlineChip: View {
    let text: String
    var icon: String? = nil
    let on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(text)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 16).frame(height: 38)
            .background(on ? Theme.ink : Theme.tan.opacity(0.6), in: Capsule())
            .foregroundStyle(on ? Theme.paper : Theme.ink)
        }
        .buttonStyle(.plain)
    }
}

struct EmptyCard: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 14.5)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20).background(Theme.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct FlowChips: View {
    let items: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { g in
                    Text(g).font(.system(size: 12.5)).padding(.horizontal, 11).padding(.vertical, 6).background(Theme.tan.opacity(0.55), in: Capsule())
                }
            }
        }
    }
}
