import SwiftUI
import PhotosUI

/// Create / edit an invitation: title, when, where, what to wear, message, cover photo.
struct InviteEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let existing: Event?
    var prefillTitle: String? = nil
    /// Set after the first successful send, so a failed photo upload never creates a second invitation.
    @State private var createdId: String?

    @State private var title = ""
    @State private var start = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0,
                                                     of: Date().addingTimeInterval(3 * 86400)) ?? Date()
    @State private var place = ""
    @State private var mapUrl = ""
    @State private var dress = ""
    @State private var message = ""
    @State private var photo: PhotosPickerItem?
    @State private var coverJPEG: Data?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Що (вечеря на даху, кіно…)", text: $title)
                    DatePicker("Коли", selection: $start, in: Date()...)
                }
                Section {
                    TextField("Де", text: $place)
                    TextField("Посилання на карту (необов'язково)", text: $mapUrl)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    TextField("Що вдягнути", text: $dress)
                    TextField("Повідомлення", text: $message, axis: .vertical).lineLimit(2...6)
                }
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(coverJPEG == nil ? "Фото обкладинки" : "Фото вибрано ✓", systemImage: "photo")
                    }
                    if let data = coverJPEG, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill().frame(height: 160).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                if let e = store.error { Section { Text(e).foregroundStyle(Theme.coffee) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle(existing == nil ? "Запрошення" : "Змінити запрошення")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Надіслати" : "Зберегти") { Task { await save() } }
                        .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: photo) { _, item in Task { await loadPhoto(item) } }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let t = prefillTitle, title.isEmpty { title = t }
        guard let e = existing else { return }
        title = e.title; start = e.startsAt; place = e.place ?? ""; mapUrl = e.mapUrl ?? ""
        dress = e.invitation?.dress ?? ""; message = e.invitation?.message ?? ""
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
        coverJPEG = ImageTools.jpeg(img, maxSide: 1600)
    }

    private func save() async {
        busy = true; defer { busy = false }
        let draft = EventDraft(ownerId: nil, title: title, startsAt: start, endsAt: nil,
                               place: place.isEmpty ? nil : place, mapUrl: mapUrl.isEmpty ? nil : mapUrl,
                               note: nil, dress: dress.isEmpty ? nil : dress, message: message.isEmpty ? nil : message)
        let ok = await store.run {
            let api = API.current()
            var e: Event
            if let id = existing?.id ?? createdId {
                e = try await api.updateEvent(id, draft)
            } else {
                e = try await api.createInvitation(draft)
                createdId = e.id
            }
            if let jpeg = coverJPEG {
                try await api.uploadCover(e.id, jpeg: jpeg)
                e = try await api.events(from: e.startsAt.addingTimeInterval(-60), to: e.startsAt.addingTimeInterval(60))
                    .first { $0.id == e.id } ?? e
            }
            store.upsert(e)
        }
        if ok { dismiss(); await store.refreshAll() }
    }
}

enum ImageTools {
    /// Scales so the longer side is at most `maxSide`, JPEG 0.8.
    static func jpeg(_ img: UIImage, maxSide: CGFloat) -> Data? {
        let s = img.size
        let k = min(1, maxSide / max(s.width, s.height))
        let size = CGSize(width: (s.width * k).rounded(), height: (s.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.8)
    }
}
