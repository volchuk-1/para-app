import SwiftUI
import PhotosUI
import ImageIO
import CoreLocation

// MARK: - Спогади: memories are circles, albums squares; the one in the middle turns into a droplet

struct GalleryPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL
    @Namespace private var ns
    @State private var items: [HistoryItem] = []
    @State private var loaded = false
    @State private var year: Int?
    @State private var month: Int?
    @State private var kind = "all"
    @State private var open: HistoryItem?
    @State private var add: AddPreset?
    @State private var spinReset = 0.0
    @State private var kindOpen = false
    @State private var kindHot: String?
    @State private var pressTask: Task<Void, Never>?
    private let kinds: [(String, String, String)] = [("all", "Усе", "sparkles"), ("memory", "Спогади", "photo"), ("album", "Альбоми", "photo.stack"),
                                                     ("date", "Побачення", "heart.fill"), ("film", "Фільми", "film")]
    private let mon = ["січ", "лют", "бер", "кві", "тра", "чер", "лип", "сер", "вер", "жов", "лис", "гру"]

    private var shown: [HistoryItem] {
        items.filter { x in
            guard let d = date(x.at) else { return false }
            let c = Calendar.current
            return (year == nil || c.component(.year, from: d) == year) && (month == nil || c.component(.month, from: d) - 1 == month) && (kind == "all" || x.kind == kind)
        }
    }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                Theme.cream.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 28) {
                        ForEach(shown) { x in blob(x, viewport: g.size.height) }
                        if loaded && shown.isEmpty { Text("Нічого за цими фільтрами.").font(.system(size: 14)).foregroundStyle(Theme.muted).padding(.top, 40) }
                    }
                    .padding(.leading, 96).frame(maxWidth: .infinity)
                    .padding(.top, g.size.height * 0.32).padding(.bottom, g.size.height * 0.5)
                }
                .coordinateSpace(name: "gcol")
                head.padding(.horizontal, 18).padding(.top, 6)
                rail.padding(.leading, 12).padding(.top, 96)
                if let x = open { detail(x).transition(.opacity).zIndex(5) }
            }
        }
        .foregroundStyle(Theme.ink)
        .task { await load() }
        .sheet(item: $add, onDismiss: { Task { await load() } }) { p in AddMemorySheet5(preset: p) }
        .sensoryFeedback(.selection, trigger: kindHot)
    }

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Спогади").font(.serif(30, .bold))
                Text("\(kinds.first { $0.0 == kind }?.1 ?? "") · \(month.map { mon[$0] + " " } ?? "")\(year.map(String.init) ?? "усі роки")").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { add = AddPreset() } label: { Image(systemName: "plus").font(.system(size: 19, weight: .bold)).frame(width: 44, height: 44).background(Theme.olive, in: Circle()).foregroundStyle(Theme.cream) }
                .padding(.trailing, 54)
        }
    }

    // MARK: blobs

    private func blob(_ x: HistoryItem, viewport: CGFloat) -> some View {
        let square = x.kind == "album"
        return GeometryReader { gg in
            let mid = gg.frame(in: .named("gcol")).midY
            let k = max(0, 1 - abs(mid - viewport * 0.45) / 180)
            let base: CGFloat = square ? 24 : 62
            let radius = base + (34 - base) * k
            ZStack {
                fill(x)
                if square, let n = x.count {
                    Text("\(n)").font(.system(size: 12, weight: .bold)).frame(minWidth: 26, minHeight: 26).padding(.horizontal, 4)
                        .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream).overlay(Capsule().stroke(Theme.cream, lineWidth: 3))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).offset(x: 6, y: -6)
                }
            }
            .frame(width: 124, height: 124)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .matchedGeometryEffect(id: x.id, in: ns, isSource: open?.id != x.id)
            .scaleEffect(1 + 0.18 * k)
            .shadow(color: .black.opacity(0.22 * k), radius: 18 * k, y: 12 * k)
            .overlay(alignment: .bottom) {
                Text(date(x.at).map { $0.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "uk_UA"))) } ?? "")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted).opacity(k > 0.6 ? 1 : 0).offset(y: 30)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture { Haptic.hit(.medium); withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { open = x } }
            .onChange(of: k > 0.85) { _, on in if on { Haptic.hit(.rigid, 0.9) } }
        }
        .frame(height: 124)
    }

    @ViewBuilder private func fill(_ x: HistoryItem) -> some View {
        let bg: Color = x.kind == "date" ? Theme.coffee : x.kind == "cancelled" ? Color(hex: 0xB9B2A5) : x.kind == "film" ? Color(hex: 0x2A2626) : Color(hex: 0xCFC9BC)
        ZStack {
            bg
            if let u = x.photoUrl { AuthImage(url: u) }
            else if let u = x.backdropUrl { RemoteImage(url: u) }
            else { Image(systemName: x.kind == "date" ? "heart.fill" : x.kind == "cancelled" ? "xmark" : "photo").font(.system(size: 32)).foregroundStyle(.white.opacity(0.85)) }
        }
        .opacity(x.kind == "cancelled" ? 0.6 : 1)
    }

    // MARK: rail: reset, year and month wheels, type

    private var rail: some View {
        let years = Array(Set(items.compactMap { date($0.at).map { Calendar.current.component(.year, from: $0) } })).sorted()
        return VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.9)) { spinReset -= 720 }
                Task { try? await Task.sleep(for: .milliseconds(600)); withAnimation(.snappy) { year = nil; month = nil; kind = "all" } }
            } label: { OuroborosShape().fill(Theme.olive).frame(width: 30, height: 30).frame(width: 44, height: 44).background(Theme.olive.opacity(0.12), in: Circle()).rotationEffect(.degrees(spinReset)) }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: spinReset)
            label("Рік")
            DialWheel(values: [nil] + years.map { Optional($0) }, label: { $0.map(String.init) ?? "Усі" }, selection: $year)
            label("Місяць")
            DialWheel(values: [nil] + (0..<12).map { Optional($0) }, label: { $0.map { mon[$0] } ?? "Усі" }, selection: $month)
            kindButton
        }
        .frame(width: 78)
    }
    private func label(_ t: String) -> some View { Text(t.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 4) }

    /// Type: press — a menu falls out to the right; slide to a type, let go.
    private var kindButton: some View {
        let cur = kinds.first { $0.0 == kind } ?? kinds[0]
        return VStack(spacing: 2) { Image(systemName: cur.2).font(.system(size: 19)); Text(cur.1).font(.system(size: 11.5, weight: .semibold)) }
            .frame(width: 78, height: 62).background(Theme.olive, in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(Theme.cream)
            .overlay(alignment: .topLeading) {
                if kindOpen {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(kinds, id: \.0) { k in
                            Label(k.1, systemImage: k.2).font(.system(size: 13.5, weight: .medium)).padding(.horizontal, 10).frame(width: 170, height: 38, alignment: .leading)
                                .background(kindHot == k.0 ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(6).background(Theme.ink, in: RoundedRectangle(cornerRadius: 20)).foregroundStyle(Theme.cream)
                    .offset(x: 88, y: -110).transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                }
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    if pressTask == nil && !kindOpen {
                        pressTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(260))
                            if !Task.isCancelled { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { kindOpen = true } }
                        }
                    }
                    if kindOpen {
                        // the menu starts 110 pt above the button's top, 6 pt padding, rows of 40 pt
                        let i = Int(((v.location.y + 110 - 6) / 40).rounded(.down))
                        kindHot = (0..<kinds.count).contains(i) && v.location.x > 70 ? kinds[i].0 : nil
                    }
                }
                .onEnded { _ in
                    pressTask?.cancel(); pressTask = nil
                    if kindOpen { if let h = kindHot { kind = h }; withAnimation(.snappy) { kindOpen = false }; kindHot = nil }
                    else { let i = kinds.firstIndex { $0.0 == kind } ?? 0; withAnimation(.snappy) { kind = kinds[(i + 1) % kinds.count].0 } }
                })
    }

    // MARK: detail: grows from the blob to the whole screen; the text types itself

    private func detail(_ x: HistoryItem) -> some View {
        MemoryDetail(item: x, ns: ns, close: { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { open = nil } },
                     addPhoto: { open = nil; add = AddPreset(title: x.title, date: String(x.at.prefix(10)), eventId: x.id) },
                     deleted: { open = nil; Task { await load() } })
    }

    private func date(_ s: String) -> Date? { API.decoderDate(s) ?? ISO8601DateFormatter().date(from: s) ?? Evening.date(String(s.prefix(10))) }
    private func load() async { if let l = try? await API.current().history() { items = l }; loaded = true }
}

/// A dial: values snap under the band, small notches between them, a ratchet click on each step.
struct DialWheel: View {
    let values: [Int?]
    let label: (Int?) -> String
    @Binding var selection: Int?
    @State private var pos: Int?
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    VStack(spacing: 0) {
                        Text(label(v)).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(pos == i ? Theme.ink : Theme.muted)
                            .scaleEffect(pos == i ? 1.16 : 1).frame(height: 36)
                        HStack(spacing: 5) { ForEach(0..<3, id: \.self) { k in Capsule().fill(Theme.ink.opacity(0.22)).frame(width: 1.5, height: k == 1 ? 9 : 6) } }.frame(height: 16)
                    }
                    .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $pos, anchor: .top)
        .contentMargins(.vertical, 52, for: .scrollContent)
        .frame(width: 78, height: 156)
        .background(alignment: .top) { RoundedRectangle(cornerRadius: 12).fill(Theme.olive.opacity(0.12)).frame(height: 36).padding(.horizontal, 6).padding(.top, 52) }
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 22))
        .overlay(LinearGradient(stops: [.init(color: Theme.paper, location: 0), .init(color: Theme.paper.opacity(0), location: 0.32), .init(color: Theme.paper.opacity(0), location: 0.68), .init(color: Theme.paper, location: 1)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1), trigger: pos)
        .onAppear { pos = values.firstIndex(of: selection) ?? 0 }
        .onChange(of: pos) { _, p in if let p, values.indices.contains(p), values[p] != selection { selection = values[p] } }
        .onChange(of: selection) { _, s in let i = values.firstIndex(of: s) ?? 0; if i != pos { withAnimation { pos = i } } }
    }
}

struct MemoryDetail: View {
    let item: HistoryItem
    let ns: Namespace.ID
    var close: () -> Void
    var addPhoto: () -> Void
    var deleted: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var typed = ""
    @State private var confirm = false

    private var lines: String {
        let d = API.decoderDate(item.at) ?? Evening.date(String(item.at.prefix(10))) ?? Date()
        let kind = ["memory": "СПОГАД", "album": "АЛЬБОМ", "date": "ПОБАЧЕННЯ", "film": "ФІЛЬМ", "cancelled": "СКАСОВАНО"][item.kind] ?? ""
        var l = ["\(kind)_\(d.formatted(.dateTime.day(.twoDigits).month(.twoDigits)))", "ДАТА: \(d.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "uk_UA"))))"]
        if let p = item.place { l.append("МІСЦЕ: \(p)") }
        if let t = item.temp { l.append("ПОГОДА: \(t > 0 ? "+" : "")\(t)°C") }
        if let c = item.count { l.append("ФОТО: \(c)") }
        return l.joined(separator: "\n")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
                .overlay { if let u = item.photoUrl { AuthImage(url: u) } else if let u = item.backdropUrl { RemoteImage(url: u) } }
                .clipShape(RoundedRectangle(cornerRadius: 0))
                .matchedGeometryEffect(id: item.id, in: ns)
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(typed).font(.system(size: 14, design: .monospaced)).lineSpacing(4).frame(minHeight: 90, alignment: .topLeading)
                    Text(item.title).font(.system(size: 42, weight: .light)).tracking(-0.8)
                    if let lat = item.lat, let lon = item.lon {
                        Button { if let u = URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)") { openURL(u) } } label: {
                            Label(String(format: "%.4f, %.4f · Google Maps", lat, lon), systemImage: "mappin.circle.fill").font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14).frame(height: 36).background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    if let n = item.note, !n.isEmpty { Text(n).font(.system(size: 15)) }
                    if item.kind == "film", let a = item.avg { Text("разом \(String(format: "%.1f", a))").font(.system(size: 15)) }
                    if item.kind == "album", let ph = item.photos {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                            ForEach(ph, id: \.self) { u in Color.gray.aspectRatio(1, contentMode: .fit).overlay { AuthImage(url: u) }.clipped() }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18)).padding(.top, 160)
                    }
                    if item.kind == "date" {
                        Button(action: addPhoto) { Label("Додати фото до цього вечора", systemImage: "camera.fill").frame(maxWidth: .infinity).frame(height: 50) }
                            .font(.system(size: 15, weight: .semibold)).background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream).padding(.top, 200)
                    }
                    if item.kind == "memory" || item.kind == "album" {
                        Button("Видалити") { confirm = true }.font(.system(size: 13)).opacity(0.6).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 22).padding(.top, 76).padding(.bottom, 120)
            }
            .foregroundStyle(.white)
            // top-left: the bell sits top-right over everything
            Button { Haptic.hit(.medium); close() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).frame(width: 46, height: 46).background(.ultraThinMaterial, in: Circle()) }
                .foregroundStyle(.white).padding(.leading, 16).padding(.top, 6)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in if v.translation.height > 90 || v.translation.width > 110 { Haptic.hit(.medium); close() } })
        .task {
            typed = ""
            for ch in lines { typed.append(ch); try? await Task.sleep(for: .milliseconds(22)) }
        }
        .confirmationDialog("Видалити?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Видалити", role: .destructive) {
                Task {
                    if item.kind == "album" { try? await API.current().deleteAlbum(item.id) } else { try? await API.current().deleteMemory(item.id) }
                    deleted()
                }
            }
        }
    }
}

struct AddPreset: Identifiable { var title = ""; var date = ""; var eventId: String? = nil; var id: String { "\(title)|\(date)|\(eventId ?? "")" } }

/// One photo → a memory (circle); several → an album (square). Date and place come from the photo itself.
struct AddMemorySheet5: View {
    @Environment(\.dismiss) private var dismiss
    let preset: AddPreset
    @State private var picks: [PhotosPickerItem] = []
    @State private var photos: [(data: Data, meta: PhotoMeta)] = []
    @State private var title = ""
    @State private var day = Date()
    @State private var note = ""
    @State private var busy = false
    @State private var progress = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            SoftForm {
                Section {
                    PhotosPicker(selection: $picks, maxSelectionCount: 40, matching: .images, photoLibrary: .shared()) {
                        if photos.isEmpty { Label("Обрати фото", systemImage: "photo.on.rectangle.angled") }
                        else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) { ForEach(Array(photos.enumerated()), id: \.offset) { _, p in if let i = UIImage(data: p.data) { Image(uiImage: i).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10)) } } }
                            }
                        }
                    }
                } footer: { Text(photos.count > 1 ? "Альбом · \(photos.count) фото" : "Одне фото — спогад, кілька — альбом") }
                if let m = photos.first(where: { $0.meta.lat != nil })?.meta ?? photos.first?.meta {
                    Section("З фото") {
                        if let t = m.taken { Label(t.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier: "uk_UA"))), systemImage: "calendar") }
                        if let p = m.place { Label(p, systemImage: "mappin") } else if m.lat != nil { Label("шукаю назву місця…", systemImage: "mappin") }
                        if m.lat == nil { Text("У фото нема місця").foregroundStyle(Theme.muted) }
                    }
                }
                Section {
                    TextField("Назва — Невицький замок", text: $title)
                    DatePicker("Коли", selection: $day, displayedComponents: .date).environment(\.locale, Locale(identifier: "uk_UA"))
                    TextField("Кілька слів", text: $note, axis: .vertical).lineLimit(1...4)
                }
                if !progress.isEmpty { Section { Text(progress).foregroundStyle(Theme.muted) } }
                if let error { Section { Text(error).foregroundStyle(Theme.coffee) } }
            }
            .navigationTitle(preset.eventId != nil ? "Фото до вечора" : "Новий спогад").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { if busy { ProgressView() } else { Button("Зберегти") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) } }
            }
            .onAppear { title = preset.title; if let d = Evening.date(preset.date) { day = d } }
            .onChange(of: picks) { _, items in Task { await read(items) } }
        }
        .tint(Theme.olive)
    }

    private func read(_ items: [PhotosPickerItem]) async {
        var out: [(Data, PhotoMeta)] = []
        for it in items { if let d = try? await it.loadTransferable(type: Data.self) { out.append((d, PhotoMeta.read(d))) } }
        photos = out.map { (data: $0.0, meta: $0.1) }
        if let t = photos.compactMap({ $0.meta.taken }).first { day = t }
        if let i = photos.firstIndex(where: { $0.meta.lat != nil }), let lat = photos[i].meta.lat, let lon = photos[i].meta.lon {
            let place = await PhotoMeta.place(lat: lat, lon: lon)
            for k in photos.indices where photos[k].meta.lat != nil { photos[k].meta.place = place }
            if title.isEmpty, let p = place { title = p.components(separatedBy: ",").first ?? p }
        }
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            if photos.count > 1 {
                let a = try await API.current().newAlbum(title)
                for (i, p) in photos.enumerated() {
                    progress = "Завантажую \(i + 1) з \(photos.count)…"
                    guard let img = UIImage(data: p.data), let jpeg = img.resizedJPEG(maxSide: 1600) else { continue }
                    try await API.current().addAlbumPhoto(a.id, jpeg: jpeg, lat: p.meta.lat, lon: p.meta.lon, place: p.meta.place, takenAt: p.meta.taken)
                }
            } else {
                let m = photos.first?.meta
                let id = try await API.current().addMemory(.init(title: title, date: Evening.iso(day), note: note.isEmpty ? nil : note,
                                                                 eventId: preset.eventId, lat: m?.lat, lon: m?.lon, place: m?.place, takenAt: m?.taken))
                if let p = photos.first, let img = UIImage(data: p.data), let jpeg = img.resizedJPEG(maxSide: 1600) { try await API.current().uploadMemoryPhoto(id, jpeg: jpeg) }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// When and where a photo was taken (EXIF / GPS), and the place name from Apple.
struct PhotoMeta {
    var taken: Date?
    var lat: Double?
    var lon: Double?
    var place: String?

    static func read(_ data: Data) -> PhotoMeta {
        var m = PhotoMeta()
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return m }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any], let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter(); f.dateFormat = "yyyy:MM:dd HH:mm:ss"; f.timeZone = .current
            m.taken = f.date(from: s)
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let la = gps[kCGImagePropertyGPSLatitude] as? Double, let lo = gps[kCGImagePropertyGPSLongitude] as? Double {
            m.lat = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -la : la
            m.lon = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -lo : lo
        }
        return m
    }

    static func place(lat: Double, lon: Double) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon), preferredLocale: Locale(identifier: "uk_UA"))
        guard let p = marks?.first else { return nil }
        return [p.locality ?? p.subAdministrativeArea, p.administrativeArea].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ", ")
    }
}
