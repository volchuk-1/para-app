import SwiftUI

/// Invitation as a booking (courts reference): what we do, which day (♥ = both free), session at Multiplex or arrival time,
/// «Надіслати запит» — the partner answers «Йдемо» / «Інший день».
struct InviteBooking: View {
    enum Start: Equatable { case blank, film(String), day(String) }

    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let start: Start

    @State private var pick = ""          // cinema | dinner | walk | own
    @State private var filmId: String?    // cinema: the film from «Хочемо», picked inside the card
    @State private var day = ""
    @State private var avail: [DayPlan] = []
    @State private var sessions: [String: [CinemaSession]] = [:]
    @State private var time: String?
    @State private var arrival = 19 * 60
    @State private var custom = ""
    @State private var place = ""
    @State private var busy = false
    @State private var error: String?

    private let acts: [(String, String, String)] = [("cinema", "film.fill", "Кіно"), ("dinner", "fork.knife", "Вечеря"), ("walk", "tree.fill", "Прогулянка"), ("own", "sparkles", "Своє")]
    private var cal: Calendar { Dock.calendar }
    private var movies: [WatchItem] {
        var m = store.watch.filter { $0.mediaType == "movie" && $0.status != .done && $0.status != .dropped }
        if case .film(let id) = start, !m.contains(where: { $0.id == id }), let w = store.watch.first(where: { $0.id == id }) { m.insert(w, at: 0) }
        return Array(m.prefix(6))
    }
    private var film: WatchItem? { pick == "cinema" ? filmId.flatMap { id in store.watch.first { $0.id == id } } : nil }
    private var act: (String, String, String) { acts.first { $0.0 == pick } ?? acts[3] }
    private var filmSessions: [CinemaSession]? { film.flatMap { sessions[$0.id] } }

    var body: some View {
        ZStack(alignment: .top) {
            hero
            ScrollView {
                VStack(spacing: 0) {
                    title.padding(.top, 96)
                    chips.padding(.top, 70)
                    card.padding(.top, 18)
                }
                .padding(.bottom, 30)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44)
                        .background(.white.opacity(0.22), in: Circle()).foregroundStyle(Theme.paper)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .background(Theme.oliveDeep.ignoresSafeArea())
        .task { await setup() }
    }

    /// Neutral header: warm gradient + a big faint sign of what we do. No film posters here — they made the screen
    /// wider than the phone; the film is picked inside the card.
    private var hero: some View {
        Color.clear
            .frame(maxWidth: .infinity).frame(height: 440)
            .background {
                ZStack {
                    RadialGradient(colors: [Theme.coffee, Theme.oliveDeep], center: .top, startRadius: 20, endRadius: 420)
                    Image(systemName: act.1).font(.system(size: 230, weight: .bold)).foregroundStyle(Theme.sand.opacity(0.07))
                        .rotationEffect(.degrees(-12)).offset(x: 90, y: 40)
                        .id(pick).transition(.opacity.combined(with: .scale(scale: 0.85)))
                    LinearGradient(colors: [.black.opacity(0.3), .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipped()
            .ignoresSafeArea(edges: .top)
            .animation(.easeInOut(duration: 0.35), value: pick)
    }

    private var title: some View {
        VStack(spacing: 4) {
            Text("ПОБАЧЕННЯ").font(.system(size: 13, weight: .bold)).tracking(2.6).foregroundStyle(Theme.paper)
            Text(act.2.uppercased())
                .font(.system(size: 64, weight: .bold)).tracking(-2.5).foregroundStyle(Theme.sand).lineLimit(1).minimumScaleFactor(0.6)
            Text(film.map { "\($0.title) · Multiplex" } ?? (pick == "cinema" ? "Multiplex «Паннонія»" : "\(state.me?.name ?? "") і \(state.partner?.name ?? "")"))
                .font(.system(size: 13, weight: .bold)).tracking(1.4).textCase(.uppercase).foregroundStyle(Theme.paper).lineLimit(1).padding(.horizontal, 20)
        }
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: pick)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(acts, id: \.0) { a in chip(a.0, a.1, a.2) }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(_ id: String, _ icon: String, _ text: String) -> some View {
        Button {
            withAnimation(.snappy) { pick = id; time = nil; day = "" }
            Task { await afterPick() }
        } label: {
            Label(text, systemImage: icon).lineLimit(1).font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16).frame(height: 42).frame(maxWidth: 200)
                .background(pick == id ? AnyShapeStyle(Theme.sand) : AnyShapeStyle(.white.opacity(0.2)), in: Capsule())
                .foregroundStyle(pick == id ? Theme.ink : Theme.paper)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            if pick == "cinema" { filmPicker }
            HStack {
                Label("Оберіть день", systemImage: "calendar").font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: 0x6F695E))
                Spacer()
                Text(filmSessions?.isEmpty == false ? "бліді — без сеансів" : "♥ — обоє вільні").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(days, id: \.self) { d in dayTile(d).id(d) } }.padding(.horizontal, 18).padding(.vertical, 3)
                }
                .padding(.horizontal, -18)
                .onChange(of: day) { _, d in withAnimation { proxy.scrollTo(d, anchor: .leading) } }
            }
            if let f = film {
                Label("Сеанс у Multiplex «Паннонія»", systemImage: "film").font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: 0x6F695E))
                if let all = sessions[f.id] {
                    let today = all.filter { $0.date == day }
                    if today.isEmpty {
                        Text(all.isEmpty ? "Цього фільму зараз нема в афіші Паннонії — обери день і час самі." : "Цього дня сеансів нема")
                            .font(.system(size: 14)).foregroundStyle(Theme.muted)
                        if all.isEmpty { stepper }
                    } else {
                        FlowRow(items: today) { s in
                            Button { time = s.time } label: {
                                HStack(spacing: 5) {
                                    Text(s.time).font(.system(size: 16, weight: .medium))
                                    if !s.tags.isEmpty { Text(s.tags.joined(separator: " ")).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.coffee) }
                                }
                                .padding(.horizontal, 15).frame(height: 44)
                                .background(time == s.time ? Theme.paper : Theme.tan.opacity(0.5), in: RoundedRectangle(cornerRadius: 15))
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.ink, lineWidth: time == s.time ? 1.6 : 0))
                            }
                            .foregroundStyle(Theme.ink)
                        }
                    }
                } else {
                    ProgressView().tint(Theme.olive)
                }
            } else {
                Label("Коли приходимо", systemImage: "clock").font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: 0x6F695E))
                stepper
                if pick == "own" { TextField("Що робимо?", text: $custom).field() }
                if pick != "cinema" { TextField("Де (необов'язково)", text: $place).field() }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Підтверджує").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    HStack(spacing: 8) { Avatar(member: state.partner, size: 26); Text(state.partner?.name ?? "").font(.system(size: 18, weight: .semibold)) }
                }
                Spacer()
                Button { Task { await send() } } label: {
                    Group { if busy { ProgressView().tint(Theme.paper) } else { Text("Надіслати запит") } }
                        .font(.system(size: 16, weight: .semibold)).padding(.horizontal, 24).frame(height: 56)
                        .background(Theme.ink, in: Capsule()).foregroundStyle(Theme.paper)
                }
                .disabled(busy)
            }
            .padding(.top, 4)
            if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coffee) }
            Text("\(state.partner?.name ?? "") відповість «Йдемо» або «Інший день»\(film != nil ? ". Після «Йдемо» — кнопка «Купити квитки»" : "").")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18).padding(.vertical, 20)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 38, style: .continuous))
        .padding(.horizontal, 12)
        .foregroundStyle(Theme.ink)
    }

    /// Films from «Хочемо»: tap one to see its sessions, tap it again to go without a film.
    private var filmPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Який фільм", systemImage: "popcorn").font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: 0x6F695E))
                Spacer()
                Text(film == nil ? "можна й без" : "ще раз — зняти").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            }
            if movies.isEmpty {
                Text("У «Хочемо» нема фільмів — обери день і час, фільм вирішите там.").font(.system(size: 14)).foregroundStyle(Theme.muted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(movies) { m in filmTile(m) }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.horizontal, -18)
            }
        }
    }

    private func filmTile(_ m: WatchItem) -> some View {
        let on = filmId == m.id
        return Button {
            withAnimation(.snappy) { filmId = on ? nil : m.id; time = nil; day = "" }
            Task { await afterPick() }
        } label: {
            VStack(spacing: 6) {
                Color.clear.frame(width: 64, height: 92)
                    .overlay { RemoteImage(url: m.posterUrl ?? m.backdropUrl) }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.ink, lineWidth: on ? 2 : 0))
                Text(m.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: 74, height: 30, alignment: .top)
            }
            .opacity(filmId == nil || on ? 1 : 0.5)
        }
        .foregroundStyle(Theme.ink)
    }

    private var stepper: some View {
        HStack(spacing: 10) {
            Button { arrival = max(6 * 60, arrival - 15) } label: { Image(systemName: "minus").frame(width: 46, height: 44).background(Theme.tan.opacity(0.5), in: RoundedRectangle(cornerRadius: 15)) }
            Text(String(format: "%02d:%02d", arrival / 60, arrival % 60)).font(.system(size: 30, weight: .medium)).monospacedDigit().frame(minWidth: 100)
            Button { arrival = min(23 * 60 + 45, arrival + 15) } label: { Image(systemName: "plus").frame(width: 46, height: 44).background(Theme.tan.opacity(0.5), in: RoundedRectangle(cornerRadius: 15)) }
        }
        .foregroundStyle(Theme.ink)
    }

    private var days: [String] {
        (0..<35).compactMap { cal.date(byAdding: .day, value: $0, to: Date()) }.map { Evening.iso($0) }
    }

    private func dayTile(_ d: String) -> some View {
        let date = Evening.date(d) ?? Date()
        let plan = avail.first { $0.date == d }
        let off: Bool = {
            guard let f = film, let s = sessions[f.id], !s.isEmpty else { return false }
            return !s.contains { $0.date == d }
        }()
        return Button { day = d; time = nil } label: {
            VStack(spacing: 6) {
                Text("\(cal.component(.day, from: date))").font(.system(size: 29, weight: .medium))
                Text(date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "uk_UA")))).font(.system(size: 13)).foregroundStyle(day == d ? Theme.paper.opacity(0.7) : Theme.muted)
            }
            .frame(width: 66, height: 84)
            .foregroundStyle(day == d ? Theme.paper : Theme.ink)
            .background(day == d ? Theme.ink : Theme.tan.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.coffee, lineWidth: d == Evening.iso(Date()) && day != d ? 1.5 : 0))
            .overlay(alignment: .bottom) { if filmSessions?.isEmpty != false, plan?.bothFree == true { Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(day == d ? Color(hex: 0xB9CC98) : Theme.olive).padding(.bottom, 6) } }
            .opacity(off ? 0.35 : 1)
        }
        .disabled(off)
        .buttonStyle(.plain)
    }

    private func setup() async {
        switch start {
        case .film(let id): pick = "cinema"; filmId = id
        case .day(let d): pick = "dinner"; day = d
        case .blank: pick = "cinema"
        }
        let today = Evening.iso(Date())
        let end = Evening.iso(cal.date(byAdding: .day, value: 34, to: Date()) ?? Date())
        avail = (try? await API.current().availability(from: today, to: end)) ?? []
        await afterPick()
    }

    private func afterPick() async {
        if let f = film {
            if sessions[f.id] == nil { sessions[f.id] = (try? await API.current().sessions(watchId: f.id)) ?? [] }
            if day.isEmpty { day = sessions[f.id]?.first?.date ?? Evening.iso(Date()) }
        } else if day.isEmpty {
            day = avail.first { $0.isFree }?.date ?? Evening.iso(Date())
        }
    }

    private func send() async {
        busy = true; defer { busy = false }
        let f = film
        let session = f.flatMap { sessions[$0.id]?.first { $0.date == day && $0.time == time } }
        if let f, let all = sessions[f.id], !all.isEmpty, session == nil { error = "Обери сеанс"; return }
        let t = session?.time ?? String(format: "%02d:%02d", arrival / 60, arrival % 60)
        let hm = t.split(separator: ":").compactMap { Int($0) }
        guard let base = Evening.date(day), hm.count == 2,
              let startsAt = cal.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: base) else { return }
        let title: String = f.map { "Кіно: \($0.title)" } ?? (pick == "own" ? custom.trimmingCharacters(in: .whitespaces) : act.2)
        if title.isEmpty { error = "Напиши, що робимо"; return }
        var d = EventDraft(ownerId: nil, title: title, startsAt: startsAt, endsAt: nil, place: pick == "cinema" ? "Multiplex «Паннонія»" : (place.isEmpty ? nil : place),
                           mapUrl: nil, note: nil, dress: nil, message: nil)
        d.watchId = f?.id
        d.buyUrl = session?.buyUrl
        let ok = await store.run { let e = try await API.current().createInvitation(d); store.upsert(e) }
        if ok { dismiss() } else { error = store.error }
    }
}

/// Wrapping row of buttons (session times).
struct FlowRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder var content: (Item) -> Content
    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 4).map { Array(items[$0..<min($0 + 4, items.count)]) }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) { ForEach(row) { content($0) } }
            }
        }
    }
}

/// Фінанси: monobank jars (read-only) and our common goal.
struct FinancePage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL
    @State private var data: FinanceResult?
    @State private var editGoal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(data?.goal?.title ?? "Наші фінанси").font(.system(size: 34, weight: .medium)).padding(.top, 70).padding(.horizontal, 22)
                Text(data?.goal != nil ? "Збираємо разом" : "Банки monobank і спільна ціль").font(.system(size: 14)).opacity(0.75).padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 26)
                budget
                if let d = data, d.connected {
                    VStack(spacing: 8) {
                        if d.error != nil { jarRow("monobank зараз не відповідає", "спробуй пізніше", nil, nil) }
                        ForEach(d.jars) { j in
                            Button { if let u = j.topUpUrl?.asURL { openURL(u) } } label: {
                                jarRow(j.title, j.goal.map { "ціль \(Int($0)) ₴ · тап — поповнити в monobank" } ?? "тап — поповнити в monobank", j.balance, j.topUpUrl)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
            }
            .padding(.bottom, 120)
        }
        .background(RadialGradient(colors: [Color(hex: 0xD9C9B4), Color(hex: 0xC3AD91), Color(hex: 0x8D7559)], center: .init(x: 0.7, y: 0.1), startRadius: 10, endRadius: 700).ignoresSafeArea())
        .foregroundStyle(Color(hex: 0x2A241C))
        .task { data = try? await API.current().finance() }
        .sheet(isPresented: $editGoal, onDismiss: { Task { data = try? await API.current().finance() } }) { GoalSheet(jars: data?.jars ?? [], goal: data?.goal) }
    }

    private var budget: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(data?.connected == false ? "monobank не підключено" : "Наша ціль", systemImage: data?.connected == false ? "powerplug" : "checkmark.circle.fill")
                .font(.system(size: 14)).opacity(0.85)
            if data?.connected == false {
                Text("Щоб бачити банки, \(state.me?.name ?? "") створює особистий токен на api.monobank.ua і кладе його на сервер (не в чат). Токен лише читає суми банок і цілі. Гроші переказуються тільки в застосунку monobank.")
                    .font(.system(size: 14)).opacity(0.8)
            } else if let g = data?.goal {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(g.saved >= 1000 ? String(format: "%.1fk", g.saved / 1000) : "\(Int(g.saved))").font(.system(size: 56, weight: .medium))
                    Text("з \(Int(g.target)) ₴").font(.system(size: 15)).opacity(0.7)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x3A3631))
                        RoundedRectangle(cornerRadius: 12).fill(Theme.paper).frame(width: max(48, geo.size.width * CGFloat(g.percent) / 100))
                            .overlay(alignment: .leading) { Text("\(g.percent)%").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).padding(.leading, 12) }
                    }
                }
                .frame(height: 40)
            } else if data != nil {
                Text("Ціль ще не задана.").opacity(0.8)
            }
            if data?.connected == true {
                HStack { Spacer(); Button(data?.goal == nil ? "Задати ціль" : "Змінити ціль") { editGoal = true }.font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 6).overlay(Capsule().stroke(.white.opacity(0.4))) }
            }
        }
        .padding(18)
        .background(Color(hex: 0x1F1D1A), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .foregroundStyle(Color(hex: 0xF4EFE6))
        .padding(.horizontal, 12)
    }

    private func jarRow(_ t: String, _ s: String, _ v: Double?, _ link: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "dollarsign.circle.fill").font(.system(size: 22)).frame(width: 44, height: 44)
                .background(Theme.coffee, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Theme.cream)
            VStack(alignment: .leading, spacing: 2) { Text(t).font(.system(size: 15, weight: .semibold)); Text(s).font(.system(size: 12.5)).foregroundStyle(Theme.muted) }
            Spacer()
            if let v { Text("\(Int(v)) ₴").font(.system(size: 15, weight: .semibold)) }
        }
        .padding(12).background(Theme.paper.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(Theme.ink)
    }
}

struct GoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let jars: [Jar]
    let goal: FinanceGoal?
    @State private var title = ""
    @State private var target = ""
    @State private var chosen: Set<String> = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            SoftForm {
                Section { TextField("Назва (Відпустка в Карпатах)", text: $title); TextField("Скільки треба, ₴", text: $target).keyboardType(.numberPad) }
                Section("З яких банок рахувати") {
                    ForEach(jars) { j in
                        Button { if chosen.contains(j.id) { chosen.remove(j.id) } else { chosen.insert(j.id) } } label: {
                            HStack { Text(j.title); Spacer(); Text("\(Int(j.balance)) ₴").foregroundStyle(Theme.muted); Image(systemName: chosen.contains(j.id) ? "checkmark.circle.fill" : "circle") }
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
                if let error { Text(error).foregroundStyle(Theme.coffee) }
            }
            .navigationTitle("Спільна ціль").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save() } } }
            }
            .onAppear { title = goal?.title ?? ""; target = goal.map { String(Int($0.target)) } ?? ""; chosen = Set(goal?.jarIds ?? []) }
        }
        .tint(Theme.olive)
    }

    private func save() async {
        do { try await API.current().setGoal(.init(title: title, target: Double(target) ?? 0, jarIds: Array(chosen))); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

/// «В»: who we are and shortcuts to settings, finance, games.
struct MePage: View {
    @EnvironmentObject var state: AppState
    @Binding var page: Page
    var openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageTitle(plain: state.me?.name ?? "", italic: "& \(state.partner?.name ?? "")", sub: "Разом у DaVincit")
                row("gearshape.fill", "Налаштування", "ім'я, код пари, перевірка острівця", openSettings)
                row("dollarsign.circle.fill", "Фінанси", "банки monobank і спільна ціль") { page = .finance }
                row("gamecontroller.fill", "Ігри", "згодом") { page = .games }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 120)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }

    private func row(_ icon: String, _ t: String, _ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 22)).frame(width: 44, height: 44).background(Theme.tan, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Theme.olive)
                VStack(alignment: .leading, spacing: 2) { Text(t).font(.system(size: 15, weight: .semibold)); Text(s).font(.system(size: 12.5)).foregroundStyle(Theme.muted) }
                Spacer()
            }
            .padding(10).background(Theme.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
