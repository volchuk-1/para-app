import SwiftUI

// MARK: - Wave 8: «Змінити Головну» as a whole screen, the mood bubble, a 3D coin, «Натхнення» side by side,
// notifications out of the bell, the second page of Головна (the day as a calm list).

/// kinds of widget faces: name, SF symbol, the tile colour of the list
enum FaceKind {
    static let all: [(String, String, String, UInt32)] = [
        ("card", "Натхнення", "sparkles", 0x2F3A24), ("tasks", "Справи", "checklist", 0x2B1B14), ("event", "Подія", "calendar", 0x4B5E3A),
        ("evening", "Вечір", "moon.stars.fill", 0x80513A), ("film", "Фільм", "film.fill", 0x211F1D), ("turn", "Чия черга", "arrow.left.arrow.right", 0x8C5E3C),
        ("pomodoro", "Фокус", "timer", 0x000000), ("note", "Записка", "note.text", 0xA59E91), ("coin", "Монетка", "circle.circle.fill", 0xB98A2E),
        ("jar", "Банка", "banknote.fill", 0xC9A27E), ("memory", "Спогад", "photo.fill", 0x5E5C50), ("spotify", "Spotify", "music.note", 0x1DB954),
    ]
    static func name(_ k: String) -> String { all.first { $0.0 == k }?.1 ?? k }
    static func icon(_ k: String) -> String { all.first { $0.0 == k }?.2 ?? "square" }
    static func color(_ k: String) -> Color { Color(hex: all.first { $0.0 == k }?.3 ?? 0x555555) }
}

/// A small coloured square with a symbol, like in the Settings of iPhone.
struct IconTile: View {
    let icon: String
    let color: Color
    var body: some View {
        Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 30, height: 30).background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct HomeEditView: View {
    @State var layout: [DashWidget]
    var startWith: String? = nil
    var onDone: ([DashWidget]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []
    @State private var saving = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Text("Перемикач — показати чи сховати. Тягни за ≡, щоб змінити порядок. Тап на назву — розмір, стос і кольори.")
                        .font(.system(size: 13.5)).foregroundStyle(Theme.muted).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                }
                Section("На Головній") {
                    ForEach(layout) { w in
                        HStack(spacing: 12) {
                            IconTile(icon: FaceKind.icon(w.faces.first ?? ""), color: FaceKind.color(w.faces.first ?? ""))
                            Button { path.append(w.id) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(w.faces.map(FaceKind.name).joined(separator: " · ")).font(.system(size: 15.5, weight: .medium)).lineLimit(1)
                                    Text(sizeName(w.size) + (w.faces.count > 1 ? " · стос із \(w.faces.count)" : "") + " · налаштувати ›").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Toggle("", isOn: Binding(get: { true }, set: { on in if !on { remove(w.id) } })).labelsHidden().tint(Theme.olive)
                        }
                    }
                    .onMove { from, to in layout.move(fromOffsets: from, toOffset: to); Haptic.hit(.light); Task { await save() } }
                }
                let used = Set(layout.flatMap(\.faces))
                let free = FaceKind.all.filter { !used.contains($0.0) }
                if !free.isEmpty {
                    Section("Можна додати") {
                        ForEach(free, id: \.0) { k in
                            HStack(spacing: 12) {
                                IconTile(icon: k.2, color: Color(hex: k.3))
                                Text(k.1).font(.system(size: 15.5, weight: .medium))
                                Spacer()
                                Button { add(k.0) } label: {
                                    Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 30, height: 30).background(Theme.olive, in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section {
                    Text("Друга сторінка Головної (гортай убік) — день списком: події, справи, що дивитесь і слухаєте.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(LinearGradient(colors: [Color(hex: 0xEFE9DC), Theme.cream], startPoint: .top, endPoint: .center).ignoresSafeArea())
            .navigationTitle("Змінити Головну")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { close() } label: { Label("Головна", systemImage: "chevron.left") } }
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { close() }.fontWeight(.semibold) }
            }
            .navigationDestination(for: String.self) { id in
                WidgetDetailView(layout: $layout, id: id) { Task { await save() } }
            }
        }
        .tint(Theme.olive)
        .onAppear { if let s = startWith, path.isEmpty { path = [s] } }
    }

    private func sizeName(_ s: String) -> String { s == "l" ? "Великий" : s == "m" ? "Середній" : "Малий" }
    private func remove(_ id: String) { withAnimation(.snappy) { layout.removeAll { $0.id == id } }; Haptic.hit(.light); Task { await save() } }
    private func add(_ k: String) {
        withAnimation(.snappy) { layout.append(DashWidget(id: "w\(Int(Date().timeIntervalSince1970))", size: k == "spotify" || k == "card" ? "m" : "s", faces: [k])) }
        Haptic.hit(.medium); Task { await save() }
    }
    private func save() async { if let l = try? await API.current().setLayout(layout) { layout = l } }
    private func close() { onDone(layout); dismiss() }
}

struct WidgetDetailView: View {
    @Binding var layout: [DashWidget]
    let id: String
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var askRemove = false
    private let swatch: [UInt32] = [0x4B5E3A, 0x80513A, 0xE2C7A7, 0x2B1B14, 0xC7CABC, 0xF2EEE2, 0x000000, 0xDCE3CF, 0xC9A27E, 0xFFFFFF]

    private var idx: Int? { layout.firstIndex { $0.id == id } }

    var body: some View {
        List {
            if let i = idx {
                Section("Розмір") {
                    Picker("Розмір", selection: Binding(get: { layout[i].size }, set: { layout[i].size = $0; onChange() })) {
                        Text("Малий").tag("s"); Text("Середній").tag("m"); Text("Великий").tag("l")
                    }
                    .pickerStyle(.segmented).listRowBackground(Color.clear)
                }
                Section("Що показує · кілька — гортаються стосом") {
                    ForEach(FaceKind.all, id: \.0) { k in
                        HStack(spacing: 12) {
                            IconTile(icon: k.2, color: Color(hex: k.3))
                            Text(k.1).font(.system(size: 15.5))
                            Spacer()
                            Toggle("", isOn: Binding(get: { layout[i].faces.contains(k.0) }, set: { on in
                                if on { layout[i].faces.append(k.0) } else if layout[i].faces.count > 1 { layout[i].faces.removeAll { $0 == k.0 } }
                                Haptic.hit(.light); onChange()
                            }))
                            .labelsHidden().tint(Theme.olive)
                        }
                    }
                }
                Section("Кольори") {
                    colorRow("Фон", \.bg, i); colorRow("Текст", \.fg, i); colorRow("Акцент", \.ac, i)
                    Button("Стандартні кольори") { layout[i].colors = nil; onChange() }
                }
                Section {
                    Button("Прибрати з Головної", role: .destructive) { askRemove = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.cream.ignoresSafeArea())
        .navigationTitle(idx.map { layout[$0].faces.map(FaceKind.name).joined(separator: " · ") } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Прибрати цей віджет з Головної?", isPresented: $askRemove, titleVisibility: .visible) {
            Button("Прибрати", role: .destructive) { layout.removeAll { $0.id == id }; onChange(); dismiss() }
        }
    }

    private func colorRow(_ label: String, _ key: WritableKeyPath<WidgetColors, String?>, _ i: Int) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted).frame(width: 56, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(swatch, id: \.self) { h in
                        let hex = String(format: "#%06x", h)
                        let on = layout[i].colors?[keyPath: key] == hex
                        Circle().fill(Color(hex: h)).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Theme.ink.opacity(0.15), lineWidth: 1))
                            .overlay(Circle().stroke(Theme.ink, lineWidth: on ? 2 : 0).padding(-3))
                            .onTapGesture {
                                var c = layout[i].colors ?? WidgetColors()
                                c[keyPath: key] = hex
                                layout[i].colors = c
                                Haptic.hit(.light); onChange()
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - the mood bubble: it grows out of the mood button; hold and slide over the faces, let go

struct MoodBubble: View {
    @Binding var shown: Bool
    var partnerMood: MoodState?
    var partner: String
    @Binding var hot: String?
    var onPick: (String) -> Void
    var onTouch: (String) -> Void
    @State private var own = ""
    @State private var typing = false
    static let moods = ["😊", "🥰", "😴", "🤒", "😤", "🥳"]
    private var recent: [String] { (UserDefaults.standard.stringArray(forKey: "dv-moods") ?? []).filter { !Self.moods.contains($0) }.prefix(4).map { $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("МІЙ НАСТРІЙ — ВЕДИ ПАЛЬЦЕМ, ВІДПУСТИ").font(.system(size: 10.5, weight: .bold)).tracking(1).foregroundStyle(Theme.muted)
            HStack {
                ForEach(Self.moods, id: \.self) { m in
                    Text(m).font(.system(size: 26)).frame(width: 44, height: 44)
                        .background(hot == m ? Color.white : .clear, in: Circle())
                        .shadow(color: .black.opacity(hot == m ? 0.15 : 0), radius: 8, y: 4)
                        .scaleEffect(hot == m ? 1.4 : 1).offset(y: hot == m ? -8 : 0)
                        .background(GeometryReader { g in Color.clear.preference(key: MoodFrames.self, value: [m: g.frame(in: .global)]) })
                        .onTapGesture { onPick(m) }
                    if m != Self.moods.last { Spacer(minLength: 0) }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hot)
            Text("НЕДАВНІ").font(.system(size: 10.5, weight: .bold)).tracking(1).foregroundStyle(Theme.muted).padding(.top, 4)
            HStack(spacing: 6) {
                ForEach(recent, id: \.self) { m in Text(m).font(.system(size: 26)).frame(width: 44, height: 44).onTapGesture { onPick(m) } }
                if typing {
                    TextField("Свій смайлик", text: $own).font(.system(size: 20)).multilineTextAlignment(.center).frame(height: 40)
                        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 12)).onSubmit { if !own.isEmpty { onPick(own) } }
                } else {
                    Button { typing = true } label: { Image(systemName: "plus").font(.system(size: 15, weight: .bold)).frame(width: 44, height: 44).background(Theme.tan, in: Circle()) }.buttonStyle(.plain)
                }
            }
            if let p = partnerMood {
                HStack(spacing: 8) {
                    Text(p.emoji).font(.system(size: 20))
                    Text("\(partner) · \(p.at.shortTime)").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 6)
            }
            HStack(spacing: 6) {
                touch("heart.fill", "Думаю про тебе", "think")
                touch("hand.raised.fill", "Скучаю", "miss")
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(Theme.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.25), radius: 30, y: 16)
    }

    private func touch(_ icon: String, _ label: String, _ k: String) -> some View {
        Button { onTouch(k) } label: {
            Label(label, systemImage: icon).font(.system(size: 12.5, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 40)
                .background(Theme.tan, in: Capsule()).foregroundStyle(Theme.ink)
        }
        .buttonStyle(PressScale())
    }
}

struct MoodFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

// MARK: - the coin: gold, with an edge; thrown up, it spins and lands on one of us

struct Coin3DView: View {
    let me: String
    let partner: String
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @State private var angle = 0.0
    @State private var lift: CGFloat = 0
    @State private var result: String?
    @State private var flying = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x3A3027), Color(hex: 0x17120E)], center: .init(x: 0.5, y: 0.42), startRadius: 10, endRadius: 520).ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 42, height: 42).background(.white.opacity(0.1), in: Circle()) }
                    Spacer()
                }
                TextField("", text: $q, prompt: Text("Питання").foregroundColor(Color(hex: 0xF2EEE2).opacity(0.45)))
                    .multilineTextAlignment(.center).font(.system(size: 17)).frame(height: 50)
                    .background(.white.opacity(0.08), in: Capsule())
                Spacer()
                ZStack {
                    Ellipse().fill(RadialGradient(colors: [.black.opacity(0.55), .clear], center: .center, startRadius: 2, endRadius: 80))
                        .frame(width: 160, height: 22).scaleEffect(CGFloat(1) - lift / CGFloat(600)).opacity(Double(1 - lift / 700)).offset(y: 120)
                    coin.offset(y: -lift)
                }
                .frame(height: 320)
                Text(result ?? " ").font(.serif(26)).opacity(result == nil ? 0 : 1).animation(.easeOut, value: result)
                Spacer()
                Button { Task { await toss() } } label: {
                    Text("Підкинути").font(.system(size: 16, weight: .bold)).frame(maxWidth: .infinity).frame(height: 56)
                        .background(LinearGradient(colors: [Color(hex: 0xE8C062), Color(hex: 0xB98A2E)], startPoint: .top, endPoint: .bottom), in: Capsule())
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(PressScale()).disabled(flying)
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
            .foregroundStyle(Color(hex: 0xF2EEE2))
        }
    }

    /// the face that looks at us depends on the angle; the edge shows as the coin turns
    private var coin: some View {
        let a = angle.truncatingRemainder(dividingBy: 360)
        let back = a > 90 && a < 270
        let edge = abs(cos(angle * .pi / 180))
        return ZStack {
            ForEach(0..<6, id: \.self) { k in
                Circle().fill(Color(hex: 0x9B7428)).frame(width: 180, height: 180)
                    .offset(x: CGFloat(k) * 1.1 * (1 - edge) * (back ? -1 : 1))
            }
            face(back ? String(partner.prefix(1)) : String(me.prefix(1)), back ? partner : me)
                .scaleEffect(x: back ? -1 : 1)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(14), axis: (x: 1, y: 0, z: 0))
    }

    private func face(_ letter: String, _ name: String) -> some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: 0xFFF1C2), Color(hex: 0xE8C062), Color(hex: 0xB98A2E), Color(hex: 0x8C6420)], center: .init(x: 0.35, y: 0.3), startRadius: 2, endRadius: 120))
            Circle().strokeBorder(Color(hex: 0x8C6420).opacity(0.55), lineWidth: 10)
            Circle().strokeBorder(Color(hex: 0xFFECB4).opacity(0.6), lineWidth: 2).padding(10)
            Text(letter).font(.serif(72, .bold)).foregroundStyle(Color(hex: 0x7A5418)).shadow(color: Color(hex: 0xFFF0C8).opacity(0.8), radius: 0, y: 1)
            Text(name.uppercased()).font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(Color(hex: 0x7A5418)).opacity(0.8).offset(y: 52)
        }
        .frame(width: 180, height: 180)
    }

    private func toss() async {
        flying = true; result = nil
        Haptic.hit(.heavy)
        guard let r = try? await API.current().coin(q.trimmingCharacters(in: .whitespaces).isEmpty ? "Хто обирає?" : q) else { flying = false; return }
        let mine = r.winnerName == me
        let target = angle - angle.truncatingRemainder(dividingBy: 360) + 1800 + (mine ? 0 : 180)
        withAnimation(.easeOut(duration: 0.75)) { lift = 260 }
        withAnimation(.timingCurve(0.3, 0.6, 0.4, 1, duration: 1.7)) { angle = target }
        try? await Task.sleep(for: .milliseconds(750))
        withAnimation(.easeIn(duration: 0.8)) { lift = 0 }
        try? await Task.sleep(for: .milliseconds(950))
        Haptic.hit(.heavy)
        result = (mine ? "Ти" : r.winnerName) + (q.isEmpty ? "" : " — \(q)")
        flying = false
    }
}

// MARK: - «Натхнення»: cards side by side; a swipe slides them past the screen edge

struct CardsResult: Decodable { let today: DashCard?; let cards: [DashCard] }
extension API { func cards() async throws -> CardsResult { try await get("/cards") } }

struct CardsCarousel: View {
    let first: DashCard?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var cards: [DashCard] = []
    private let tints: [UInt32] = [0x2F3A24, 0x5A2230, 0x3B3C36]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { dismiss() }
            VStack {
                Spacer()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                            card(c, tint: Color(hex: tints[i % tints.count]))
                                .containerRelativeFrame(.horizontal) { w, _ in w * 0.78 }
                                .scrollTransition(.interactive, axis: .horizontal) { v, phase in
                                    v.rotationEffect(.degrees(phase.value * 6)).scaleEffect(1 - abs(phase.value) * 0.1).opacity(1 - abs(phase.value) * 0.25)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, UIScreen.main.bounds.width * 0.11, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .frame(height: min(460, UIScreen.main.bounds.height * 0.62))
                Spacer()
            }
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white).frame(width: 42, height: 42).background(.white.opacity(0.16), in: Circle()) }
                .padding(.leading, 16).padding(.top, 8)
        }
        .presentationBackground(.ultraThinMaterial)
        .task {
            if let r = try? await API.current().cards() {
                let all = r.cards
                if let f = first ?? r.today { cards = [f] + all.filter { $0.id != f.id } } else { cards = all }
            } else if let f = first { cards = [f] }
        }
    }

    private func card(_ c: DashCard, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x9DB27F), Color(hex: 0x3A4A2E)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let u = c.image { RemoteImage(url: u) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(c.tag.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.6).opacity(0.7)
                Text(c.title).font(.serif(23, .bold)).lineLimit(3)
                if !c.text.isEmpty { Text(c.text).font(.system(size: 13.5)).opacity(0.85).lineLimit(4) }
                if let u = c.url, let url = URL(string: u) {
                    Button { openURL(url) } label: {
                        Label(c.youtube != nil ? "Дивитись" : "Відкрити", systemImage: c.youtube != nil ? "play.rectangle.fill" : "arrow.up.right.square")
                            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).frame(height: 36).background(.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain).padding(.top, 4)
                }
            }
            .padding(16)
        }
        .foregroundStyle(Color(hex: 0xF3EEE6))
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
    }
}

// MARK: - notifications grow out of the bell

struct BellPanel: View {
    @EnvironmentObject var store: Store
    var onClose: () -> Void
    @State private var open = false

    var body: some View {
        GeometryReader { g in
            let bell = CGPoint(x: g.size.width - 16 - 23, y: 4 + 23)
            ZStack(alignment: .top) {
                Color.black.opacity(open ? 0.16 : 0).ignoresSafeArea().onTapGesture { close() }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Сповіщення").font(.serif(24, .bold)).padding(.leading, 4).padding(.bottom, 8).padding(.trailing, 60)
                    ScrollView {
                        VStack(spacing: 0) {
                            if store.notifications.isEmpty { Text("Поки тихо.").foregroundStyle(Theme.muted).padding(.vertical, 12) }
                            ForEach(Array(store.notifications.enumerated()), id: \.element.id) { i, n in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: icon(n.kind)).font(.system(size: 15)).foregroundStyle(.white).frame(width: 36, height: 36).background(color(n.kind), in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(n.title).font(.system(size: 14.5, weight: .semibold))
                                        if let b = n.body, !b.isEmpty { Text(b).font(.system(size: 12.5)).foregroundStyle(Theme.muted) }
                                    }
                                    Spacer(minLength: 4)
                                    Text(n.createdAt.formatted(.relative(presentation: .numeric).locale(Locale(identifier: "uk_UA")))).font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }
                                .padding(.vertical, 11).padding(.horizontal, 4)
                                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                                .opacity(open ? 1 : 0).offset(y: open ? 0 : -8)
                                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.1 + Double(i) * 0.05), value: open)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: min(620, g.size.height * 0.74), alignment: .top)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Theme.ink.opacity(0.3), radius: 30, y: 16)
                .mask {
                    Circle().frame(width: 46, height: 46).scaleEffect(open ? 40 : 1)
                        .position(x: bell.x - 12, y: bell.y)
                }
                .padding(.horizontal, 12)
            }
        }
        .task { withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.55)) { open = true }; await store.markNotificationsRead() }
    }

    private func close() {
        withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.45)) { open = false }
        Task { try? await Task.sleep(for: .milliseconds(430)); onClose() }
    }
    private func icon(_ k: String) -> String {
        switch k {
        case "invite": return "envelope.open.fill"
        case "invite_answer": return "checkmark.circle.fill"
        case "invite_cancel": return "xmark.circle.fill"
        case "event_new", "event_changed": return "calendar.badge.plus"
        case "wish_new": return "gift.fill"
        case "watch_new": return "popcorn.fill"
        case "price_drop": return "arrow.down.right"
        case "hour": return "alarm.fill"
        case "morning": return "sun.max.fill"
        default: return "bell.fill"
        }
    }
    private func color(_ k: String) -> Color {
        switch k {
        case "invite", "invite_answer": return Theme.olive
        case "invite_cancel": return Color(hex: 0xAA3333)
        case "event_new", "event_changed": return Theme.coffee
        case "wish_new": return Color(hex: 0xC8742A)
        case "watch_new": return Color(hex: 0x211F1D)
        default: return Color(hex: 0x6E8FB5)
        }
    }
}

// MARK: - Головна, page 2: the same day as a calm list

struct DashListPage: View {
    let d: Dashboard
    let spot: SpotNow?
    var onTasks: () -> Void
    var onFilm: (String) -> Void
    var onQuick: (String, String) -> Void
    var onNote: () -> Void
    var onEdit: () -> Void
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: AppState
    @State private var tasks: TaskDay?
    @State private var open = false
    @State private var ticked: Set<String> = []

    private var today: [Event] {
        let cal = Dock.calendar
        return store.events.filter { cal.isDateInToday($0.startsAt) && $0.invitation?.status != .cancelled }.sorted { $0.startsAt < $1.startsAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            todayTile
            tasksBlock
            if let w = d.watching?.first ?? d.film { watchRow(w) }
            if let s = spot, s.ready, let t = (s.partner?.track?.playing == true ? s.partner?.track : s.me.track) { spotRow(t, hers: t == s.partner?.track) }
            if let n = d.note {
                block {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color(hex: 0x6E8FB5))
                            Text(String((d.partner?.name ?? "?").prefix(1))).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            if let u = state.partner?.avatarUrl { AuthImage(url: u).clipShape(Circle()) }
                        }
                        .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 1) { Text(n.text.isEmpty ? "📷" : n.text).font(.system(size: 15, weight: .medium)); Text("записка").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                        Spacer()
                    }
                    .padding(14).contentShape(Rectangle()).onTapGesture { onNote() }
                }
            }
            Button { onEdit() } label: { Label("Змінити Головну", systemImage: "square.grid.2x2").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.muted) }
                .buttonStyle(.plain).frame(maxWidth: .infinity).padding(.top, 8)
        }
        .task { tasks = try? await API.current().tasks(Evening.iso(Date())) }
    }

    private func block<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c().frame(maxWidth: .infinity, alignment: .leading).background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func pos(_ d: Date) -> CGFloat {
        let c = Dock.calendar.dateComponents([.hour, .minute], from: d)
        return max(0, min(1, (CGFloat(c.hour ?? 0) + CGFloat(c.minute ?? 0) / 60 - 8) / 15))
    }

    private var todayTile: some View {
        let evs = today
        let next = evs.first { ($0.endsAt ?? $0.startsAt) > Date() }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("СЬОГОДНІ · " + (evs.isEmpty ? "ВІЛЬНО" : "\(evs.count) \(evs.count == 1 ? "ПОДІЯ" : evs.count < 5 ? "ПОДІЇ" : "ПОДІЙ")")).font(.system(size: 11, weight: .bold)).tracking(1.4).opacity(0.7)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).frame(width: 32, height: 32).background(.white.opacity(0.14), in: Circle())
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            Text(next?.title ?? "Вечір вільний").font(.system(size: 21, weight: .semibold))
            if let n = next { Text(n.startsAt.shortTime + (n.place.map { " · \($0)" } ?? "")).font(.system(size: 14)).opacity(0.8) }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.12))
                    ForEach(evs) { e in
                        let a = pos(e.startsAt), b = pos(e.endsAt ?? e.startsAt.addingTimeInterval(3600))
                        RoundedRectangle(cornerRadius: 6).fill(e.invitation != nil ? Theme.sand : .white.opacity(0.3))
                            .frame(width: max(8, (b - a) * g.size.width), height: 20).offset(x: a * g.size.width)
                    }
                    Rectangle().fill(.white).frame(width: 2).offset(x: pos(Date()) * g.size.width)
                }
            }
            .frame(height: 30).padding(.top, 8)
            HStack { ForEach(["8", "12", "16", "20", "23"], id: \.self) { Text($0); if $0 != "23" { Spacer() } } }.font(.system(size: 10)).opacity(0.6)
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(evs) { e in
                        HStack(spacing: 12) {
                            Text(e.startsAt.shortTime).font(.system(size: 13)).monospacedDigit().opacity(0.75).frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) { Text(e.title).font(.system(size: 15, weight: .semibold)); if let p = e.place { Text(p).font(.system(size: 12)).opacity(0.7) } }
                        }
                        .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.14)).frame(height: 1) }
                    }
                    HStack(spacing: 6) {
                        quick("cinema", "Кіно"); quick("home", "Вдома"); quick("walk", "Гуляти")
                    }
                    .padding(.top, 10)
                }
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Theme.olive, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .foregroundStyle(Theme.cream)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { open.toggle() }; Haptic.hit(.light) }
    }

    private func quick(_ k: String, _ label: String) -> some View {
        Button { onQuick(k, label) } label: {
            Text(label).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 36).background(.white.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var tasksBlock: some View {
        let open = (tasks?.tasks ?? []).filter { !$0.done }.prefix(3)
        return block {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("СПРАВИ" + (tasks.map { " · \($0.done) З \($0.total)" } ?? "")).font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Усі") { onTasks() }.font(.system(size: 13, weight: .semibold)).tint(Theme.olive)
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
                if tasks != nil && open.isEmpty { Text("На сьогодні все ✓").font(.system(size: 14)).foregroundStyle(Theme.muted).padding(.horizontal, 16).padding(.bottom, 14) }
                ForEach(Array(open.enumerated()), id: \.element.id) { i, t in
                    let done = ticked.contains(t.id)
                    HStack(spacing: 14) {
                        Button { tick(t) } label: {
                            ZStack {
                                Circle().stroke(done ? Theme.ink : Color(hex: 0xB9AE9F), lineWidth: 1.6)
                                if done { Circle().fill(Theme.ink); Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.cream) }
                            }
                            .frame(width: 22, height: 22)
                        }
                        .buttonStyle(PressScale())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(done ? Color(hex: 0xA99C8D) : Theme.ink)
                            if t.assignee == "us" { Text("нам").font(.system(size: 11.5)).foregroundStyle(Theme.muted) }
                            else if t.createdBy == "partner" { Text("від: \(d.partner?.name ?? "")").font(.system(size: 11.5)).foregroundStyle(Color(hex: 0x4F6F95)) }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 52) } }
                }
            }
        }
    }

    private func tick(_ t: TaskItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { _ = ticked.insert(t.id) }
        Haptic.hit(.heavy)
        Task {
            _ = try? await API.current().patchTask(t.id, API.TaskPatch(done: true, date: Evening.iso(Date())))
            try? await Task.sleep(for: .milliseconds(450))
            tasks = try? await API.current().tasks(Evening.iso(Date()))
            ticked.remove(t.id)
        }
    }

    private func watchRow(_ w: DashFilm) -> some View {
        block {
            HStack(spacing: 12) {
                ZStack { LinearGradient(colors: [Color(hex: 0x3A3F4A), Color(hex: 0x0D0E12)], startPoint: .top, endPoint: .bottom); if let u = w.posterUrl ?? w.backdropUrl { RemoteImage(url: u) } }
                    .frame(width: 44, height: 62).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.title).font(.system(size: 15.5, weight: .semibold)).lineLimit(1)
                    Text((w.season.map { "S\($0)E\(w.episode ?? 1) · " } ?? "") + "дивимось").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(12).contentShape(Rectangle()).onTapGesture { onFilm(w.id) }
        }
    }

    private func spotRow(_ t: SpotTrack, hers: Bool) -> some View {
        block {
            HStack(spacing: 12) {
                VinylDisc(spinning: t.playing).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hers ? "\(d.partner?.name ?? "") слухає" : "Ти слухаєш").font(.system(size: 15, weight: .semibold))
                    Text("\(t.artist) — \(t.title)").font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Image(systemName: "music.note").foregroundStyle(Color(hex: 0x1DB954))
            }
            .padding(12)
        }
    }
}
