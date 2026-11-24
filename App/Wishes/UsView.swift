import SwiftUI

/// «Ми»: wishes of both (grid like Goodsend) + settings. Codex, goals and the intimate part come in later waves.
struct UsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Binding var route: Route?
    @Binding var who: String
    @State private var showBought = false
    @State private var open: Wish?
    @State private var showSettings = false

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    @State private var cat: String?

    var body: some View {
        ZStack(alignment: .top) {
            Theme.cream.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Наші бажання").font(.serif(34, .bold))
                        Spacer()
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").font(.system(size: 17))
                                .frame(width: 44, height: 44).background(Theme.olive.opacity(0.12), in: Circle())
                        }
                        .accessibilityLabel("Налаштування")
                    }
                    HStack(spacing: 8) {
                        if let p = state.partner { personChip(p) }
                        if let m = state.me { personChip(m) }
                        Spacer()
                        Button { showBought.toggle(); cat = nil } label: { Chip(text: "Куплене", selected: showBought) }.buttonStyle(.plain)
                    }
                    let mine = items
                    let cats = Wish.categories.filter { c in mine.contains { $0.cat == c.0 } }
                    if cats.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                catChip(nil, "Усе")
                                ForEach(cats, id: \.0) { c in catChip(c.0, c.1) }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.horizontal, -16)
                    }
                    let list = cat.map { c in mine.filter { $0.cat == c } } ?? mine
                    if list.isEmpty {
                        let wanting = store.wishes.filter { $0.ownerId == who && $0.status != "bought" }.count
                        if showBought {
                            Button { if wanting > 0 { showBought = false } else { route = .wish } } label: {
                                MuseumTile(fill: Theme.paper, tag: "Поки порожньо", title: "Ще нічого не", underlined: "куплено.",
                                           meta: wanting > 0 ? "Купили щось із бажань? Відкрий його й натисни «Куплено» — воно переїде сюди. У бажаннях зараз: \(wanting)." : "Тут будуть куплені бажання.",
                                           footer: wanting > 0 ? "До бажань" : "Додати бажання")
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button { route = .wish } label: {
                                MuseumTile(fill: Theme.paper, tag: "Порожньо", title: "Додай перше", underlined: "бажання.",
                                           meta: "Посилання з будь-якого магазину — назва, фото й ціна підтягнуться самі",
                                           footer: "Додати")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(list) { w in
                            Button { open = w } label: { WishCard(wish: w) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
            .refreshable { await store.refreshAll() }
        }
        .foregroundStyle(Theme.ink)
        .onAppear { if who.isEmpty { who = state.partner?.id ?? "" } }
        .sheet(item: $open) { w in WishDetailView(wish: w) }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func catChip(_ k: String?, _ l: String) -> some View {
        Button { cat = k } label: {
            Text(l).font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 13).frame(height: 34)
                .background(cat == k ? Theme.ink : Theme.tan.opacity(0.6), in: Capsule())
                .foregroundStyle(cat == k ? Theme.paper : Theme.ink)
        }
        .buttonStyle(.plain)
    }

    private var items: [Wish] {
        store.wishes.filter { $0.ownerId == who && ($0.status == "bought") == showBought }
    }

    private func personChip(_ m: Member) -> some View {
        Button { who = m.id } label: {
            HStack(spacing: 6) {
                Avatar(member: m, size: 24)
                Text(m.id == state.me?.id ? "Мої" : m.name)
            }
            .font(.system(size: 14, weight: who == m.id ? .semibold : .medium))
            .padding(.leading, 5).padding(.trailing, 14).frame(height: 36)
            .background(who == m.id ? Theme.olive.opacity(0.18) : Theme.olive.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(who == m.id ? Theme.olive : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

struct WishCard: View {
    let wish: Wish
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                RemoteImage(url: wish.imageUrl, contentMode: .fit)
                    .padding(14)
                    .frame(height: 150).frame(maxWidth: .infinity)
                HStack {
                    if let d = wish.dropPercent {
                        Label("\(d)%", systemImage: "arrow.down").font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                    }
                    Spacer()
                    if let p = wish.priceText {
                        Text(p).font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Theme.muted.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                    }
                }
                .padding(10)
            }
            Text(wish.title).font(.system(size: 14.5, weight: .semibold)).lineLimit(2)
                .padding(.horizontal, 14).padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 214, alignment: .top)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct WishDetailView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State var wish: Wish
    @State private var confirmDelete = false

    init(wish: Wish) { _wish = State(initialValue: wish) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RemoteImage(url: wish.imageUrl, contentMode: .fit)
                    .frame(height: 300).frame(maxWidth: .infinity)
                    .background(Theme.cream, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                Text(wish.title).font(.serif(26, .bold))
                if let p = wish.priceText {
                    HStack(spacing: 8) {
                        Text(p).font(.system(size: 22, weight: .bold))
                        if let d = wish.dropPercent, let fp = wish.firstPrice {
                            Text("було \(fp.formatted(.number.precision(.fractionLength(0...2)))) · −\(d)%").font(.system(size: 14)).foregroundStyle(Theme.olive)
                        }
                    }
                }
                if let n = wish.note { Text(n).font(.system(size: 15)).foregroundStyle(Theme.muted) }
                Text("Категорія").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Wish.categories, id: \.0) { c in
                            Button { Task { await setCategory(c.0) } } label: {
                                Text(c.1).font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 13).frame(height: 34)
                                    .background(wish.cat == c.0 ? Theme.olive : Theme.tan.opacity(0.6), in: Capsule())
                                    .foregroundStyle(wish.cat == c.0 ? Theme.cream : Theme.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let u = wish.url?.asURL {
                    Button { openURL(u) } label: {
                        Label("Відкрити в магазині", systemImage: "safari").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(fill: Theme.olive, text: Theme.cream))
                }
                Button {
                    Task { await setStatus(wish.status == "bought" ? "want" : "bought") }
                } label: {
                    Label(wish.status == "bought" ? "Повернути в бажання" : "Куплено", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(fill: Theme.coffee, text: Theme.cream))
                Button("Видалити", role: .destructive) { confirmDelete = true }
                if let e = store.error { Text(e).foregroundStyle(Theme.coffee) }
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .confirmationDialog("Видалити бажання?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Видалити", role: .destructive) { Task { await remove() } }
        }
    }

    private func setCategory(_ c: String) async {
        await store.run { let w = try await API.current().patchWish(wish.id, .init(category: c)); wish = w; store.upsert(w) }
    }

    private func setStatus(_ s: String) async {
        await store.run { let w = try await API.current().patchWish(wish.id, .init(status: s)); wish = w; store.upsert(w) }
    }
    private func remove() async {
        let ok = await store.run {
            try await API.current().deleteWish(wish.id)
            store.wishes.removeAll { $0.id == wish.id }
        }
        if ok { dismiss() }
    }
}

/// Add a wish by link (or by hand).
struct WishEditor: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var title = ""
    @State private var price = ""
    @State private var note = ""
    @State private var forMe = true
    @State private var busy = false

    var body: some View {
        NavigationStack {
            SoftForm {
                Section {
                    TextField("Посилання на товар", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: { Text("Назва, фото й ціна підтягнуться з сайту самі.") }
                Section {
                    Picker("Чиє", selection: $forMe) {
                        Text("Моє").tag(true)
                        Text(state.partner?.name ?? "Партнера").tag(false)
                    }
                    .pickerStyle(.segmented)
                    TextField("Назва (якщо без посилання)", text: $title)
                    TextField("Ціна, ₴ (необов'язково)", text: $price).keyboardType(.decimalPad)
                    TextField("Нотатка", text: $note)
                }
                if let e = store.error { Section { Text(e).foregroundStyle(Theme.coffee) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle("Бажання")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Додати") { Task { await save() } }
                        .disabled(busy || (url.isEmpty && title.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
            .overlay { if busy { ProgressView("Дивлюсь сторінку…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
    }

    private func save() async {
        busy = true; defer { busy = false }
        let body = API.WishBody(url: url.isEmpty ? nil : url.trimmingCharacters(in: .whitespaces),
                                title: title.isEmpty ? nil : title,
                                price: Double(price.replacingOccurrences(of: ",", with: ".")),
                                note: note.isEmpty ? nil : note,
                                ownerId: forMe ? state.me?.id : state.partner?.id)
        if await store.run({ store.upsert(try await API.current().addWish(body)) }) { dismiss() }
    }
}
