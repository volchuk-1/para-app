import SwiftUI

// MARK: - Memories: every photo of an album with its own description, all the places, edits

extension API {
    struct ShotPatch: Encodable { let date: String; let place: String; let note: String }
    struct AlbumPatch6: Encodable { let title: String; let note: String }
    struct MemoryPatch: Encodable { let title: String; let date: String; let place: String; let note: String }
    struct MemoryFull: Decodable { let memory: MemoryOut }
    struct MemoryOut: Decodable { let title: String; let date: String; let note: String?; let place: String? }

    func patchShot(album: String, photo: String, _ p: ShotPatch) async throws -> Album { (try await send("PATCH", "/albums/\(album)/photos/\(photo)", p) as AlbumResult).album }
    func patchAlbum(_ id: String, _ p: AlbumPatch6) async throws -> Album { (try await send("PATCH", "/albums/\(id)", p) as AlbumResult).album }
    func patchMemory(_ id: String, _ p: MemoryPatch) async throws -> MemoryOut { (try await send("PATCH", "/memories/\(id)", p) as MemoryFull).memory }
}

enum MemoryText {
    static let uk = Locale(identifier: "uk_UA")
    static let dayFmt: DateFormatter = { let f = DateFormatter(); f.locale = uk; f.dateFormat = "d MMMM yyyy, HH:mm"; return f }()
    static let isoDay: DateFormatter = { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    static func maps(_ lat: Double, _ lon: Double) -> URL? { URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)") }
}

/// The places of an album as chips: «Яремче · 2», «Ворохта»; each opens the map.
struct PlaceChips: View {
    let places: [AlbumPlace]
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(places) { p in
                    Button {
                        if let lat = p.lat, let lon = p.lon, let u = MemoryText.maps(lat, lon) { openURL(u) }
                    } label: {
                        Label(p.label + (p.count > 1 ? " · \(p.count)" : ""), systemImage: "mappin.circle.fill")
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1).padding(.horizontal, 12).frame(height: 34)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// One photo of an album: the picture, and under it its own description — date, place on the map, weather, a note.
struct ShotDetail: View {
    let albumId: String
    @State var shots: [AlbumPhoto]
    @State var index: Int
    var changed: (Album) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editing = false

    private var p: AlbumPhoto { shots[min(index, shots.count - 1)] }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Color.black.frame(height: UIScreen.main.bounds.height * 0.56)
                        .overlay { AuthImage(url: p.url).scaledToFit() }
                        .clipped()
                    VStack(alignment: .leading, spacing: 10) {
                        Text(lines).font(.system(size: 14, design: .monospaced)).lineSpacing(4)
                        if let lat = p.lat, let lon = p.lon {
                            Button { if let u = MemoryText.maps(lat, lon) { openURL(u) } } label: {
                                Label(String(format: "%.4f, %.4f · Google Maps", lat, lon), systemImage: "mappin.circle.fill")
                                    .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
                                    .background(Color.white.opacity(0.16), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("У цьому фото немає геолокації.").font(.system(size: 13)).opacity(0.6)
                        }
                        if let n = p.note, !n.isEmpty { Text(n).font(.system(size: 15)) }
                        HStack {
                            navButton("chevron.left", enabled: index > 0) { index -= 1 }
                            Spacer()
                            Button { editing = true } label: {
                                Label("Змінити", systemImage: "pencil").font(.system(size: 14, weight: .bold))
                                    .padding(.horizontal, 16).frame(height: 40).background(Color.white.opacity(0.18), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            navButton("chevron.right", enabled: index < shots.count - 1) { index += 1 }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 22).padding(.bottom, 60)
                }
            }
            .foregroundStyle(.white)
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).frame(width: 46, height: 46).background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(.white).padding(.leading, 16).padding(.top, 6)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -70, index < shots.count - 1 { Haptic.hit(.light); index += 1 }
            else if v.translation.width > 70, index > 0 { Haptic.hit(.light); index -= 1 }
            else if v.translation.height > 110 { dismiss() }
        })
        .sheet(isPresented: $editing) {
            ShotEditSheet(albumId: albumId, shot: p) { album in
                let id = p.id
                shots = album.photos
                index = album.photos.firstIndex { $0.id == id } ?? 0
                changed(album)
            }
        }
    }

    private var lines: String {
        var l = ["ФОТО \(index + 1) З \(shots.count)", "ДАТА: " + (p.takenAt.map { MemoryText.dayFmt.string(from: $0) } ?? "невідома")]
        if let pl = p.place { l.append("МІСЦЕ: \(pl)") }
        if let t = p.temp { l.append("ПОГОДА: \(t > 0 ? "+" : "")\(t)°C") }
        return l.joined(separator: "\n")
    }

    private func navButton(_ icon: String, enabled: Bool, _ a: @escaping () -> Void) -> some View {
        Button { Haptic.hit(.light); a() } label: {
            Image(systemName: icon).font(.system(size: 17, weight: .bold)).frame(width: 44, height: 44).background(Color.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0).disabled(!enabled)
    }
}

/// The date, the name of the place and a note of one photo (the coordinates come from the photo itself).
struct ShotEditSheet: View {
    let albumId: String
    let shot: AlbumPhoto
    var saved: (Album) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var place = ""
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            SoftForm {
                Section {
                    DatePicker("Дата", selection: $date, displayedComponents: .date).environment(\.locale, MemoryText.uk)
                    TextField("Місце, напр.: Ворохта, віадук", text: $place)
                    TextField("Підпис", text: $note, axis: .vertical).lineLimit(1...4)
                } footer: { Text("Геолокація береться з самого фото і не змінюється; назву місця, дату й підпис можна виправити.") }
                if let error { Section { Text(error).foregroundStyle(Theme.coffee) } }
            }
            .navigationTitle("Фото").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрити") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save() } }.disabled(busy) }
            }
            .onAppear { date = shot.takenAt ?? Date(); place = shot.place ?? ""; note = shot.note ?? "" }
        }
        .tint(Theme.olive)
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            let a = try await API.current().patchShot(album: albumId, photo: shot.id, .init(date: MemoryText.isoDay.string(from: date), place: place, note: note))
            Haptic.ok(); saved(a); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// A memory: title, date, place, note. An album: title and note (dates and places live on its photos).
struct MemoryEditSheet: View {
    let item: HistoryItem
    var saved: (HistoryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var place = ""
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            SoftForm {
                Section {
                    TextField("Назва", text: $title)
                    if item.kind == "memory" {
                        DatePicker("Дата", selection: $date, displayedComponents: .date).environment(\.locale, MemoryText.uk)
                        TextField("Місце", text: $place)
                    }
                    TextField("Підпис", text: $note, axis: .vertical).lineLimit(1...5)
                } footer: {
                    if item.kind == "album" { Text("Дату й місце кожного фото змінюй на самому фото.") }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.coffee) } }
            }
            .navigationTitle(item.kind == "album" ? "Альбом" : "Спогад").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрити") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save() } }.disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear {
                title = item.title; place = item.place ?? ""; note = item.note ?? ""
                date = Evening.date(String(item.at.prefix(10))) ?? Date()
            }
        }
        .tint(Theme.olive)
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            var x = item
            if item.kind == "album" {
                let a = try await API.current().patchAlbum(item.id, .init(title: title, note: note))
                x.title = a.title; x.note = a.note
            } else {
                let m = try await API.current().patchMemory(item.id, .init(title: title, date: MemoryText.isoDay.string(from: date), place: place, note: note))
                x.title = m.title; x.note = m.note; x.place = m.place; x.at = "\(m.date)T12:00:00.000Z"
            }
            Haptic.ok(); saved(x); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
