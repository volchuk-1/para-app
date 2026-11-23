import SwiftUI

/// Create / edit a plain event («моє» або «наше»).
struct EventEditor: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let existing: Event?

    @State private var title = ""
    @State private var ours = true
    @State private var start = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var hasEnd = false
    @State private var end = Date().addingTimeInterval(7200)
    @State private var place = ""
    @State private var note = ""
    @State private var busy = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            SoftForm {
                Section {
                    TextField("Назва", text: $title)
                    Picker("Чиє", selection: $ours) {
                        Text("Наше").tag(true)
                        Text("Моє").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .disabled(existing != nil)
                }
                Section {
                    DatePicker("Початок", selection: $start)
                        .onChange(of: start) { _, s in end = EventTimes.clampedEnd(start: s, end: end) }
                    Toggle("Є кінець", isOn: $hasEnd)
                        .onChange(of: hasEnd) { _, on in if on { end = EventTimes.clampedEnd(start: start, end: end) } }
                    if hasEnd { DatePicker("Кінець", selection: $end, in: start...) }
                }
                Section {
                    TextField("Місце", text: $place)
                    TextField("Нотатка", text: $note, axis: .vertical).lineLimit(2...5)
                }
                if let e = store.error { Section { Text(e).foregroundStyle(Theme.coffee) } }
                if existing != nil && canEdit {
                    Section { Button("Видалити", role: .destructive) { confirmDelete = true } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle(existing == nil ? "Нова подія" : "Подія")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти") { Task { await save() } }
                        .disabled(busy || !canEdit || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Видалити подію?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Видалити", role: .destructive) { Task { await remove() } }
            }
            .onAppear(perform: load)
        }
    }

    /// Partner's own events are read-only here.
    private var canEdit: Bool { existing == nil || existing!.isOurs || existing!.ownerId == state.me?.id }

    private func load() {
        guard let e = existing else { return }
        title = e.title; ours = e.isOurs; start = e.startsAt
        hasEnd = e.endsAt != nil; end = e.endsAt ?? e.startsAt.addingTimeInterval(7200)
        place = e.place ?? ""; note = e.note ?? ""
    }

    private var draft: EventDraft {
        EventDraft(ownerId: ours ? nil : state.me?.id, title: title, startsAt: start, endsAt: hasEnd ? end : nil,
                   place: place.isEmpty ? nil : place, note: note.isEmpty ? nil : note)
    }

    private func save() async {
        busy = true; defer { busy = false }
        let ok = await store.run {
            let api = API.current()
            let e = try await (existing == nil ? api.createEvent(draft) : api.updateEvent(existing!.id, draft))
            store.upsert(e)
        }
        if ok { dismiss() }
    }

    private func remove() async {
        guard let e = existing else { return }
        if await store.run({ try await API.current().deleteEvent(e.id); store.removeEvent(e.id) }) { dismiss() }
    }
}

/// Opens the right screen for an event: invitation view or the editor.
struct InviteOrEventView: View {
    let event: Event
    var body: some View {
        if event.invitation != nil { InviteView(event: event) } else { EventEditor(existing: event) }
    }
}
