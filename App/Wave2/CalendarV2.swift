import SwiftUI

/// Цей тиждень: each day shows both of us as day strips and whether the evening is good for a date.
struct WeekPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @State private var start = Evening.monday(of: Date())
    @State private var days: [DayPlan] = []
    @State private var schedule: ScheduleResult?
    @State private var showSchedule = false
    @State private var invite: String?
    @State private var error: String?
    private var cal: Calendar { Dock.calendar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageTitle(plain: "Цей", italic: "тиждень", sub: subtitle)
                HStack(spacing: 8) {
                    navButton("← тиждень") { move(-7) }
                    navButton("Сьогодні") { start = Evening.monday(of: Date()); Task { await load() } }
                    navButton("тиждень →") { move(7) }
                }
                legend
                Button { showSchedule = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Наш розклад").font(.system(size: 14, weight: .semibold))
                            Text("робота, справи, мої вихідні").font(.system(size: 12)).opacity(0.65)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(14).background(Theme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).foregroundStyle(Theme.paper)
                }
                if schedule?.rules.isEmpty == true {
                    EmptyCard(text: "Додай свій розклад роботи — тоді календар сам покаже вільні вечори.")
                }
                ForEach(days) { d in dayRow(d) }
                if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coffee) }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 120)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .task { await load() }
        .sheet(isPresented: $showSchedule, onDismiss: { Task { await load() } }) { ScheduleSheet() }
        .fullScreenCover(item: Binding(get: { invite.map { DayID(id: $0) } }, set: { invite = $0?.id })) { d in InviteBooking(start: .day(d.id)) }
    }

    private var subtitle: String {
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let f = DateFormatter(); f.locale = Locale(identifier: "uk_UA"); f.dateFormat = "d MMMM"
        let free = days.filter { $0.isFree && $0.date >= Evening.iso(Date()) }.count
        return "\(cal.component(.day, from: start))–\(f.string(from: end))" + (days.isEmpty ? "" : " · \(free) вільні вечори")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("робота", AnyShapeStyle(Color(hex: 0xD8CFC2)))
            legendItem("справи", AnyShapeStyle(Color(hex: 0xA59E91)))
            legendItem("події", AnyShapeStyle(Theme.coffee))
            legendItem("наше", AnyShapeStyle(Theme.olive))
        }
        .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
    }
    private func legendItem(_ t: String, _ s: AnyShapeStyle) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 3).fill(s).frame(width: 12, height: 8); Text(t) }
    }
    private func navButton(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(t, action: a).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
            .background(Theme.paper, in: Capsule()).foregroundStyle(Theme.ink)
    }

    private func dayRow(_ d: DayPlan) -> some View {
        let today = Evening.iso(Date())
        let date = Evening.date(d.date) ?? Date()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "uk_UA")))).font(.system(size: 15, weight: .semibold))
                + Text(" \(cal.component(.day, from: date)) \(date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "uk_UA"))))\(d.date == today ? " · сьогодні" : "")").font(.system(size: 13)).foregroundColor(Theme.muted)
                Spacer()
                EveningBadge(day: d) { if d.isFree && d.date >= today { invite = d.date } }
                    .opacity(d.date < today ? 0.5 : 1)
            }
            DayLane(letter: String(state.me?.name.prefix(1) ?? "Я"), blocks: d.blocks.me, off: d.meOff, known: d.meKnown ?? true)
            DayLane(letter: String(state.partner?.name.prefix(1) ?? "?"), blocks: d.blocks.partner, off: d.partnerOff, known: d.partnerKnown ?? true)
            Text(Evening.note(d, partner: state.partner?.name ?? "")).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .background(d.date == today ? Color(hex: 0xF3E6D8) : Theme.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.coffee, lineWidth: d.date == today ? 1.5 : 0))
        .grayscale(d.date < today ? 1 : 0).opacity(d.date < today ? 0.5 : 1)
    }

    private func move(_ n: Int) { start = cal.date(byAdding: .day, value: n, to: start) ?? start; Task { await load() } }

    private func load() async {
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        do {
            async let a = API.current().availability(from: Evening.iso(start), to: Evening.iso(end))
            async let s = API.current().schedule()
            let (d, sc) = try await (a, s)
            days = d
            schedule = sc
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct DayID: Identifiable { let id: String }

struct EveningBadge: View {
    let day: DayPlan
    var action: () -> Void
    var body: some View {
        let (bg, fg, icon): (Color, Color, String?) = {
            switch day.status {
            case "free", "day": return (Theme.olive, Theme.cream, day.status == "day" ? "sun.max.fill" : "heart.fill")
            case "home": return (Theme.tan, Theme.ink, "tv.fill")
            case "maybe": return (Theme.tan.opacity(0.5), Theme.coffee, "questionmark")
            case "plan": return (Theme.coffee, Theme.cream, "heart.fill")
            default: return (Color(hex: 0xECE7DE), Color(hex: 0x9A9284), nil)
            }
        }()
        return Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(Evening.label(day)).lineLimit(1).strikethrough(day.status == "busy")
            }
            .font(.system(size: 12, weight: .bold)).padding(.horizontal, 11).frame(height: 28)
            .background(bg, in: Capsule()).foregroundStyle(fg)
        }
        .buttonStyle(.plain)
    }
}

/// One person's day from 8:00 to 24:00; dashed line at 19:00.
struct DayLane: View {
    let letter: String
    let blocks: [DayBlock]
    let off: Bool
    var known: Bool = true
    var body: some View {
        HStack(spacing: 8) {
            Text(letter).font(.serif(12, .bold)).foregroundStyle(Theme.muted).frame(width: 16)
            GeometryReader { g in
                let w = g.size.width
                let x = { (m: Int) -> CGFloat in CGFloat(max(0, min(16 * 60, m - 8 * 60))) / CGFloat(16 * 60) * w }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xF1ECE3))
                    if !known && blocks.isEmpty { Text("графік не внесено").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.muted).padding(.leading, 8) }
                    else if off && blocks.isEmpty { Text("ВИХІДНИЙ").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.olive).padding(.leading, 8) }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                        let a = x(Evening.minutes(b.start)), e = x(Evening.minutes(b.end))
                        Capsule().fill(fill(b.kind)).frame(width: max(6, e - a)).offset(x: a)
                            .overlay(alignment: .leading) {
                                if b.kind != "work", let l = b.label { Text(l).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.cream).lineLimit(1).padding(.leading, 6).frame(width: max(6, e - a), alignment: .leading).offset(x: a) }
                            }
                    }
                    Rectangle().fill(Theme.olive.opacity(0.5)).frame(width: 1.5, height: 20).offset(x: x(19 * 60))
                }
            }
            .frame(height: 14)
        }
    }
    private func fill(_ k: String) -> Color {
        switch k {
        case "work": return Color(hex: 0xD8CFC2)
        case "activity": return Color(hex: 0xA59E91)
        case "maybe": return Color(hex: 0xA59E91).opacity(0.55)
        case "ours": return Theme.olive
        default: return Theme.coffee
        }
    }
}

/// Місяць as a poster: big month name, grid with events inside, busy evenings hatched, ♥ on free ones.
struct MonthPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @State private var month = Date()
    @State private var days: [DayPlan] = []
    @State private var invite: String?
    private var cal: Calendar { Dock.calendar }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("МІСЯЦЬ").font(.system(size: 11, weight: .bold)).tracking(1).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.coffee, in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(Theme.cream)
                Text("\(cal.component(.year, from: month))").font(.system(size: 34, weight: .bold))
                Text(month.formatted(.dateTime.month(.wide).locale(Locale(identifier: "uk_UA"))).capitalized)
                    .font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.coffee)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 1.5).offset(y: 4) }
                HStack(spacing: 8) {
                    Button("← місяць") { shift(-1) }; Button("Цей") { month = Date(); Task { await load() } }; Button("місяць →") { shift(1) }
                }
                .font(.system(size: 13, weight: .semibold)).buttonStyle(.bordered).tint(Theme.ink).padding(.top, 8)
                grid
                HStack(spacing: 12) {
                    HStack(spacing: 4) { Capsule().fill(Color(hex: 0xC9A27E)).frame(width: 14, height: 4); Text("\(state.me?.name.prefix(1) ?? "") працює") }
                    HStack(spacing: 4) { Capsule().fill(Color(hex: 0x8DA06F)).frame(width: 14, height: 4); Text("\(state.partner?.name.prefix(1) ?? "") працює") }
                    HStack(spacing: 4) { Image(systemName: "heart.fill").foregroundStyle(Theme.olive); Text("обоє вільні") }
                }
                .font(.system(size: 11.5)).foregroundStyle(Theme.muted).padding(.top, 6)
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 120)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .task { await load() }
        .fullScreenCover(item: Binding(get: { invite.map { DayID(id: $0) } }, set: { invite = $0?.id })) { d in InviteBooking(start: .day(d.id)) }
    }

    private var grid: some View {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let blanks = (cal.component(.weekday, from: first) + 5) % 7
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let today = Evening.iso(Date())
        return LazyVGrid(columns: cols, spacing: 0) {
            ForEach(["пн", "вт", "ср", "чт", "пт", "сб", "нд"], id: \.self) { Text($0).font(.system(size: 11, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading).padding(4) }
            ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: 70) }
            ForEach(days) { d in
                let evs = store.events.filter { Evening.iso($0.startsAt) == d.date && $0.invitation?.status != .cancelled }
                Button { if d.isFree && d.date >= today { invite = d.date } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Evening.date(d.date).map { cal.component(.day, from: $0) } ?? 0)").font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, d.date == today ? 5 : 0).background(d.date == today ? Theme.coffee : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(d.date == today ? Theme.cream : (d.date < today ? Theme.muted : Theme.ink))
                        HStack(spacing: 2) {
                            Capsule().fill(d.blocks.me.contains { $0.kind == "work" } ? Color(hex: 0xC9A27E) : .clear).frame(height: 3)
                            Capsule().fill(d.blocks.partner.contains { $0.kind == "work" } ? Color(hex: 0x8DA06F) : .clear).frame(height: 3)
                        }
                        .opacity(d.date < today ? 0.5 : 1)
                        ForEach(evs.prefix(2)) { e in
                            Text(e.title).font(.system(size: 9.5)).lineLimit(1).padding(.horizontal, 3)
                                .background(e.isOurs ? Theme.olive : Theme.tan, in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(e.isOurs ? Theme.cream : Theme.ink)
                        }
                        Spacer(minLength: 0)
                        if d.date >= today {
                            HStack { Spacer(); if d.bothFree { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(Theme.olive) } else if d.isFree { Image(systemName: "heart").font(.system(size: 9)).foregroundStyle(Theme.olive.opacity(0.6)) } }
                                .frame(height: 10)
                                .background(d.status == "busy" || d.status == "home" ? Theme.muted.opacity(0.25) : d.status == "maybe" ? Theme.coffee.opacity(0.15) : .clear)
                        }
                    }
                    .padding(3).frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                    .background(d.date == today ? Color(hex: 0xF3E6D8) : d.date < today ? Color(hex: 0xF4F1EB) : Theme.paper)
                    .overlay(Rectangle().stroke(Theme.ink, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shift(_ n: Int) { month = cal.date(byAdding: .month, value: n, to: month) ?? month; Task { await load() } }

    private func load() async {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let last = cal.date(byAdding: DateComponents(month: 1, day: -1), to: first) else { return }
        days = (try? await API.current().availability(from: Evening.iso(first), to: Evening.iso(last))) ?? []
    }
}

/// All invitations, newest first.
struct InvitesPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @State private var open: Event?
    @State private var hidden: Set<String> = []
    @State private var shown: Set<String> = []
    @State private var showArchive = false

    private func archived(_ e: Event) -> Bool { !shown.contains(e.id) && (hidden.contains(e.id) || e.invitation?.archived == true) }

    var body: some View {
        let all = store.events.filter { $0.invitation != nil }.sorted { $0.startsAt > $1.startsAt }
        let list = all.filter { !archived($0) }
        let arch = all.filter { archived($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PageTitle(plain: "Наші", italic: "запрошення", sub: "\(list.filter { $0.invitation?.status == .pending }.count) чекають відповіді · свайп ліворуч — в архів")
                if list.isEmpty { EmptyCard(text: "Тут порожньо. Натисни «+» або «Вільний вечір» у календарі.") }
                ForEach(list) { e in
                    SwipeToArchive(onArchive: { archive(e, true) }) { row(e) }
                }
                if !arch.isEmpty {
                    Button { withAnimation(.snappy) { showArchive.toggle() } } label: {
                        Label("Архів · \(arch.count)", systemImage: showArchive ? "chevron.up" : "archivebox")
                            .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).frame(height: 44).background(Theme.ink.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    if showArchive {
                        ForEach(arch) { e in
                            row(e).opacity(0.8)
                                .overlay(alignment: .bottomTrailing) {
                                    Button("Повернути") { archive(e, false) }
                                        .font(.system(size: 12, weight: .bold)).padding(.horizontal, 12).frame(height: 28)
                                        .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream).padding(8)
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 120)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .fullScreenCover(item: $open) { e in InviteView(event: e) }
    }

    private func row(_ e: Event) -> some View {
        Button { open = e } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.title).font(.system(size: 15, weight: .semibold))
                    Text(e.startsAt.dayTime).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(status(e)).font(.system(size: 12, weight: .bold)).padding(.horizontal, 10).frame(height: 26)
                    .background(e.invitation?.status == .accepted ? Theme.olive : Theme.tan, in: Capsule())
                    .foregroundStyle(e.invitation?.status == .accepted ? Theme.cream : Theme.ink)
            }
            .padding(14).background(Theme.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func archive(_ e: Event, _ on: Bool) {
        withAnimation(.snappy) {
            if on { hidden.insert(e.id); shown.remove(e.id) } else { shown.insert(e.id); hidden.remove(e.id) }
        }
        Task { try? await API.current().archiveInvite(e.id, on) }
    }

    private func status(_ e: Event) -> String {
        let mine = e.createdBy == state.me?.id
        switch e.invitation?.status {
        case .accepted: return mine ? "\(state.partner?.name ?? ""): йдемо" : "йдемо"
        case .pending: return mine ? "чекає відповіді" : "чекає тебе"
        case .reschedule: return "інший день?"
        case .cancelled: return "скасовано"
        case nil: return ""
        }
    }
}

/// Наш розклад: rules of both, my own days (work / off / as usual) and a new rule.
struct ScheduleSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var data: ScheduleResult?
    @State private var kind = "work"
    @State private var label = ""
    @State private var days: Set<Int> = [1, 2, 3, 4, 5]
    @State private var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var end = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var error: String?
    @State private var shifts4: [ShiftDay4] = []
    @State private var monthOffset = 0
    @State private var pickDay: String?
    @State private var ownDay: DayID?
    @State private var ownStart = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var ownEnd = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()
    private let wd = ["нд", "пн", "вт", "ср", "чт", "пт", "сб"]

    var body: some View {
        NavigationStack {
            SoftForm {
                Section { Text("Звідси календар знає, коли ви обоє вільні. Вечір для побачення — обоє вільні приблизно з 19:30.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                if let data, !data.rules.contains(where: { $0.memberId == state.me?.id && $0.kind == "work" }) {
                    Section {
                        daysRow
                        DatePicker("Початок", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("Кінець", selection: $end, displayedComponents: .hourAndMinute)
                        Button("Зберегти мій графік") { kind = "work"; Task { await addRule() } }.disabled(days.isEmpty)
                    } header: { Text("Мій графік роботи") } footer: {
                        Text("Без нього календар не знає, коли ти зайнятий. \(state.partner?.name ?? "Партнер") вносить свій графік зі свого телефону.")
                    }
                }
                Section("Правила") {
                    ForEach(data?.rules ?? []) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text((r.memberId == state.me?.id ? state.me?.name : state.partner?.name) ?? "").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                Text((r.kind == "work" ? "Робота" : r.label ?? "Справа") + (r.sometimes ? " · інколи" : "")).font(.system(size: 15, weight: .semibold))
                                Text(r.weekdays.map { wd[$0] }.joined(separator: ", ") + " · \(r.start)–\(r.end)").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if r.memberId == state.me?.id {
                                Button(role: .destructive) { Task { await run { try await API.current().deleteRule(r.id) } } } label: { Image(systemName: "trash") }
                            }
                        }
                    }
                    if data?.rules.isEmpty == true { Text("Поки правил нема.").foregroundStyle(Theme.muted) }
                }
                Section {
                    shiftGrid
                } header: { Text("Мої змінні дні") } footer: { Text("Тап по дню: вихідний, робочий за графіком або свої години — для змінного графіка. Решта днів — як завжди.") }
                Section("Нове правило") {
                    Picker("Що", selection: $kind) { Text("Робота").tag("work"); Text("Справа").tag("activity"); Text("Інколи").tag("sometimes") }.pickerStyle(.segmented)
                    if kind != "work" { TextField("Назва (тренування, курси…)", text: $label) }
                    daysRow
                    DatePicker("Початок", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Кінець", selection: $end, displayedComponents: .hourAndMinute)
                    Button("Додати") { Task { await addRule() } }.disabled(days.isEmpty)
                    if let error { Text(error).foregroundStyle(Theme.coffee) }
                }
            }
            .navigationTitle("Наш розклад").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .task { await load() }
            .confirmationDialog(pickDay.flatMap { Evening.date($0) }.map { $0.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "uk_UA"))) } ?? "",
                                isPresented: Binding(get: { pickDay != nil }, set: { if !$0 { pickDay = nil } }), titleVisibility: .visible) {
                if let d = pickDay {
                    Button("Як завжди") { Task { await run { try await API.current().setShift4(date: d, value: nil) } } }
                    Button("Вихідний") { Task { await run { try await API.current().setShift4(date: d, value: "off") } } }
                    Button("Робочий за графіком") { Task { await run { try await API.current().setShift4(date: d, value: "work") } } }
                    Button("Свої години…") { ownDay = DayID(id: d) }
                }
            }
            .sheet(item: $ownDay) { d in
                NavigationStack {
                    SoftForm {
                        Section {
                            DatePicker("Початок", selection: $ownStart, displayedComponents: .hourAndMinute)
                            DatePicker("Кінець", selection: $ownEnd, displayedComponents: .hourAndMinute)
                        } footer: { Text("Цього дня календар вважатиме тебе зайнятою(им) лише в ці години.") }
                    }
                    .navigationTitle(Evening.date(d.id).map { $0.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA"))) } ?? d.id).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { ownDay = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Зберегти") { let s = hm(ownStart), e = hm(ownEnd); ownDay = nil; Task { await run { try await API.current().setShift4(date: d.id, value: "work", start: s, end: e) } } }
                                .disabled(hm(ownEnd) <= hm(ownStart))
                        }
                    }
                }
                .presentationDetents([.medium])
                .tint(Theme.olive)
            }
        }
        .tint(Theme.olive)
    }

    private var daysRow: some View {
        HStack(spacing: 4) {
            ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { i in
                Button(wd[i]) { if days.contains(i) { days.remove(i) } else { days.insert(i) } }
                    .font(.system(size: 12.5, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 34)
                    .background(days.contains(i) ? Theme.olive : Theme.paper, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(days.contains(i) ? Theme.cream : Theme.ink)
                    .buttonStyle(.plain)
            }
        }
    }

    private var shiftGrid: some View {
        let cal = Dock.calendar
        let now = Date()
        let cur = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let first = cal.date(byAdding: .month, value: monthOffset, to: cur) ?? cur
        let n = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let blanks = (cal.component(.weekday, from: first) + 5) % 7
        let mine = Dictionary(shifts4.filter { $0.memberId == state.me?.id }.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        return VStack(spacing: 8) {
        HStack {
            Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }.disabled(monthOffset <= 0).buttonStyle(.plain)
            Spacer()
            Text(first.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "uk_UA"))).capitalized).font(.system(size: 14, weight: .semibold))
            Spacer()
            Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }.disabled(monthOffset >= 3).buttonStyle(.plain)
        }
        .foregroundStyle(Theme.olive)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(["пн", "вт", "ср", "чт", "пт", "сб", "нд"], id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(Theme.muted) }
            ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: 40) }
            ForEach(1...n, id: \.self) { day in
                let date = cal.date(byAdding: .day, value: day - 1, to: first) ?? first
                let iso = Evening.iso(date)
                let sd = mine[iso]
                let v = sd?.value
                Button { pickDay = iso } label: {
                    VStack(spacing: 0) {
                        Text("\(day)").font(.system(size: 12, weight: .semibold))
                        Text(v == "off" ? "вих." : v == "work" ? (sd?.start.map { "\(short($0))–\(short(sd?.end ?? ""))" } ?? "роб.") : "·").font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(v == "off" ? Theme.olive : v == "work" ? Theme.tan : Theme.paper, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(v == "off" ? Theme.cream : Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
        }
    }

    /// "08:30" → "8:30", "14:00" → "14"
    private func short(_ s: String) -> String {
        let p = s.split(separator: ":"); guard let h = p.first.flatMap({ Int($0) }) else { return s }
        return p.count > 1 && p[1] != "00" ? "\(h):\(p[1])" : "\(h)"
    }

    private func hm(_ d: Date) -> String { let c = Calendar.current.dateComponents([.hour, .minute], from: d); return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0) }

    private func addRule() async {
        await run {
            try await API.current().addRule(.init(kind: kind == "work" ? "work" : "activity", label: label.isEmpty ? nil : label, weekdays: Array(days).sorted(),
                                                  start: hm(start), end: hm(end), sometimes: kind == "sometimes"))
        }
        label = ""
    }
    private func run(_ work: @escaping () async throws -> Void) async {
        do { try await work(); await load(); error = nil } catch { self.error = error.localizedDescription }
    }
    private func load() async {
        data = try? await API.current().schedule()
        shifts4 = (try? await API.current().schedule4().shifts) ?? shifts4
    }
}

/// Наша історія: coloured folders stacked; a tap opens one.
struct HistoryPage: View {
    @State private var folders: [ArchiveFolder] = []
    @State private var open = 4
    private let look: [String: (Color, Color)] = [
        "dates": (Theme.olive, Theme.cream), "watched": (Color(hex: 0xC9A27E), Theme.ink), "read": (Color(hex: 0x9FB08A), Theme.ink),
        "gifts": (Color(hex: 0xD8B28F), Theme.ink), "memories": (Color(hex: 0x8C5E3C), Theme.cream),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(plain: "Наша", italic: "історія", sub: "Папки — тап розгортає")
                VStack(spacing: -20) {
                    ForEach(Array(folders.enumerated()), id: \.element.id) { i, f in
                        let lk = look[f.kind] ?? (Theme.paper, Theme.ink)
                        Button { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { open = open == i ? -1 : i } } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(alignment: .top) {
                                    Text(f.title).font(.serif(27, .bold))
                                    Spacer()
                                    Text("\(f.count)").font(.system(size: 13, weight: .bold)).opacity(0.65)
                                }
                                if open == i {
                                    VStack(spacing: 0) {
                                        ForEach(f.items) { it in
                                            Divider().overlay(lk.1.opacity(0.15))
                                            HStack { Text(it.title).font(.system(size: 14)); Spacer(); Text(note(f.kind, it.note)).font(.system(size: 13)).opacity(0.65) }.padding(.vertical, 9)
                                        }
                                        if f.items.isEmpty { Text(f.kind == "memories" ? "Спогади з фото — згодом" : "Поки порожньо").font(.system(size: 14)).opacity(0.7).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10) }
                                    }
                                    .padding(.top, 10)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 26)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(lk.0, in: UnevenRoundedRectangle(topLeadingRadius: 26, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 26))
                            .foregroundStyle(lk.1)
                            .shadow(color: .black.opacity(0.1), radius: 9, y: -6)
                        }
                        .buttonStyle(.plain)
                        .zIndex(Double(i))
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 120)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .task { folders = (try? await API.current().archive()) ?? [] }
    }

    private func note(_ kind: String, _ n: String?) -> String {
        guard let n else { return "" }
        if kind == "dates", let d = ISO8601DateFormatter().date(from: n) ?? API.decoderDate(n) {
            return d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "uk_UA")))
        }
        return n
    }
}

extension API {
    /// ISO date with fractional seconds, as the server sends it.
    static func decoderDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
