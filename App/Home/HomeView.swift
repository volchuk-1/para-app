import SwiftUI

/// Olive background, museum tiles that appear only when there is something to show.
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Binding var tab: Tab
    @Binding var route: Route?
    @State private var openEvent: Event?
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.olive.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    if store.offline { Banner(text: "Немає зв'язку — показую збережене").padding(.bottom, 6) }
                    if let e = store.error { Banner(text: e).padding(.bottom, 6) }
                    let tiles = store.home?.tiles ?? []
                    if tiles.isEmpty { emptyTile }
                    ForEach(tiles) { tile in tileView(tile) }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 110)
            }
            .refreshable { await store.refreshAll() }
        }
        .sheet(item: $openEvent) { e in InviteOrEventView(event: e) }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 18))
                        .frame(width: 44, height: 44)
                        .background(Theme.cream.opacity(0.14), in: Circle())
                }
                .foregroundStyle(Theme.cream)
                .accessibilityLabel("Налаштування")
            }
            (Text("Привіт, ") + Text(store.home?.greeting.name ?? state.me?.name ?? "").italic().bold() + Text("."))
                .font(.serif(34))
            Text(store.home?.greeting.subline ?? " ")
                .font(.serif(22))
                .opacity(0.9)
        }
        .foregroundStyle(Theme.cream)
        .padding(.horizontal, 8)
        .padding(.bottom, 14)
    }

    private var emptyTile: some View {
        Button { route = .invite } label: {
            MuseumTile(fill: Theme.cream, tag: "Почнемо", title: "Запроси на", underlined: "побачення.",
                       meta: "Або додай подію, серіал чи бажання через «+»", footer: "Створити запрошення")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func tileView(_ tile: Tile) -> some View {
        switch tile {
        case .next(let e):
            Button { openEvent = e } label: {
                let (t, u) = splitTitle(e.title)
                MuseumTile(fill: Theme.cream, tag: e.invitation != nil ? "Запрошення" : "Найближче",
                           title: t, underlined: u, meta: eventMeta(e)) {
                    if Countdown.shouldStartLiveActivity(startsAt: e.startsAt, now: Date()) {
                        Text(timerInterval: Date.countdown(to: e.startsAt), countsDown: true)
                            .font(.system(size: 28, weight: .bold).monospacedDigit())
                            .padding(.top, 10)
                    }
                }
            }
            .buttonStyle(.plain)
        case .awaiting(let list):
            ForEach(list) { e in
                Button { openEvent = e } label: {
                    let (t, u) = splitTitle(e.title)
                    MuseumTile(fill: Theme.sand, tag: "Чекає твоєї відповіді", title: t, underlined: u,
                               meta: "\(e.startsAt.dayTime)\(e.place.map { " · \($0)" } ?? "")", footer: "Відповісти")
                }
                .buttonStyle(.plain)
            }
        case .watching(let items):
            HStack(alignment: .top, spacing: 8) {
                ForEach(items) { w in
                    MuseumTile(fill: Theme.sage, tag: "Дивимось", title: w.title,
                               meta: w.episodeLabel ?? (w.mediaType == "tv" ? "серіал" : "фільм"), footer: nil) {
                        if w.mediaType == "tv" {
                            Button { Task { await nextEpisode(w.id) } } label: {
                                Label("+1 серія", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 12).frame(height: 34)
                                    .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 10)
                        }
                    }
                    .onTapGesture { tab = .together }
                }
            }
        case .want(let count, let posters):
            Button { tab = .together } label: {
                MuseumTile(fill: Theme.paper, tag: "Хочемо подивитись", title: "\(count) у", underlined: "списку.") {
                    HStack(spacing: -14) {
                        ForEach(Array(posters.enumerated()), id: \.offset) { _, p in
                            RemoteImage(url: p).frame(width: 54, height: 78)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.paper, lineWidth: 2))
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .buttonStyle(.plain)
        case .drop(let wishes):
            ForEach(wishes) { w in
                Button { tab = .us } label: {
                    MuseumTile(fill: Theme.paper, tag: "Подешевшало −\(w.dropPercent ?? 0)%", title: w.title,
                               meta: w.priceText, footer: "Подивитись")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func nextEpisode(_ id: String) async {
        await store.run {
            store.upsert(try await API.current().nextEpisode(id))
            store.home = try await API.current().home()
        }
    }

    private func eventMeta(_ e: Event) -> String {
        var parts = [e.startsAt.dayTime]
        if let p = e.place { parts.append(p) }
        if let inv = e.invitation {
            let other = state.partner?.name ?? ""
            switch inv.status {
            case .accepted: parts.append(e.createdBy == state.me?.id ? "\(other): прийду" : "ти прийдеш")
            case .pending: parts.append(e.createdBy == state.me?.id ? "чекаємо відповіді" : "чекає твоєї відповіді")
            case .reschedule: parts.append("просять інший час")
            case .cancelled: parts.append("скасовано")
            }
        }
        return parts.joined(separator: " · ")
    }
}
