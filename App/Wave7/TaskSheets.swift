import SwiftUI

// MARK: - «Справи»: one task (its list, to the timer, done), a new task, a new routine

struct TaskSheet: View {
    @State var task: TaskItem
    let day: String
    let partner: String
    var onTimer: (TaskItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newItem = ""
    @State private var busy = false
    @State private var askDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TaskTags(task: task, partner: partner)
                Text(task.title).font(.serif(28, .bold))
                if let n = task.note, !n.isEmpty { Text(n).font(.system(size: 14.5)).foregroundStyle(Theme.muted) }
                ForEach(Array(task.items.enumerated()), id: \.offset) { i, it in
                    Button { Task { await toggle(i) } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: it.done ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                                .foregroundStyle(it.done ? Theme.olive : Theme.line)
                            Text(it.t).font(.system(size: 15.5)).strikethrough(it.done).foregroundStyle(it.done ? Theme.muted : Theme.ink)
                            Spacer()
                        }
                        .padding(.horizontal, 14).frame(minHeight: 48)
                        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    TextField("Додати пункт", text: $newItem).font(.system(size: 15)).padding(.horizontal, 14).frame(height: 46)
                        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onSubmit { Task { await addItem() } }
                    Button { Task { await addItem() } } label: {
                        Image(systemName: "plus").font(.system(size: 17, weight: .bold)).frame(width: 46, height: 46)
                            .background(Theme.olive, in: Circle()).foregroundStyle(Theme.cream)
                    }
                    .buttonStyle(PressScale())
                }
                if let m = task.minutes, !task.done {
                    wide("До таймера · \(m) хв", "timer", Theme.olive, Theme.cream) { onTimer(task); dismiss() }
                }
                wide(task.done ? "Повернути в роботу" : "Готово ✓", task.done ? "arrow.uturn.backward" : "checkmark",
                     task.done ? Theme.cream : Theme.ink, task.done ? Theme.ink : Theme.cream) { Task { await setDone(!task.done) } }
                Button(role: .destructive) { askDelete = true } label: {
                    Text("Видалити справу").font(.system(size: 15, weight: .semibold)).foregroundStyle(.red).frame(maxWidth: .infinity).frame(height: 46)
                }
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .disabled(busy)
        .confirmationDialog("Видалити справу?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Видалити", role: .destructive) { Task { try? await API.current().deleteTask(task.id); dismiss() } }
        }
    }

    private func wide(_ t: String, _ icon: String, _ bg: Color, _ fg: Color, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Label(t, systemImage: icon).font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 54)
                .background(bg, in: Capsule()).foregroundStyle(fg)
        }
        .buttonStyle(PressScale())
    }

    private func toggle(_ i: Int) async {
        var items = task.items
        items[i].done.toggle()
        task.items = items
        Haptic.hit(.light)
        if let t = try? await API.current().patchTask(task.id, API.TaskPatch(items: items, date: day)) { task = t }
    }
    private func addItem() async {
        let v = newItem.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        newItem = ""
        if let t = try? await API.current().patchTask(task.id, API.TaskPatch(items: task.items + [TaskLine(t: v, done: false)], date: day)) { task = t }
    }
    private func setDone(_ on: Bool) async {
        busy = true; defer { busy = false }
        if let t = try? await API.current().patchTask(task.id, API.TaskPatch(done: on, date: day)) {
            task = t
            if on { Haptic.ok(); dismiss() }
        }
    }
}

/// A row of pill buttons, one of them chosen.
struct PillPick<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var value: T
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]
                Button { value = o.0; Haptic.hit(.light) } label: {
                    Text(o.1).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(value == o.0 ? Theme.ink : .clear, in: Capsule())
                        .foregroundStyle(value == o.0 ? Theme.cream : Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).background(Theme.cream, in: Capsule())
    }
}

/// Seven day chips, Monday first; the server counts 1 = Monday … 7 = Sunday.
struct WeekdayPick: View {
    @Binding var days: Set<Int>
    private let names = ["пн", "вт", "ср", "чт", "пт", "сб", "нд"]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { n in
                let on = days.contains(n)
                Button { if on { days.remove(n) } else { days.insert(n) }; Haptic.hit(.light) } label: {
                    Text(names[n - 1]).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 40)
                        .background(on ? Theme.olive : Theme.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(on ? Theme.cream : Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NewTaskSheet: View {
    let partner: String
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var who = "me"
    @State private var itemsText = ""
    @State private var minutes = 0
    @State private var rep = ""
    @State private var days: Set<Int> = []
    @State private var mday = 1
    @State private var important = false
    @State private var busy = false
    @State private var err = ""

    private struct Preset { let label: String; let icon: String; let title: String; var minutes = 0; var rep = ""; var days: Set<Int> = []; var mday = 1 }
    private let presets: [Preset] = [
        Preset(label: "Продукти", icon: "cart.fill", title: "Купити продукти"),
        Preset(label: "Пропилососити", icon: "wind", title: "Пропилососити", minutes: 30),
        Preset(label: "Сміття", icon: "trash.fill", title: "Винести сміття", rep: "w", days: [4]),
        Preset(label: "Оплатити", icon: "creditcard.fill", title: "Оплатити рахунки", rep: "m", mday: 10),
        Preset(label: "Полити квіти", icon: "leaf.fill", title: "Полити квіти", rep: "w", days: [1, 4]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Нова справа").font(.serif(28, .bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(presets, id: \.label) { p in
                            Button { apply(p) } label: {
                                Label(p.label, systemImage: p.icon).font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 14).frame(height: 38)
                                    .background(Theme.cream, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 4)
                label("Що зробити")
                TextField("Що зробити", text: $title).font(.system(size: 16)).padding(.horizontal, 16).frame(height: 50)
                    .background(Theme.cream, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                label("Кому")
                PillPick(options: [("me", "Мені"), ("partner", partner), ("us", "Нам")], value: $who)
                label("Список усередині — кожен пункт з нового рядка")
                TextEditor(text: $itemsText).font(.system(size: 15)).frame(height: 84).scrollContentBackground(.hidden)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.cream, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                label("Скільки часу (для таймера)")
                PillPick(options: [(0, "—"), (15, "15"), (25, "25"), (30, "30"), (50, "50"), (90, "90")], value: $minutes)
                label("Повтор")
                PillPick(options: [("", "Один раз"), ("daily", "Щодня"), ("w", "Щотижня"), ("m", "Щомісяця")], value: $rep)
                if rep == "w" { WeekdayPick(days: $days) }
                if rep == "m" { Stepper("Число місяця: \(mday)", value: $mday, in: 1...31).font(.system(size: 15)).padding(.horizontal, 6) }
                Toggle("Важливо", isOn: $important).font(.system(size: 15)).tint(Theme.olive).padding(.horizontal, 6).padding(.top, 6)
                if !err.isEmpty { Text(err).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.coffee) }
                Button { Task { await save() } } label: {
                    Text("Додати").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 54)
                        .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                }
                .buttonStyle(PressScale()).disabled(busy).padding(.top, 6)
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 6).padding(.top, 6)
    }

    private func apply(_ p: Preset) {
        title = p.title; minutes = p.minutes; rep = p.rep; days = p.days; mday = p.mday
        Haptic.hit(.light)
    }

    private func save() async {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { err = "Напиши, що зробити"; return }
        var repeatValue: String?
        switch rep {
        case "daily": repeatValue = "daily"
        case "w":
            guard !days.isEmpty else { err = "Обери дні тижня"; return }
            repeatValue = "w:" + days.sorted().map(String.init).joined(separator: ",")
        case "m": repeatValue = "m:\(mday)"
        default: repeatValue = nil
        }
        let items = itemsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        busy = true; defer { busy = false }
        do {
            _ = try await API.current().addTask(API.TaskNew(title: t, assignee: who, items: items, minutes: minutes > 0 ? minutes : nil, repeat: repeatValue, important: important))
            Haptic.ok()
            dismiss()
        } catch {
            err = "Не вдалося зберегти"
        }
    }
}

struct NewRoutineSheet: View {
    private struct StepDraft: Identifiable { let id = UUID(); var name = ""; var minutes = 20 }
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var icon = "sun"
    @State private var days: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    @State private var steps: [StepDraft] = [StepDraft()]
    @State private var busy = false
    @State private var err = ""
    private let icons = ["sun", "moon", "book", "barbell", "translate", "laptop", "leaf", "heart", "music-note", "coffee"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Нова рутина").font(.serif(28, .bold))
                TextField("Назва", text: $title).font(.system(size: 16)).padding(.horizontal, 16).frame(height: 50)
                    .background(Theme.cream, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(icons, id: \.self) { i in
                            Button { icon = i; Haptic.hit(.light) } label: {
                                Image(systemName: routineSymbol(i)).font(.system(size: 17)).frame(width: 42, height: 42)
                                    .background(icon == i ? Theme.olive : Theme.cream, in: Circle()).foregroundStyle(icon == i ? Theme.cream : Theme.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                caption("Дні")
                WeekdayPick(days: $days)
                caption("Кроки")
                ForEach($steps) { $s in
                    HStack(spacing: 6) {
                        TextField("Крок", text: $s.name).font(.system(size: 15)).padding(.horizontal, 12).frame(height: 46)
                            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Stepper("\(s.minutes) хв", value: $s.minutes, in: 1...240, step: 5).font(.system(size: 14)).fixedSize()
                        if steps.count > 1 {
                            Button { steps.removeAll { $0.id == s.id } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(Theme.muted) }.buttonStyle(.plain)
                        }
                    }
                }
                Button { steps.append(StepDraft(minutes: 30)) } label: {
                    Label("Ще крок", systemImage: "plus").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 46)
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 1.5)).foregroundStyle(Theme.coffee)
                }
                .buttonStyle(.plain)
                if !err.isEmpty { Text(err).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.coffee) }
                Button { Task { await save() } } label: {
                    Text("Зберегти").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 54)
                        .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                }
                .buttonStyle(PressScale()).disabled(busy).padding(.top, 6)
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 6).padding(.top, 6)
    }

    private func save() async {
        let t = title.trimmingCharacters(in: .whitespaces)
        let list = steps.map { RoutineStep(name: $0.name.trimmingCharacters(in: .whitespaces), minutes: $0.minutes) }.filter { !$0.name.isEmpty && $0.minutes >= 1 }
        guard !t.isEmpty, !list.isEmpty else { err = "Назва й хоча б один крок з часом"; return }
        guard !days.isEmpty else { err = "Обери дні"; return }
        busy = true; defer { busy = false }
        do {
            _ = try await API.current().addRoutine(API.RoutineNew(title: t, icon: icon, days: days.sorted(), steps: list))
            Haptic.ok()
            dismiss()
        } catch {
            err = "Не вдалося зберегти"
        }
    }
}
