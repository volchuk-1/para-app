import SwiftUI

// MARK: - «Справи»: tasks, routines and one timer on one screen. The mode is picked like in the calendar:
// press the button, slide to a mode, let go (a tap opens the same picker to tap).

enum FocusMode: String, CaseIterable {
    case tasks, routine, timer
    var title: String {
        switch self { case .tasks: return "Задачі"; case .routine: return "Рутина"; case .timer: return "Таймер" }
    }
}

/// What the timer is about to run: a task with minutes, a step of a routine, or a free «Фокус». It never starts by itself.
struct TimerPrep: Equatable {
    var name = "Фокус"
    var minutes = 25
    var sub = "ТАЙМЕР"
    var together = false
    var routine: Routine? = nil
    var step = 0
    var taskId: String? = nil
    /// a focus session: the picked tasks, one at a time; the timer runs for the whole session
    var queue: [QueueItem] = []
    var idx = 0
    var view: FocusView = .timer
    /// «Почати фокус» is the start itself (the plain timer still waits for ▶)
    var autostart = false
}
struct QueueItem: Equatable { let id: String; let title: String }
/// what the big card shows: only the task, the clock, time since start, or the countdown
enum FocusView: String, CaseIterable {
    case minimal, clock, stopwatch, timer
    var title: String {
        switch self { case .minimal: return "Мінімал"; case .clock: return "Годинник"; case .stopwatch: return "Секундомір"; case .timer: return "Таймер" }
    }
}
struct RowFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

private let weekdayNames = ["нд", "пн", "вт", "ср", "чт", "пт", "сб"]
/// 1 = Monday … 7 = Sunday, as the server counts
private func wdName(_ n: Int) -> String { weekdayNames[n % 7] }
private let routineColors: [Color] = [Color(hex: 0x6E8FB5), Theme.olive, Color(hex: 0x8C5E3C), Color(hex: 0x9DB27F), Color(hex: 0xC8742A), Color(hex: 0x5A2230)]
/// the routine icons the server knows (Phosphor names) → SF symbols
func routineSymbol(_ icon: String) -> String {
    switch icon {
    case "moon": return "moon.fill"
    case "book": return "book.fill"
    case "barbell": return "dumbbell.fill"
    case "translate": return "character.bubble.fill"
    case "laptop": return "laptopcomputer"
    case "leaf": return "leaf.fill"
    case "heart": return "heart.fill"
    case "music-note": return "music.note"
    case "coffee": return "cup.and.saucer.fill"
    default: return "sun.max.fill"
    }
}
func repeatText(_ r: String?) -> String? {
    guard let r, !r.isEmpty else { return nil }
    if r == "daily" { return "щодня" }
    if r.hasPrefix("w:") { return "щ" + r.dropFirst(2).split(separator: ",").compactMap { Int($0) }.map(wdName).joined(separator: ", ") }
    if r.hasPrefix("m:") { return "щомісяця \(r.dropFirst(2))-го" }
    return nil
}

/// Small labels over a task: who it is for, important, minutes, repeat, the list.
struct TaskTags: View {
    let task: TaskItem
    let partner: String
    var body: some View {
        HStack(spacing: 5) {
            if task.done { tag("✓ готово", Color(hex: 0xDFE9D3), Theme.olive) }
            if task.important { tag("⌃ важливо", Color(hex: 0xF6E3C9), Color(hex: 0xA66A26)) }
            if task.assignee == "us" { tag("нам", Color(hex: 0xE4E8D6), Theme.olive) }
            else if task.assignee == "partner" { tag("для: \(partner)", Color(hex: 0xDCE6F1), Color(hex: 0x4F6F95)) }
            else if task.createdBy == "partner" { tag("від: \(partner)", Color(hex: 0xDCE6F1), Color(hex: 0x4F6F95)) }
            if let m = task.minutes { tag("\(m) хв", Color(hex: 0xEFEAE0), Theme.muted) }
            if let r = repeatText(task.repeat) { tag(r, Color(hex: 0xEFEAE0), Theme.muted) }
            if !task.items.isEmpty { tag("\(task.items.filter(\.done).count)/\(task.items.count)", Color(hex: 0xEFEAE0), Theme.muted) }
        }
    }
    private func tag(_ s: String, _ bg: Color, _ fg: Color) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous)).foregroundStyle(fg)
    }
}

struct FocusPage: View {
    @Binding var mode: FocusMode
    /// true while tasks are picked: the bar steps aside for the timer button and the focus card
    @Binding var picking0: Bool
    @EnvironmentObject var state: AppState
    @State private var day = Evening.iso(Date())
    @State private var list: TaskDay?
    @State private var routines: [Routine]?
    @State private var prep = TimerPrep()
    @State private var opened: TaskItem?
    @State private var newTask = false
    @State private var newRoutine = false
    @State private var picking = false
    @State private var pinned = false
    @State private var hot: FocusMode?
    @State private var pressTask: Task<Void, Never>?
    @State private var pickerFrame: CGRect = .zero
    @State private var sel: Set<String> = []
    @State private var card = false
    @State private var fview: FocusView = .timer
    @State private var fmin = 25
    @State private var frames: [String: CGRect] = [:]
    @State private var sliding = false
    /// the lift after a slide is not a tap
    @State private var justSlid = false
    @Namespace private var morph

    private var partner: String { state.partner?.name ?? "партнер" }
    private var cal: Calendar { Dock.calendar }

    var body: some View {
        ZStack(alignment: .top) {
            if mode == .timer {
                TimerScreen(prep: $prep, partner: partner, onClose: { switchTo(.tasks) }, onFinished: { await finished() }) { label in
                    timerTop(label)
                }
                .transition(.opacity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        header
                        if mode == .tasks { tasksView } else { routinesView }
                    }
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 130)
                }
                .scrollDisabled(sliding)
                .background(Theme.cream.ignoresSafeArea())
                .foregroundStyle(Theme.ink)
                .transition(.opacity)
            }
            if pinned {
                Color.black.opacity(0.001).ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy) { pinned = false; picking = false } }
            }
            focusLayer
            picker
        }
        .animation(.easeInOut(duration: 0.22), value: mode)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: card)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sel.isEmpty)
        .onChange(of: sel.isEmpty) { _, e in picking0 = !e }
        .onDisappear { picking0 = false }
        .onChange(of: mode) { _, _ in sel = []; card = false }
        .task(id: day) { await loadTasks() }
        .task { await loadRoutines() }
        .sheet(item: $opened, onDismiss: { Task { await loadTasks() } }) { t in
            TaskSheet(task: t, day: day, partner: partner) { tt in toTimer(tt) }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $newTask, onDismiss: { Task { await loadTasks() } }) { NewTaskSheet(partner: partner) }
        .sheet(isPresented: $newRoutine, onDismiss: { Task { await loadRoutines() } }) { NewRoutineSheet() }
        .sensoryFeedback(.selection, trigger: hot)
    }

    // MARK: the mode button and its picker

    private var header: some View {
        HStack(alignment: .center) {
            Text("Справи").font(.serif(34, .bold))
            Spacer()
            HStack(spacing: 6) {
                Text(mode.title).font(.system(size: 14, weight: .semibold))
                Text("затисни").font(.system(size: 10.5)).opacity(0.55)
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(Theme.ink, in: Capsule()).foregroundStyle(Theme.paper)
            .contentShape(Capsule())
            .gesture(modeGesture)
        }
        .padding(.trailing, 56).padding(.bottom, 4)
    }

    /// inside the dark card of the timer: «вт 24 · АНГЛІЙСЬКА ⌄» is the same mode button
    private func timerTop(_ label: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 14)).tracking(0.8).lineLimit(1).minimumScaleFactor(0.7)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
        }
        .opacity(0.85).frame(maxWidth: .infinity).frame(height: 24)
        .contentShape(Rectangle())
        .gesture(modeGesture)
    }

    private var modeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if pressTask == nil && !picking {
                    pressTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        if !Task.isCancelled { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { picking = true } }
                    }
                }
                if picking && !pinned { hot = modeAt(v.location.x) }
            }
            .onEnded { _ in
                pressTask?.cancel(); pressTask = nil
                if picking && !pinned {
                    switchTo(hot ?? mode)
                } else {
                    // a plain tap: the picker stays open to tap a mode
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { picking = true; pinned = true }
                }
            }
    }

    private func modeAt(_ x: CGFloat) -> FocusMode {
        guard pickerFrame.width > 0 else { return mode }
        let n = FocusMode.allCases.count
        let i = Int(((x - pickerFrame.minX) / pickerFrame.width * CGFloat(n)).rounded(.down))
        return FocusMode.allCases[max(0, min(n - 1, i))]
    }

    private func switchTo(_ m: FocusMode) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { picking = false; pinned = false; mode = m }
        hot = nil
        Haptic.hit(.light)
    }

    private var picker: some View {
        let dark = mode == .timer
        return HStack(spacing: 4) {
            ForEach(FocusMode.allCases, id: \.self) { m in
                let on = hot == m || (pinned && hot == nil && m == mode)
                Text(m.title).font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(on ? (dark ? Color(hex: 0xC7CCD3) : Theme.olive) : .clear, in: Capsule())
                    .foregroundStyle(on ? (dark ? Color(hex: 0x111111) : Theme.cream) : (dark ? Color(hex: 0x8D939B) : Theme.muted))
                    .scaleEffect(on ? 1.04 : 1)
                    .contentShape(Capsule())
                    .onTapGesture { if pinned { switchTo(m) } }
            }
        }
        .padding(6).frame(height: 56)
        .background(dark ? Color(hex: 0x1B1C1F) : Theme.paper, in: Capsule())
        .shadow(color: .black.opacity(dark ? 0.45 : 0.22), radius: 18, y: 10)
        .background(GeometryReader { g in Color.clear.onAppear { pickerFrame = g.frame(in: .global) }.onChange(of: g.frame(in: .global)) { _, f in pickerFrame = f } })
        .padding(.horizontal, 12).padding(.top, 6)
        .opacity(picking ? 1 : 0).scaleEffect(picking ? 1 : 0.96, anchor: .top).offset(y: picking ? 0 : -14)
        .allowsHitTesting(pinned)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: hot)
    }

    // MARK: Задачі

    private var weekDates: [Date] {
        let m = Evening.monday(of: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: m) }
    }

    private var tasksView: some View {
        let today = Evening.iso(Date())
        let t = list?.date == day ? list : nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(weekDates, id: \.self) { d in
                    let iso = Evening.iso(d), on = iso == day
                    Button { day = iso; Haptic.hit(.light) } label: {
                        VStack(spacing: 1) {
                            Text(weekdayNames[cal.component(.weekday, from: d) - 1]).font(.system(size: 11))
                            Text("\(cal.component(.day, from: d))").font(.system(size: 20, weight: .medium))
                                .foregroundStyle(iso == today && !on ? Theme.olive : (on ? Theme.ink : Color(hex: 0x9A9087)))
                        }
                        .frame(maxWidth: .infinity).frame(height: 58)
                        .background(on ? Theme.paper : Color(hex: 0xECE7DC), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: on ? Theme.ink.opacity(0.08) : .clear, radius: 4, y: 2)
                        .foregroundStyle(on ? Theme.ink : Color(hex: 0x9A9087))
                    }
                    .buttonStyle(.plain)
                }
            }
            goal(t, today: today)
            if !sel.isEmpty {
                HStack {
                    Button("Скасувати") { withAnimation(.snappy) { sel = []; card = false } }
                    Spacer()
                    Text("Вибрано: \(sel.count)").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button("Усі") { withAnimation(.snappy) { sel = Set((t?.tasks ?? []).filter { !$0.done }.map(\.id)) }; Haptic.hit(.light) }
                }
                .font(.system(size: 15, weight: .semibold)).tint(Theme.olive).frame(height: 36)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let t {
                let rows = t.tasks.filter { !$0.done } + t.tasks.filter(\.done)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, task in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 52) }
                        row(task)
                    }
                    if !rows.isEmpty { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 52) }
                    Button { newTask = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .bold)).frame(width: 24, height: 24).foregroundStyle(Theme.olive)
                            Text(rows.isEmpty ? "Перша справа на цей день" : "Нова справа").font(.system(size: 16)).foregroundStyle(Theme.muted)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .coordinateSpace(name: "flist")
                .onPreferenceChange(RowFrames.self) { frames = $0 }
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .simultaneousGesture(slideToPick(rows))
                if rows.contains(where: { !$0.done }) && sel.isEmpty {
                    Text("Затисни справу й веди пальцем — виберуться кілька для фокусу.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 2)
                }
            } else {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.paper).frame(height: 160).opacity(0.6)
            }
        }
    }

    /// press a task and slide: every open task under the finger joins the pick (like a to-do app made for focus)
    private func slideToPick(_ rows: [TaskItem]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("flist")))
            .onChanged { v in
                guard case .second(true, let drag) = v else { return }
                if !sliding { sliding = true; justSlid = true; Haptic.hit(.medium) }
                guard let drag else { return }
                if let id = frames.first(where: { $0.value.contains(drag.location) })?.key,
                   let task = rows.first(where: { $0.id == id }), !task.done, !sel.contains(id) {
                    _ = withAnimation(.snappy(duration: 0.2)) { sel.insert(id) }
                    Haptic.hit(.light, 0.7)
                }
            }
            .onEnded { _ in
                sliding = false
                Task { try? await Task.sleep(for: .milliseconds(350)); justSlid = false }
            }
    }


    private func goal(_ t: TaskDay?, today: String) -> some View {
        let total = t?.total ?? 0, done = t?.done ?? 0
        let pc = total > 0 ? Int((Double(done) / Double(total) * 100).rounded()) : 0
        let dots = min(10, total), on = total > 0 ? Int((Double(done) / Double(total) * Double(dots)).rounded()) : 0
        let label = day == today ? "сьогодні" : (dateOf(day)?.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA"))) ?? day)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text("\(pc)%").font(.system(size: 56, weight: .regular)).tracking(-1.5).lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(t == nil ? "…" : "\(done) з \(total)\nзроблено").font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 4), count: 5), spacing: 4) {
                ForEach(0..<dots, id: \.self) { i in Circle().fill(i < on ? Theme.olive : Color(hex: 0xE6E1D5)).frame(width: 18, height: 18) }
            }
            .frame(width: 106)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func row(_ t: TaskItem) -> some View {
        let picked = sel.contains(t.id)
        var bits: [String] = []
        if t.important { bits.append("важливо") }
        if t.assignee == "us" { bits.append("нам") } else if t.assignee == "partner" { bits.append("для: \(partner)") } else if t.createdBy == "partner" { bits.append("від: \(partner)") }
        if let m = t.minutes { bits.append("\(m) хв") }
        if let r = repeatText(t.repeat) { bits.append(r) }
        if !t.items.isEmpty { bits.append("\(t.items.filter(\.done).count)/\(t.items.count)") }
        return HStack(spacing: 14) {
            Button { if sel.isEmpty { Task { await setDone(t, !t.done) } } else { toggle(t) } } label: {
                ZStack {
                    Circle().stroke(picked || t.done ? Theme.ink : Color(hex: 0xB9AE9F), lineWidth: 1.6)
                    if t.done { Circle().fill(Theme.ink); Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.cream) }
                    if picked { Circle().fill(Theme.ink).padding(5) }
                }
                .frame(width: 24, height: 24).contentShape(Circle().inset(by: -8))
            }
            .buttonStyle(PressScale())
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 16.5, weight: .medium)).lineLimit(2)
                    .foregroundStyle(t.done ? Color(hex: 0xA99C8D) : (!sel.isEmpty && !picked ? Theme.muted : Theme.ink))
                if !bits.isEmpty {
                    Text(bits.joined(separator: " · ")).font(.system(size: 12)).lineLimit(1)
                        .foregroundStyle(t.assignee == "partner" || t.createdBy == "partner" ? Color(hex: 0x4F6F95) : Theme.muted)
                        .opacity(t.done ? 0.6 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 14).padding(.trailing, 16).padding(.vertical, 13)
        .background(picked ? Color(hex: 0xE6E0D3) : .clear)
        .contentShape(Rectangle())
        .background(GeometryReader { g in Color.clear.preference(key: RowFrames.self, value: [t.id: g.frame(in: .named("flist"))]) })
        .onTapGesture { if justSlid { return }; if sel.isEmpty { opened = t } else { toggle(t) } }
    }

    private func toggle(_ t: TaskItem) {
        guard !t.done else { return }
        withAnimation(.snappy(duration: 0.2)) {
            if sel.contains(t.id) { sel.remove(t.id) } else { sel.insert(t.id) }
            if sel.isEmpty { card = false }
        }
        Haptic.hit(.light)
    }

    // MARK: the round timer button and the focus card that grows out of it

    @ViewBuilder private var focusLayer: some View {
        if mode == .tasks && !sel.isEmpty {
            ZStack(alignment: .bottomTrailing) {
                if card {
                    Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { card = false } }
                        .transition(.opacity)
                    focusCard
                } else {
                    Button { withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { card = true }; Haptic.hit(.medium) } label: {
                        Image(systemName: "timer").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.cream)
                            .frame(width: 58, height: 58)
                            .background { Circle().fill(Theme.ink).matchedGeometryEffect(id: "focus", in: morph) }
                            .shadow(color: Theme.ink.opacity(0.3), radius: 12, y: 8)
                    }
                    .buttonStyle(PressScale())
                    .padding(.trailing, 18).padding(.bottom, 18)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private var focusCard: some View {
        let time: String = fview == .clock ? Date().shortTime : fview == .stopwatch ? "00:00" : fview == .minimal ? "\(fmin) хв" : String(format: "%02d:00", fmin)
        let adjustable = fview == .timer || fview == .minimal
        return VStack(spacing: 14) {
            Menu {
                Picker("Вигляд", selection: $fview) { ForEach(FocusView.allCases, id: \.self) { v in Text(v.title).tag(v) } }
            } label: {
                HStack(spacing: 5) { Text(fview.title).font(.system(size: 14, weight: .semibold)); Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)) }
                    .foregroundStyle(Color(hex: 0xC7CCD3))
            }
            HStack {
                step("minus", -5).opacity(adjustable ? 1 : 0.25).disabled(!adjustable)
                Spacer()
                Text(time).font(.system(size: 64, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText()).foregroundStyle(Color(hex: 0xE9ECEF))
                Spacer()
                step("plus", 5).opacity(adjustable ? 1 : 0.25).disabled(!adjustable)
            }
            Button { startFocus() } label: {
                Text("Почати фокус" + (sel.count > 1 ? " · \(sel.count) справи" : "")).font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 54).background(Color(hex: 0xF4F4F5), in: Capsule()).foregroundStyle(Color(hex: 0x111111))
            }
            .buttonStyle(PressScale())
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 18)
        .background { RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color(hex: 0x0F0F10)).matchedGeometryEffect(id: "focus", in: morph) }
        .padding(.horizontal, 12).padding(.bottom, 10)
        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.08)), removal: .opacity.animation(.easeIn(duration: 0.1))))
    }

    private func step(_ icon: String, _ d: Int) -> some View {
        Button { withAnimation(.snappy) { fmin = min(180, max(5, fmin + d)) }; Haptic.hit(.light) } label: {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44)
                .background(Color(hex: 0x1F2023), in: Circle()).foregroundStyle(Color(hex: 0xC7CCD3))
        }
        .buttonStyle(PressScale())
    }

    private func startFocus() {
        let q = (list?.tasks ?? []).filter { sel.contains($0.id) && !$0.done }.map { QueueItem(id: $0.id, title: $0.title) }
        guard let first = q.first else { return }
        prep = TimerPrep(name: first.title, minutes: fview == .timer || fview == .minimal ? fmin : 600, sub: "ФОКУС", queue: q, idx: 0, view: fview, autostart: true)
        withAnimation(.snappy) { card = false; sel = [] }
        switchTo(.timer)
    }

    private func setDone(_ t: TaskItem, _ on: Bool) async {
        Haptic.hit(on ? .heavy : .light)
        _ = try? await API.current().patchTask(t.id, API.TaskPatch(done: on, date: day))
        await loadTasks()
    }

    private func toTimer(_ t: TaskItem) {
        prep = TimerPrep(name: t.title, minutes: t.minutes ?? 25, sub: t.createdBy == "partner" ? "ВІД: \(partner.uppercased())" : "ЗАДАЧА", taskId: t.id, queue: [QueueItem(id: t.id, title: t.title)])
        switchTo(.timer)
    }

    // MARK: Рутина

    private var routinesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let rs = routines {
                if rs.isEmpty {
                    Text("Рутина — це ланцюжок кроків з часом для дисципліни: «20 хв англійська → 30 хв комп’ютер». \(partner) теж бачить твої серії.")
                        .font(.system(size: 14.5)).foregroundStyle(Theme.muted).padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                ForEach(rs) { r in routineCard(r) }
            } else {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.paper).frame(height: 150).opacity(0.6)
            }
            bigButton("Нова рутина", "plus") { newRoutine = true }
        }
    }

    private func routineCard(_ r: Routine) -> some View {
        let all = max(1, r.steps.reduce(0) { $0 + $1.minutes })
        let daysText = r.days.count == 7 ? "щодня" : r.days.map(wdName).joined(separator: ", ")
        let streakText = r.doneToday ? "сьогодні ✓" : "серія: \(r.streak) " + dayWord(r.streak)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: routineSymbol(r.icon)).foregroundStyle(Theme.olive)
                Text(r.title).font(.system(size: 17, weight: .bold))
                Spacer()
                Text("\(daysText) · \(r.minutes) хв").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            GeometryReader { g in
                let room = g.size.width - CGFloat(max(0, r.steps.count - 1)) * 6
                HStack(spacing: 6) {
                    ForEach(Array(r.steps.enumerated()), id: \.offset) { i, s in
                        Text("\(s.minutes) хв · \(s.name)").font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(width: max(30, room * CGFloat(s.minutes) / CGFloat(all)), height: 40, alignment: .leading)
                            .background(routineColors[i % routineColors.count], in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(height: 40).clipped()
            HStack {
                Text((r.owner == "partner" ? "\(partner) · " : "") + streakText).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                if r.owner == "me" {
                    Button { run(r) } label: {
                        Text(r.doneToday ? "Ще раз" : "Почати").font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16).frame(height: 38).background(Theme.ink, in: Capsule()).foregroundStyle(Theme.cream)
                    }
                    .buttonStyle(PressScale())
                }
            }
            HStack(spacing: 4) {
                ForEach(r.week, id: \.date) { w in
                    Capsule().fill(w.done ? Theme.olive : Color(hex: 0xE6E1D5)).frame(height: 6).opacity(w.on || w.done ? 1 : 0.35)
                }
            }
        }
        .padding(16)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contextMenu {
            if r.owner == "me" {
                Button("Видалити рутину", role: .destructive) { Task { try? await API.current().deleteRoutine(r.id); await loadRoutines() } }
            }
        }
    }

    private func dayWord(_ n: Int) -> String {
        if n % 10 == 1 && n % 100 != 11 { return "день" }
        if (2...4).contains(n % 10) && !(12...14).contains(n % 100) { return "дні" }
        return "днів"
    }

    private func run(_ r: Routine) {
        guard let first = r.steps.first else { return }
        prep = TimerPrep(name: first.name, minutes: first.minutes, sub: "РУТИНА «\(r.title.uppercased())»", routine: r, step: 0)
        switchTo(.timer)
    }

    /// the timer ran out: a routine gets its next step ready (it waits for ▶), or is marked done
    private func finished() async {
        guard let r = prep.routine else { return }
        let n = prep.step + 1
        if n < r.steps.count {
            prep = TimerPrep(name: r.steps[n].name, minutes: r.steps[n].minutes, sub: prep.sub, routine: r, step: n)
        } else {
            try? await API.current().routineDone(r.id)
            Haptic.ok()
            prep = TimerPrep()
            await loadRoutines()
        }
    }

    // MARK: helpers

    private func bigButton(_ t: String, _ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Label(t, systemImage: icon).font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
        }
        .buttonStyle(PressScale()).padding(.top, 2)
    }

    private func dateOf(_ s: String) -> Date? {
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private func loadTasks() async {
        if let r = try? await API.current().tasks(day) { list = r }
    }
    private func loadRoutines() async {
        if let r = try? await API.current().routines() { routines = r }
    }
}

/// a button that sinks a little under the finger
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - the timer: the lock-screen look Viktor chose — 12 pt from the sides, a tall dark card, a light card tucked under it,
// a dark tray with the week and two rings, round buttons at the bottom. It starts only with ▶.

struct TimerScreen<Top: View>: View {
    @Binding var prep: TimerPrep
    let partner: String
    var onClose: () -> Void
    var onFinished: () async -> Void
    @ViewBuilder var top: (String) -> Top
    @State private var pair: PomoPair?
    @State private var busy = false
    @State private var setting = false
    @State private var sideways: UIDeviceOrientation?
    private let bg = Color(hex: 0x2A2D31)
    private let pale = Color(hex: 0xC7CCD3)
    private let dark = Color(hex: 0x111111)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let me = pair?.me
            let total = max(1, me?.total ?? prep.minutes * 60)
            let left = me?.leftNow ?? total
            VStack(spacing: 0) {
                VStack(spacing: -22) {
                    bigCard(me, left: left, total: total).zIndex(1)
                    lightCard(me)
                }
                Spacer(minLength: 14)
                tray(left: left, total: total)
                controls(me)
            }
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 10)
        }
        .background(bg.ignoresSafeArea())
        .task {
            pair = try? await API.current().pomo()
            if prep.autostart {
                prep.autostart = false
                if pair?.me != nil { try? await API.current().stopPomo() ; pair = PomoPair(me: nil, partner: pair?.partner) }
                await play()
            }
        }
        // sideways: a desk clock — the task large, the time small; the screen stays awake
        .overlay { if let o = sideways { desk(o) } }
        .onAppear { UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let o = UIDevice.current.orientation
            withAnimation(.easeInOut(duration: 0.3)) {
                if o.isLandscape { sideways = o } else if o == .portrait || o == .portraitUpsideDown { sideways = nil }
            }
            UIApplication.shared.isIdleTimerDisabled = sideways != nil && pair?.me != nil
        }
        .task(id: pair?.me?.endsAt) { await waitForEnd() }
        .sheet(isPresented: $setting) { TimerSetSheet(prep: $prep, partner: partner).presentationDetents([.medium, .large]) }
        .sensoryFeedback(.impact(weight: .heavy), trigger: pair?.me?.startedAt)
    }

    private var name: String { prep.queue.isEmpty ? (pair?.me?.activity ?? prep.name) : prep.name }

    /// what the big card shows
    private func digits(_ me: PomoState?, left: Int, total: Int) -> String {
        switch prep.view {
        case .clock: return Date().shortTime
        case .stopwatch:
            let s = me == nil ? 0 : total - left
            return s >= 3600 ? String(format: "%d:%02d", s / 3600, s / 60 % 60) : String(format: "%02d:%02d", s / 60, s % 60)
        default: return String(format: "%02d:%02d", left / 60, left % 60)
        }
    }

    private func bigCard(_ me: PomoState?, left: Int, total: Int) -> some View {
        let uk = Locale(identifier: "uk_UA")
        let now = Date()
        let label = "\(now.formatted(.dateTime.weekday(.abbreviated).locale(uk))) \(Dock.calendar.component(.day, from: now)) · \(name.uppercased())"
        return VStack(spacing: 0) {
            top(label)
            Color.clear.frame(height: 236)
                .overlay {
                    if prep.view == .minimal {
                        Text(name).font(.system(size: fit(name) * 1.5, weight: .heavy)).multilineTextAlignment(.center).lineLimit(4).minimumScaleFactor(0.5).padding(.horizontal, 6)
                    } else {
                    Text(digits(me, left: left, total: total))
                        .font(.system(size: 166, weight: .medium)).monospacedDigit().tracking(-3)
                        .lineLimit(1).fixedSize()
                        .scaleEffect(x: 0.62, y: 1.3)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: left)
                    }
                }
            GeometryReader { g in
                Capsule().fill(Color(hex: 0x2A2C30))
                    .overlay(alignment: .leading) { Capsule().fill(pale).frame(width: g.size.width * CGFloat(total - left) / CGFloat(total)) }
            }
            .frame(height: 4).padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 6)
        }
        .foregroundStyle(pale)
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
        .background(Color(hex: 0x0F0F10), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private func lightCard(_ me: PomoState?) -> some View {
        let sub = me.map { $0.paused ? "ПАУЗА" : $0.together ? "РАЗОМ" : prep.sub } ?? prep.sub
        let line1: String
        let line2: String
        if !prep.queue.isEmpty {
            let q = prep.queue
            line1 = q.count > 1 ? "Справа \(prep.idx + 1) з \(q.count)." : "Одна справа — без перемикань."
            line2 = prep.idx + 1 < q.count ? "Далі — \(q[prep.idx + 1].title)." : "Остання — потім перерва."
        } else if let r = prep.routine {
            line1 = "Крок \(prep.step + 1) з \(r.steps.count)."
            line2 = prep.step + 1 < r.steps.count ? "Далі — \(r.steps[prep.step + 1].minutes) хв \(r.steps[prep.step + 1].name)." : "Останній крок — потім серія +1."
        } else if let me {
            line1 = "До \(me.endsAt.shortTime)."
            line2 = "\(partner) бачить твій таймер."
        } else {
            line1 = "\(prep.minutes) хвилин."
            line2 = "Старт — кнопкою ▶. Праворуч — інша справа й час."
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text(name.uppercased()).font(.system(size: fit(name), weight: .heavy)).lineLimit(2).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 16, weight: .heavy)).tracking(0.6).lineLimit(1).minimumScaleFactor(0.7).padding(.top, 2)
            Rectangle().frame(width: 110, height: 2).padding(.vertical, 16)
            Text(line1).font(.system(size: 15, weight: .bold))
            Text(line2).font(.system(size: 12)).padding(.top, 2)
            if !prep.queue.isEmpty {
                Button { Task { await queueDone() } } label: {
                    Label(prep.idx + 1 < prep.queue.count ? "Готово · далі" : "Готово", systemImage: "checkmark").font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity).frame(height: 48).background(dark, in: Capsule()).foregroundStyle(pale)
                }
                .buttonStyle(PressScale()).disabled(busy).padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 40).padding(.bottom, 20)
        .background(pale, in: UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
        .foregroundStyle(dark)
    }

    /// the bold title shrinks so a long word never breaks in the middle
    private func fit(_ t: String) -> CGFloat {
        let n = t.split(separator: " ").map(\.count).max() ?? 0
        return n <= 10 ? 34 : n <= 13 ? 28 : n <= 16 ? 23 : 19
    }

    private func tray(left: Int, total: Int) -> some View {
        let cal = Dock.calendar
        let monday = Evening.monday(of: Date())
        let dates = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
        let her = pair?.partner
        return HStack(spacing: 10) {
            Text("\(cal.component(.day, from: Date()))").font(.system(size: 22, weight: .semibold)).padding(.trailing, 2)
            Grid(horizontalSpacing: 4, verticalSpacing: 3) {
                GridRow { ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { w in Text(weekdayNames[w]).font(.system(size: 10)).opacity(0.6).frame(maxWidth: .infinity) } }
                GridRow {
                    ForEach(dates, id: \.self) { d in
                        let today = cal.isDateInToday(d)
                        Text("\(cal.component(.day, from: d))").font(.system(size: 10, weight: today ? .bold : .regular))
                            .frame(width: 17, height: 17)
                            .background(today ? pale : .clear, in: Circle())
                            .foregroundStyle(today ? dark : pale.opacity(0.6))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            ring(Double(total - left) / Double(total), pale, "\(Int((Double(left) / 60).rounded(.up)))", "хв")
            ring(her.map { 1 - Double($0.leftNow) / Double(max(1, $0.total)) } ?? 0, Color(hex: 0x8FB0D6), String(partner.prefix(1)), her.map { String($0.activity.prefix(8)) } ?? "вільна")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(hex: 0x1B1C1F), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .foregroundStyle(pale)
    }

    private func ring(_ frac: Double, _ color: Color, _ label: String, _ small: String) -> some View {
        ZStack {
            Circle().stroke(Color(hex: 0x3B3E43), lineWidth: 5)
            Circle().trim(from: 0, to: max(0, min(1, frac))).stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(label).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                Text(small).font(.system(size: 8)).opacity(0.7).lineLimit(1)
            }
            .padding(.horizontal, 6)
        }
        .padding(4)
        .frame(width: 58, height: 58)
    }

    private func controls(_ me: PomoState?) -> some View {
        HStack {
            round(me != nil ? "stop.fill" : "xmark") {
                if me != nil { await stop() } else { onClose() }
            }
            Spacer()
            Button { Task { await play() } } label: {
                Image(systemName: me != nil && me?.paused == false ? "pause.fill" : "play.fill").font(.system(size: 22))
                    .frame(width: 84, height: 58).background(pale, in: Capsule()).foregroundStyle(dark)
            }
            .buttonStyle(PressScale()).disabled(busy)
            Spacer()
            round("slider.horizontal.3") { setting = true }
        }
        .padding(.horizontal, 10).padding(.top, 16)
    }

    private func round(_ icon: String, _ a: @escaping () async -> Void) -> some View {
        Button { Task { await a() } } label: {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                .frame(width: 58, height: 58).background(Color(hex: 0x3B3E43), in: Circle()).foregroundStyle(Color(hex: 0xE9ECEF))
        }
        .buttonStyle(PressScale()).disabled(busy)
    }

    private func play() async {
        busy = true; defer { busy = false }
        if pair?.me != nil {
            let m = try? await API.current().pausePomo()
            pair = PomoPair(me: m, partner: pair?.partner)
            if let m, m.paused { LiveTasks.remove("pomo") } else if let m { LiveTasks.add(id: "pomo", title: "⏱ \(m.activity)", start: Date(), end: m.endsAt) }
            Haptic.hit(.medium)
            return
        }
        let act = prep.queue.count > 1 ? "\(prep.name) +\(prep.queue.count - 1)" : prep.name
        if let m = try? await API.current().startPomo(act, minutes: prep.minutes, together: prep.together) {
            pair = PomoPair(me: m, partner: pair?.partner)
            LiveTasks.add(id: "pomo", title: "⏱ \(prep.name)", start: Date(), end: m.endsAt)
        }
    }

    private func stop() async {
        busy = true; defer { busy = false }
        try? await API.current().stopPomo()
        LiveTasks.remove("pomo")
        pair = PomoPair(me: nil, partner: pair?.partner)
        Haptic.hit(.light)
    }

    private func desk(_ o: UIDeviceOrientation) -> some View {
        GeometryReader { g in
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let me = pair?.me
                let total = max(1, me?.total ?? prep.minutes * 60)
                HStack(alignment: .bottom) {
                    Text(name).font(.system(size: 44, weight: .bold)).lineLimit(3).minimumScaleFactor(0.5).foregroundStyle(Color(hex: 0xF2F2F2))
                    Spacer(minLength: 20)
                    Text(digits(me, left: me?.leftNow ?? total, total: total)).font(.system(size: 18, weight: .medium)).monospacedDigit().foregroundStyle(Color(hex: 0xF2F2F2).opacity(0.55))
                }
                .padding(.horizontal, 44).padding(.bottom, 36)
                .frame(width: g.size.height, height: g.size.width, alignment: .bottomLeading)
                .rotationEffect(.degrees(o == .landscapeLeft ? 90 : -90))
                .frame(width: g.size.width, height: g.size.height)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .transition(.opacity)
    }

    /// the current task of the session is done: the next comes up, the timer keeps going; after the last — rest
    private func queueDone() async {
        guard prep.idx < prep.queue.count else { return }
        busy = true; defer { busy = false }
        let cur = prep.queue[prep.idx]
        _ = try? await API.current().patchTask(cur.id, API.TaskPatch(done: true, date: Evening.iso(Date())))
        Haptic.hit(.heavy)
        if prep.idx + 1 < prep.queue.count {
            withAnimation(.snappy) { prep.idx += 1; prep.name = prep.queue[prep.idx].title }
            return
        }
        Haptic.ok()
        try? await API.current().stopPomo()
        LiveTasks.remove("pomo")
        pair = PomoPair(me: nil, partner: pair?.partner)
        prep = TimerPrep()
        onClose()
    }

    private func waitForEnd() async {
        guard let me = pair?.me, !me.paused else { return }
        let wait = me.endsAt.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        if Task.isCancelled { return }
        Haptic.ok()
        try? await API.current().stopPomo()
        LiveTasks.remove("pomo")
        pair = PomoPair(me: nil, partner: pair?.partner)
        await onFinished()
    }
}

/// ⚙ of the timer: what we do and for how long
struct TimerSetSheet: View {
    @Binding var prep: TimerPrep
    let partner: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var minutes = 25
    @State private var together = false
    private let names = ["Англійська", "Комп’ютер", "Книжка", "Робота", "Прибирання", "Спорт"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Що робимо?").font(.serif(28, .bold))
                TextField("Справа", text: $name).font(.system(size: 16)).padding(.horizontal, 16).frame(height: 50)
                    .background(Theme.cream, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(names, id: \.self) { n in
                            Button { name = n; Haptic.hit(.light) } label: {
                                Text(n).font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 14).frame(height: 38)
                                    .background(name == n ? Theme.olive : Theme.cream, in: Capsule()).foregroundStyle(name == n ? Theme.cream : Theme.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Хвилин").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                HStack(spacing: 4) {
                    ForEach([10, 15, 25, 45, 60, 90], id: \.self) { m in
                        Button { minutes = m; Haptic.hit(.light) } label: {
                            Text("\(m)").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 38)
                                .background(minutes == m ? Theme.ink : .clear, in: Capsule()).foregroundStyle(minutes == m ? Theme.cream : Theme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4).background(Theme.cream, in: Capsule())
                Stepper("Точно: \(minutes) хв", value: $minutes, in: 1...240).font(.system(size: 15))
                Toggle("Разом — \(partner) отримає запрошення", isOn: $together).font(.system(size: 15)).tint(Theme.olive)
                Button {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    prep = TimerPrep(name: n.isEmpty ? "Фокус" : n, minutes: minutes, sub: "ТАЙМЕР", together: together)
                    dismiss()
                } label: {
                    Text("Готово").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 54)
                        .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                }
                .buttonStyle(PressScale())
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .onAppear { name = prep.name; minutes = prep.minutes; together = prep.together }
    }
}
