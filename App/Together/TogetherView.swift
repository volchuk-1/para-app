import SwiftUI

/// «Разом» → «Дивимось»: Хочемо / Дивимось / Подивились, filter by type, posters grid.
struct TogetherView: View {
    @EnvironmentObject var store: Store
    @Binding var route: Route?
    @State private var status: WatchStatus = .want
    @State private var kind = "all"
    @State private var open: WatchItem?

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack(alignment: .top) {
            Theme.cream.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Разом дивимось").font(.serif(34, .bold))
                        Spacer()
                        Button { route = .watchSearch } label: {
                            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .bold))
                                .frame(width: 44, height: 44).background(Theme.olive.opacity(0.12), in: Circle())
                        }
                        .accessibilityLabel("Пошук фільму")
                    }
                    Picker("Статус", selection: $status) {
                        ForEach([WatchStatus.want, .watching, .done]) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([("all", "Усе"), ("movie", "Фільми"), ("tv", "Серіали"), ("anime", "Аніме")], id: \.0) { k in
                                Button { kind = k.0 } label: { Chip(text: k.1, selected: kind == k.0) }.buttonStyle(.plain)
                            }
                        }
                    }
                    let list = items
                    if list.isEmpty {
                        Text(status == .want
                             ? "Тут поки порожньо. Поділись відео з TikTok чи YouTube у DaVincit — або знайди через пошук."
                             : "Тут поки порожньо.")
                            .font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.vertical, 20)
                    }
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(list) { w in
                            Button { open = w } label: { PosterCard(item: w) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
            .refreshable { await store.refreshAll() }
        }
        .foregroundStyle(Theme.ink)
        .sheet(item: $open) { w in WatchDetailView(item: w) }
    }

    private var items: [WatchItem] {
        store.watch.filter { w in
            let st = status == .done ? (w.status == .done || w.status == .dropped) : w.status == status
            let k: Bool
            switch kind {
            case "movie": k = w.mediaType == "movie" && !w.isAnime
            case "tv": k = w.mediaType == "tv" && !w.isAnime
            case "anime": k = w.isAnime
            default: k = true
            }
            return st && k
        }
    }
}

struct PosterCard: View {
    let item: WatchItem
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: item.posterUrl)
                .frame(height: 240).frame(maxWidth: .infinity).clipped()
            LinearGradient(colors: [.clear, Theme.espresso.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                Text([item.kindLabel, item.year.map(String.init), item.episodeLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .opacity(0.85)
            }
            .foregroundStyle(Theme.cream)
            .padding(12)
            if let avg = item.avg {
                Text(String(format: "%.1f", avg)).font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(10)
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// One title: status, +1 episode, my rating and the partner's.
struct WatchDetailView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State var item: WatchItem
    @State private var confirmDelete = false
    @State private var cinema = false

    init(item: WatchItem) { _item = State(initialValue: item) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: item.posterUrl)
                    .frame(height: 360).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.serif(30, .bold))
                    Text([item.kindLabel, item.year.map(String.init), addedByText].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    if let r = Release.line(item.releaseDate, inUkraine: item.releaseInUkraine) {
                        Label(r, systemImage: "ticket")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.tan, in: Capsule())
                            .foregroundStyle(Theme.coffee)
                    }
                }
                Picker("Статус", selection: Binding(get: { item.status }, set: { s in Task { await patch(status: s) } })) {
                    ForEach(WatchStatus.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if item.mediaType == "tv" {
                    HStack {
                        Text(item.episodeLabel ?? "Ще не почали").font(.system(size: 22, weight: .bold).monospacedDigit())
                        Spacer()
                        Button { Task { await next() } } label: {
                            Label("+1 серія", systemImage: "plus").font(.system(size: 15, weight: .semibold))
                                .padding(.horizontal, 18).frame(height: 46)
                                .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                        }
                    }
                    .padding(16).background(Theme.sage, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Твоя оцінка").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                    HStack(spacing: 4) {
                        ForEach(1...10, id: \.self) { n in
                            let mineScore = item.ratings[state.me?.id ?? ""] ?? 0
                            Button { Task { await rate(n) } } label: {
                                Text("\(n)").font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(n <= mineScore ? Theme.coffee : Theme.cream, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(n <= mineScore ? Theme.cream : Theme.ink)
                            }
                        }
                    }
                    if let p = state.partner, let s = item.ratings[p.id] {
                        Text("\(p.name): \(s)/10").font(.system(size: 14))
                    }
                    if let avg = item.avg { Text("Разом: \(String(format: "%.1f", avg))").font(.system(size: 14, weight: .semibold)) }
                }
                if item.mediaType == "movie" {
                    Button { cinema = true } label: {
                        Label("Хочемо в кіно", systemImage: "ticket").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(fill: Theme.olive, text: Theme.cream))
                }
                if let src = item.sourceUrl?.asURL {
                    Button { openURL(src) } label: { Label("Відкрити відео, звідки додали", systemImage: "play.rectangle") }
                }
                Button("Видалити зі списку", role: .destructive) { confirmDelete = true }
                    .padding(.top, 8)
                if let e = store.error { Text(e).foregroundStyle(Theme.coffee) }
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: $cinema) { InviteEditor(existing: nil, prefillTitle: "Кіно: \(item.title)", prefillStart: Release.cinemaStart(item.releaseDate)) }
        .confirmationDialog("Видалити?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Видалити", role: .destructive) { Task { await remove() } }
        }
    }

    private var addedByText: String? {
        if item.addedBy == state.me?.id { return "додав(ла) ти" }
        if let p = state.partner, item.addedBy == p.id { return "додав(ла) \(p.name)" }
        return nil
    }

    private func patch(status: WatchStatus) async {
        await store.run { let w = try await API.current().patchWatch(item.id, .init(status: status.rawValue)); item = w; store.upsert(w) }
    }
    private func next() async {
        await store.run { let w = try await API.current().nextEpisode(item.id); item = w; store.upsert(w) }
    }
    private func rate(_ n: Int) async {
        await store.run { let w = try await API.current().rate(item.id, n); item = w; store.upsert(w) }
    }
    private func remove() async {
        let ok = await store.run {
            try await API.current().deleteWatch(item.id)
            store.watch.removeAll { $0.id == item.id }
        }
        if ok { dismiss() }
    }
}

/// Search TMDB and add to «Хочемо».
struct WatchSearchView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let sourceUrl: String?
    @State private var query = ""
    @State private var results: [Candidate] = []
    @State private var busy = false
    @State private var searched = false
    @State private var added: Set<String> = []
    @State private var lastAdded: String?

    var body: some View {
        NavigationStack {
            List {
                if let lastAdded {
                    Label("Додано: \(lastAdded) — шукай наступний", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.olive)
                }
                ForEach(results) { c in
                    let on = added.contains(c.id) || store.watch.contains { $0.tmdbId == c.tmdbId && $0.mediaType == c.mediaType }
                    Button { Task { await add(c) } } label: {
                        HStack {
                            CandidateRow(c: c)
                            if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.olive) }
                        }
                    }
                    .disabled(on)
                    .opacity(on ? 0.6 : 1)
                }
                if results.isEmpty && searched && !busy {
                    Text("Нічого не знайшлося. Спробуй назву англійською.").foregroundStyle(Theme.muted)
                }
                if let e = store.error { Text(e).foregroundStyle(Theme.coffee) }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Назва фільму чи серіалу")
            .onSubmit(of: .search) { Task { await search() } }
            // suggestions while typing: a short pause after the last letter; a newer letter cancels the older search
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespaces)
                // an empty field (after adding a film) is not «nothing found»
                guard q.count >= 2 else { if q.isEmpty { results = []; searched = false }; return }
                try? await Task.sleep(for: .milliseconds(230))
                if Task.isCancelled { return }
                await search()
            }
            .navigationTitle("Знайти")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрити") { dismiss() } } }
            .overlay { if busy { ProgressView() } }
        }
    }

    private func search() async {
        let q = query
        busy = results.isEmpty
        defer { busy = false }
        guard let r = try? await API.current().search(q), q == query else { return }
        results = r
        searched = true
    }

    private func add(_ c: Candidate) async {
        added.insert(c.id)
        Haptic.hit(.medium)
        let ok = await store.run { store.upsert(try await API.current().addWatch(c, sourceUrl: sourceUrl)) }
        if !ok { added.remove(c.id); return }
        // from a shared link there is one film to add; from search the next one can follow at once
        if sourceUrl != nil { dismiss(); return }
        lastAdded = c.title
        searched = false
        query = ""
        results = []
    }
}
