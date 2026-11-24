import SwiftUI
import PhotosUI

extension API {
    func deleteMemory(_ id: String) async throws { try await delete("/memories/\(id)") }
}

// MARK: - В → Історія: one feed, newest first

/// Memories with photos, our dates and the films we finished — with scores and reviews.
struct HistoryFeed: View {
    @EnvironmentObject var state: AppState
    @State private var items: [HistoryItem] = []
    @State private var loaded = false
    @State private var add = false
    @State private var remove: HistoryItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(plain: "Наша", italic: "історія", sub: "Спогади з фото, побачення й подивлене — від нових до старих.")
                Button { add = true } label: {
                    Label("Додати спогад з фото", systemImage: "photo.badge.plus").font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 50).background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                }
                if loaded && items.isEmpty { EmptyCard(text: "Тут з'являться ваші побачення, подивлені фільми й спогади.") }
                ForEach(groups, id: \.0) { g in
                    Text(g.0).font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(Theme.muted).padding(.top, 6)
                    ForEach(g.1) { it in card(it) }
                }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 130)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $add, onDismiss: { Task { await load() } }) { AddMemorySheet() }
        .confirmationDialog("Видалити спогад?", isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }), titleVisibility: .visible) {
            Button("Видалити", role: .destructive) { if let r = remove { Task { try? await API.current().deleteMemory(r.id); await load() } } }
        }
    }

    /// «ЛИСТОПАД 2026» → items
    private var groups: [(String, [HistoryItem])] {
        var out: [(String, [HistoryItem])] = []
        for it in items {
            let k = monthTitle(it.at)
            if let i = out.firstIndex(where: { $0.0 == k }) { out[i].1.append(it) } else { out.append((k, [it])) }
        }
        return out
    }

    private func date(_ s: String) -> Date? { API.decoderDate(s) ?? ISO8601DateFormatter().date(from: s) ?? Evening.date(String(s.prefix(10))) }
    private func monthTitle(_ s: String) -> String {
        guard let d = date(s) else { return "" }
        return d.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "uk_UA"))).uppercased()
    }
    private func dayText(_ s: String) -> String {
        guard let d = date(s) else { return "" }
        return d.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA")))
    }

    @ViewBuilder private func card(_ it: HistoryItem) -> some View {
        switch it.kind {
        case "memory":
            VStack(alignment: .leading, spacing: 0) {
                if let p = it.photoUrl {
                    Color.black.frame(height: 230).frame(maxWidth: .infinity).overlay { AuthImage(url: p) }.clipped()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(it.title).font(.system(size: 17, weight: .semibold))
                    Text(dayText(it.at)).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    if let n = it.note, !n.isEmpty { Text(n).font(.system(size: 14)).padding(.top, 2) }
                }
                .padding(14)
            }
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contextMenu { Button("Видалити", systemImage: "trash", role: .destructive) { remove = it } }
        case "film":
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(url: it.backdropUrl).frame(width: 86, height: 64).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("ПОДИВИЛИСЬ").font(.system(size: 10.5, weight: .bold)).tracking(1).foregroundStyle(Theme.olive)
                    Text(it.title).font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 6) {
                        if let r = it.ratings {
                            if let m = r[state.me?.id ?? ""] { tag("\(state.me?.name ?? "я") \(m)") }
                            if let p = r[state.partner?.id ?? ""] { tag("\(state.partner?.name ?? "") \(p)") }
                        }
                        if let a = it.avg { tag("разом " + String(format: "%.1f", a)) }
                    }
                    ForEach(it.reviews ?? [], id: \.self) { rv in
                        Text("«\(rv.text)» — \(rv.memberId == state.me?.id ? (state.me?.name ?? "") : (state.partner?.name ?? ""))").font(.system(size: 13)).foregroundStyle(Theme.ink.opacity(0.8))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12).background(Theme.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        case "cancelled":
            HStack(spacing: 12) {
                Image(systemName: "xmark").foregroundStyle(Theme.muted).frame(width: 40, height: 40).background(Theme.tan.opacity(0.6), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("СКАСОВАНЕ ПОБАЧЕННЯ").font(.system(size: 10.5, weight: .bold)).tracking(1).foregroundStyle(Theme.muted)
                    Text(it.title).font(.system(size: 15, weight: .semibold)).strikethrough(color: Theme.muted)
                    Text([dayText(it.at), it.note ?? it.place].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(12).background(Theme.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        default: // date
            HStack(spacing: 12) {
                Image(systemName: "heart.fill").foregroundStyle(Theme.cream).frame(width: 40, height: 40).background(Theme.coffee, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.title).font(.system(size: 15, weight: .semibold))
                    Text([dayText(it.at), it.place].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(12).background(Theme.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func tag(_ t: String) -> some View {
        Text(t).font(.system(size: 11.5, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(Theme.tan.opacity(0.6), in: Capsule())
    }

    private func load() async {
        if let list = try? await API.current().history() { items = list }
        loaded = true
    }
}

struct AddMemorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var day = Date()
    @State private var pick: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            SoftForm {
                Section {
                    PhotosPicker(selection: $pick, matching: .images) {
                        ZStack {
                            if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fill) }
                            else { VStack(spacing: 6) { Image(systemName: "photo.badge.plus").font(.system(size: 30)); Text("Обрати фото") }.foregroundStyle(Theme.olive) }
                        }
                        .frame(height: 200).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Section("Що було") {
                    TextField("Прогулянка на Невицький замок", text: $title)
                    DatePicker("Коли", selection: $day, in: ...Date(), displayedComponents: .date).environment(\.locale, Locale(identifier: "uk_UA"))
                    TextField("Кілька слів (необов'язково)", text: $note, axis: .vertical).lineLimit(2...5)
                }
                if let error { Section { Text(error).foregroundStyle(Theme.coffee) } }
            }
            .navigationTitle("Новий спогад").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Зберегти") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
            }
            .onChange(of: pick) { _, p in
                Task {
                    if let p, let d = try? await p.loadTransferable(type: Data.self) { image = UIImage(data: d) }
                }
            }
        }
        .tint(Theme.olive)
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            let id = try await API.current().addMemory(.init(title: title, date: Evening.iso(day), note: note.isEmpty ? nil : note))
            if let image, let jpeg = image.resizedJPEG(maxSide: 1600) { try await API.current().uploadMemoryPhoto(id, jpeg: jpeg) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
