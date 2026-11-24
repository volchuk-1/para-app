import SwiftUI
import ActivityKit
import UserNotifications

/// Календар: День · Тиждень · Місяць · Рік. Press and hold the mode button — our picker appears on top, slide to a mode,
/// let go. Day and week are the same hour grid (week = 7 columns). Tap an hour — until its end (this hour — from now);
/// press and drag down — several hours. A plan can start the olive timer.
struct CalendarPage: View {
    enum Mode: String, CaseIterable { case day, week, month, year
        var title: String { switch self { case .day: return "Сьогодні"; case .week: return "Тиждень"; case .month: return "Місяць"; case .year: return "Рік" } }
        var short: String { self == .day ? "День" : title }
    }
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @State private var mode: Mode = .day
    @State private var anchor = Date()
    @State private var days: [DayPlan] = []
    @State private var people: [Person] = []
    @State private var picking = false
    @State private var hot: Mode?
    @State private var pickerFrame: CGRect = .zero
    @State private var pressTask: Task<Void, Never>?
    @State private var plan: PlanDraft?
    @State private var showSchedule = false
    @State private var sel: (day: String, a: Int, b: Int)?
    @State private var invite: String?
    private var cal: Calendar { Dock.calendar }
    private let H0 = 7, H1 = 24, row: CGFloat = 52

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    Group {
                        switch mode {
                        case .day: hourList
                        case .week: strips
                        case .month: monthGrid
                        case .year: yearGrid
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .id(mode)
                    Button { showSchedule = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Наш розклад").font(.system(size: 14, weight: .semibold))
                                Text("робота, змінні дні з годинами, справи").font(.system(size: 12)).opacity(0.65)
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }
                        .padding(14).background(Theme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).foregroundStyle(Theme.paper)
                    }
                    if mode == .day || mode == .week {
                        Text(mode == .day ? "Тап по годині — справа до кінця години. Затисни годину й тягни вниз — кілька годин. Затисни кнопку вгорі — Тиждень, Місяць, Рік."
                             : "♥ — вечір, коли ви обоє вільні: тап — запросити. Тап по дню — його години.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 130)
            }
            .scrollDisabled(sel != nil)
            picker
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .task { await load() }
        .onChange(of: mode) { _, _ in Task { await load() } }
        .onChange(of: anchor) { _, _ in Task { await load() } }
        .sheet(item: $plan, onDismiss: { Task { await load() } }) { p in PlanSheet(draft: p) }
        .sheet(isPresented: $showSchedule, onDismiss: { Task { await load() } }) { ScheduleSheet() }
        .fullScreenCover(item: Binding(get: { invite.map { DayID(id: $0) } }, set: { invite = $0?.id })) { d in InviteBooking(start: .day(d.id)) }
        .sensoryFeedback(.selection, trigger: hot)
    }

    // MARK: header with the press-and-slide mode button

    private var subtitle: String {
        let uk = Locale(identifier: "uk_UA")
        switch mode {
        case .day: return (cal.isDateInToday(anchor) ? "сьогодні · " : "") + anchor.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(uk))
        case .week:
            let m = Evening.monday(of: anchor), e = cal.date(byAdding: .day, value: 6, to: m) ?? m
            return "\(cal.component(.day, from: m))–\(cal.component(.day, from: e)) \(e.formatted(.dateTime.month(.wide).locale(uk)))"
        case .month: return anchor.formatted(.dateTime.month(.wide).year().locale(uk)).capitalized
        case .year: return "\(cal.component(.year, from: anchor))"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title).font(.serif(34, .bold))
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.muted)
            }
            .padding(.trailing, 60)
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 38, height: 38).background(Theme.tan, in: Circle()) }
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 38, height: 38).background(Theme.tan, in: Circle()) }
                Spacer()
                HStack(spacing: 6) { Text(mode.title).font(.system(size: 14, weight: .semibold)); Text("затисни").font(.system(size: 10.5)).opacity(0.55) }
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(Theme.ink, in: Capsule()).foregroundStyle(Theme.paper)
                    .gesture(modeGesture)
            }
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
        }
    }

    private var modeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if pressTask == nil && !picking {
                    pressTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        if !Task.isCancelled { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { picking = true } }
                    }
                }
                if picking { hot = modeAt(v.location.x) }
            }
            .onEnded { _ in
                pressTask?.cancel(); pressTask = nil
                if picking {
                    let m = hot ?? mode
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { picking = false; mode = m }
                    hot = nil
                } else {
                    withAnimation(.snappy) { mode = .day; anchor = Date() }
                }
            }
    }

    private func modeAt(_ x: CGFloat) -> Mode {
        guard pickerFrame.width > 0 else { return mode }
        let i = Int(((x - pickerFrame.minX) / pickerFrame.width * 4).rounded(.down))
        return Mode.allCases[max(0, min(3, i))]
    }

    private var picker: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { m in
                Text(m.short).font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(hot == m ? Theme.olive : .clear, in: Capsule())
                    .foregroundStyle(hot == m ? Theme.cream : Theme.muted)
                    .scaleEffect(hot == m ? 1.05 : 1)
            }
        }
        .padding(6).frame(height: 56)
        .background(Theme.paper, in: Capsule())
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        .background(GeometryReader { g in Color.clear.onAppear { pickerFrame = g.frame(in: .global) }.onChange(of: g.frame(in: .global)) { _, f in pickerFrame = f } })
        .padding(.horizontal, 12).padding(.top, 6)
        .opacity(picking ? 1 : 0).scaleEffect(picking ? 1 : 0.96, anchor: .top).offset(y: picking ? 0 : -14)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: hot)
    }

    private func move(_ n: Int) {
        let unit: Calendar.Component = mode == .day ? .day : mode == .week ? .weekOfYear : mode == .month ? .month : .year
        anchor = cal.date(byAdding: unit, value: n, to: anchor) ?? anchor
    }

    // MARK: Сьогодні / Тиждень as before: both of us as day strips, ♥ on a free evening

    private var strips: some View {
        let list = gridDays
        let today = Evening.iso(Date())
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                legendItem("робота", Color(hex: 0xD8CFC2)); legendItem("справи", Color(hex: 0xA59E91))
                legendItem("події", Theme.coffee); legendItem("наше", Theme.olive)
            }
            .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            ForEach(list) { d in
                Button {
                    if mode == .week { withAnimation(.snappy) { anchor = Evening.date(d.date) ?? anchor; mode = .day } }
                } label: { stripRow(d, today: today) }
                .buttonStyle(.plain)
            }
            if list.isEmpty { ProgressView().tint(Theme.olive).frame(maxWidth: .infinity).padding(20) }
            if mode == .day { dayDetails(today: today) }
        }
    }

    private func legendItem(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 8); Text(t) }
    }

    private func stripRow(_ d: DayPlan, today: String) -> some View {
        let date = Evening.date(d.date) ?? Date()
        let uk = Locale(identifier: "uk_UA")
        let bdays = people.filter { $0.birthday == String(d.date.suffix(5)) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(date.formatted(.dateTime.weekday(.abbreviated).locale(uk))).font(.system(size: 15, weight: .semibold))
                + Text(" \(cal.component(.day, from: date)) \(date.formatted(.dateTime.month(.abbreviated).locale(uk)))\(d.date == today ? " · сьогодні" : "")").font(.system(size: 13)).foregroundColor(Theme.muted)
                Spacer()
                EveningBadge(day: d) { if d.isFree && d.date >= today { invite = d.date } }
                    .opacity(d.date < today ? 0.5 : 1)
            }
            DayLane(letter: String(state.me?.name.prefix(1) ?? "Я"), blocks: d.blocks.me, off: d.meOff, known: d.meKnown ?? true)
            DayLane(letter: String(state.partner?.name.prefix(1) ?? "?"), blocks: d.blocks.partner, off: d.partnerOff, known: d.partnerKnown ?? true)
            Text(Evening.note(d, partner: state.partner?.name ?? "")).font(.system(size: 12)).foregroundStyle(Theme.muted)
            ForEach(bdays) { b in Text("🎂 \(b.name)" + (b.turns.map { " · \($0)" } ?? "")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.coffee) }
        }
        .padding(12)
        .background(d.date == today ? Color(hex: 0xF3E6D8) : Theme.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.coffee, lineWidth: d.date == today ? 1.5 : 0))
        .grayscale(d.date < today ? 1 : 0).opacity(d.date < today ? 0.5 : 1)
    }

    // MARK: Сьогодні — the day card, then one row per hour (smaller than the week's day cards)

    private let hourH: CGFloat = 46, hourGap: CGFloat = 6

    private var hourList: some View {
        let iso = Evening.iso(anchor)
        let today = Evening.iso(Date())
        let nowM = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        let d = days.first { $0.date == iso }
        return VStack(alignment: .leading, spacing: 10) {
            if let d { stripRow(d, today: today) } else { ProgressView().tint(Theme.olive).frame(maxWidth: .infinity).padding(20) }
            if let d {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: hourGap) {
                        ForEach(H0..<H1, id: \.self) { h in hourRow(h, d: d, today: today, nowM: nowM) }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { p in tapHour(p.y, day: iso) }
                .gesture(LongPressGesture(minimumDuration: 0.3).sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { v in if case .second(true, let drag) = v, let drag { dragHour(drag.location.y, day: iso) } }
                    .onEnded { _ in if let s = sel { sel = nil; plan = PlanDraft(day: s.day, a: s.a * 60, b: s.b * 60) } })
            }
        }
    }

    private func hourRow(_ h: Int, d: DayPlan, today: String, nowM: Int) -> some View {
        let s = h * 60, e = s + 60
        let hit: (DayBlock) -> Bool = { Evening.minutes($0.start) < e && Evening.minutes($0.end) > s }
        let mine = d.blocks.me.filter(hit), hers = d.blocks.partner.filter { $0.kind != "ours" && hit($0) }
        let past = d.date < today || (d.date == today && e <= nowM)
        let cur = d.date == today && s <= nowM && nowM < e
        let picked = sel.map { $0.day == d.date && h >= $0.a && h < $0.b } ?? false
        return HStack(spacing: 10) {
            Text(String(format: "%02d:00", h)).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Theme.muted).frame(width: 46, alignment: .leading)
            if mine.isEmpty && hers.isEmpty {
                Text("вільно").font(.system(size: 12)).foregroundStyle(Theme.muted.opacity(0.6))
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(mine.enumerated()), id: \.offset) { _, b in hourChip(b, who: b.kind == "ours" ? "♥" : String(state.me?.name.prefix(1) ?? "Я"), side: b.kind == "ours" ? 0 : -1) }
                    ForEach(Array(hers.enumerated()), id: \.offset) { _, b in hourChip(b, who: String(state.partner?.name.prefix(1) ?? "?"), side: 1) }
                }
            }
            Spacer(minLength: 0)
            if let s0 = sel, picked, h == s0.a {
                Text("\(String(format: "%02d", s0.a)):00–\(String(format: "%02d", s0.b)):00 · \(s0.b - s0.a) год").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.olive)
            }
        }
        .padding(.horizontal, 12).frame(height: hourH)
        .background(picked ? Theme.olive.opacity(0.18) : Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(picked ? Theme.olive : Theme.coffee, lineWidth: picked ? 2 : (cur ? 1.5 : 0)))
        .grayscale(past ? 1 : 0).opacity(past ? 0.45 : 1)
    }

    private func hourChip(_ b: DayBlock, who: String, side: Int) -> some View {
        Text("\(who) · \(b.kind == "work" ? "робота" : b.label ?? "")").font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(fill(b.kind, side: side), in: Capsule())
            .foregroundStyle(b.kind == "work" ? Theme.muted : Theme.cream)
    }

    private func hourAt(_ y: CGFloat) -> Int? {
        let h = H0 + Int(max(0, y) / (hourH + hourGap))
        return h >= H0 && h < H1 ? h : nil
    }

    private func tapHour(_ y: CGFloat, day d: String) {
        guard let h = hourAt(y) else { return }
        let today = Evening.iso(Date())
        let nowM = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        if d < today || (d == today && (h + 1) * 60 <= nowM) { return }
        let a = d == today && h * 60 <= nowM && nowM < (h + 1) * 60 ? nowM : h * 60
        plan = PlanDraft(day: d, a: a, b: (h + 1) * 60)
    }

    private func dragHour(_ y: CGFloat, day d: String) {
        guard let h = hourAt(y) else { return }
        if var s = sel {
            let b = max(s.a + 1, h + 1)
            if b != s.b { s.b = b; sel = s; UISelectionFeedbackGenerator().selectionChanged() }
        } else {
            let today = Evening.iso(Date())
            let nowM = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
            if d < today || (d == today && (h + 1) * 60 <= nowM) { return }
            sel = (d, h, h + 1)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    /// Сьогодні: the day's events and a quick plan with the olive timer.
    @ViewBuilder private func dayDetails(today: String) -> some View {
        let iso = Evening.iso(anchor)
        let evs = store.events.filter { Evening.iso($0.startsAt) == iso }.sorted { $0.startsAt < $1.startsAt }
        VStack(alignment: .leading, spacing: 8) {
            Text("Події").font(.system(size: 15, weight: .bold))
            ForEach(evs) { e in EventRow(event: e) }
            if evs.isEmpty { Text("Цього дня подій нема.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
            if iso >= today {
                Button {
                    let now = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
                    let isToday = iso == today
                    let a = isToday ? now : 18 * 60
                    let b = isToday ? min(24 * 60, (now / 60 + 1) * 60) : 19 * 60
                    plan = PlanDraft(day: iso, a: a, b: max(b, a + 15))
                } label: {
                    Label("Справа з таймером", systemImage: "timer").font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 44).background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14).background(Theme.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: hour grid (day / week)

    private var gridDays: [DayPlan] { mode == .day ? days.filter { $0.date == Evening.iso(anchor) } : days }

    private var grid: some View {
        let list = gridDays
        let today = Evening.iso(Date())
        let nowM = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        return VStack(spacing: 0) {
            if list.contains(where: { $0.partnerKnown == false }) {
                Text("\(state.partner?.name ?? "") ще не внесла графік — праворуч порожньо.").font(.system(size: 12.5)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 30)
                ForEach(list) { d in
                    Button { withAnimation(.snappy) { anchor = Evening.date(d.date) ?? anchor; mode = .day } } label: {
                        VStack(spacing: 0) {
                            Text("\(Evening.date(d.date).map { cal.component(.day, from: $0) } ?? 0)").font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 6).background(d.date == today ? Theme.coffee : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(d.date == today ? Theme.cream : Theme.ink)
                            Text(weekdayShort(d) + (people.contains { $0.birthday == String(d.date.suffix(5)) } ? " 🎂" : "")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity).opacity(d.date < today ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)
            GeometryReader { g in
                let colW = (g.size.width - 30) / CGFloat(max(1, list.count))
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(H0..<H1, id: \.self) { h in
                            HStack(spacing: 0) {
                                Text(String(format: "%02d", h)).font(.system(size: 10)).foregroundStyle(Theme.muted).frame(width: 30, height: row, alignment: .topLeading)
                                ForEach(list) { d in
                                    Rectangle().fill(d.date < today || (d.date == today && (h + 1) * 60 <= nowM) ? Theme.ink.opacity(0.035) : Color.clear)
                                        .frame(height: row).overlay(alignment: .leading) { Rectangle().fill(Theme.ink.opacity(0.08)).frame(width: 1) }
                                }
                            }
                            .overlay(alignment: .top) { Rectangle().fill(Theme.ink.opacity(0.08)).frame(height: 1) }
                        }
                    }
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, d in
                        ForEach(Array(d.blocks.me.enumerated()), id: \.offset) { _, b in block(b, col: i, colW: colW, side: b.kind == "ours" ? 0 : -1, single: list.count == 1, who: state.me?.name ?? "") }
                        ForEach(Array(d.blocks.partner.filter { $0.kind != "ours" }.enumerated()), id: \.offset) { _, b in block(b, col: i, colW: colW, side: 1, single: list.count == 1, who: state.partner?.name ?? "") }
                    }
                    if let i = list.firstIndex(where: { $0.date == today }), nowM >= H0 * 60 {
                        Rectangle().fill(Color(hex: 0xC0453A)).frame(width: colW, height: 2)
                            .offset(x: 30 + CGFloat(i) * colW, y: CGFloat(nowM - H0 * 60) / 60 * row)
                    }
                    if let s = sel, let i = list.firstIndex(where: { $0.date == s.day }) {
                        Text("\(String(format: "%02d", s.a)):00–\(String(format: "%02d", s.b)):00 · \(s.b - s.a) год").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.olive)
                            .padding(4).frame(width: colW - 4, height: CGFloat(s.b - s.a) * row - 2, alignment: .topLeading)
                            .background(Theme.olive.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.olive, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
                            .offset(x: 30 + CGFloat(i) * colW + 2, y: CGFloat(s.a - H0) * row)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { p in tapAt(p, colW: colW, list: list) }
                .gesture(LongPressGesture(minimumDuration: 0.3).sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { v in
                        if case .second(true, let drag) = v, let drag { dragAt(drag.location, colW: colW, list: list) }
                    }
                    .onEnded { _ in
                        if let s = sel { sel = nil; plan = PlanDraft(day: s.day, a: s.a * 60, b: s.b * 60) }
                    })
            }
            .frame(height: CGFloat(H1 - H0) * row)
        }
    }

    private func weekdayShort(_ d: DayPlan) -> String { ["нд", "пн", "вт", "ср", "чт", "пт", "сб"][d.weekday % 7] }

    @ViewBuilder private func block(_ b: DayBlock, col: Int, colW: CGFloat, side: Int, single: Bool, who: String) -> some View {
        let a = max(H0 * 60, Evening.minutes(b.start)), e = min(H1 * 60, Evening.minutes(b.end))
        if e > a {
            let w = side == 0 ? colW - 4 : colW / 2 - 3
            let x = 30 + CGFloat(col) * colW + (side == 1 ? colW / 2 + 1 : 2)
            let label = b.kind == "work" ? (single ? "Робота · \(who)" : "") : (b.label ?? "")
            Text(label).font(.system(size: 10, weight: .semibold)).lineLimit(2).padding(4)
                .frame(width: w, height: max(14, CGFloat(e - a) / 60 * row - 2), alignment: .topLeading)
                .background(fill(b.kind, side: side), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(b.kind == "work" ? Theme.muted : Theme.cream)
                .offset(x: x, y: CGFloat(a - H0 * 60) / 60 * row)
                .allowsHitTesting(false)
        }
    }

    private func fill(_ kind: String, side: Int) -> AnyShapeStyle {
        switch kind {
        case "work": return AnyShapeStyle(side == 1 ? Color(hex: 0xDCE3CF) : Color(hex: 0xE5DCCF))
        case "ours": return AnyShapeStyle(Theme.coffee)
        case "activity", "maybe": return AnyShapeStyle(Color(hex: 0xA59E91))
        default: return AnyShapeStyle(side == 1 ? Color(hex: 0x8DA06F) : Theme.olive)
        }
    }

    private func cellAt(_ p: CGPoint, colW: CGFloat, list: [DayPlan]) -> (String, Int)? {
        guard p.x > 30, !list.isEmpty else { return nil }
        let i = Int((p.x - 30) / colW), h = H0 + Int(p.y / row)
        guard i >= 0, i < list.count, h >= H0, h < H1 else { return nil }
        return (list[i].date, h)
    }

    private func tapAt(_ p: CGPoint, colW: CGFloat, list: [DayPlan]) {
        guard let (d, h) = cellAt(p, colW: colW, list: list) else { return }
        let today = Evening.iso(Date())
        let nowM = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        if d < today || (d == today && (h + 1) * 60 <= nowM) { return }
        let a = d == today && h * 60 <= nowM && nowM < (h + 1) * 60 ? nowM : h * 60
        plan = PlanDraft(day: d, a: a, b: (h + 1) * 60)
    }

    private func dragAt(_ p: CGPoint, colW: CGFloat, list: [DayPlan]) {
        guard let (d, h) = cellAt(p, colW: colW, list: list) else { return }
        if var s = sel {
            guard d == s.day else { return }
            let b = max(s.a + 1, h + 1)
            if b != s.b { s.b = b; sel = s; UISelectionFeedbackGenerator().selectionChanged() }
        } else {
            let today = Evening.iso(Date())
            if d < today { return }
            sel = (d, h, h + 1)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: month and year

    private var monthGrid: some View {
        let today = Evening.iso(Date())
        let first = cal.date(from: cal.dateComponents([.year, .month], from: anchor)) ?? anchor
        let blanks = (cal.component(.weekday, from: first) + 5) % 7
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(["пн", "вт", "ср", "чт", "пт", "сб", "нд"], id: \.self) { Text($0).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted) }
                ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: 66) }
                ForEach(days) { d in
                    let isToday = d.date == today
                    Button { withAnimation(.snappy) { anchor = Evening.date(d.date) ?? anchor; mode = .day } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Evening.date(d.date).map { cal.component(.day, from: $0) } ?? 0)").font(.system(size: 13, weight: .bold))
                            HStack(spacing: 2) {
                                Capsule().fill(d.blocks.me.contains { $0.kind == "work" } ? Color(hex: 0xC9A27E) : .clear).frame(height: 3)
                                Capsule().fill(d.blocks.partner.contains { $0.kind == "work" } ? Color(hex: 0x8DA06F) : .clear).frame(height: 3)
                            }
                            if let e = (d.blocks.me + d.blocks.partner).first(where: { $0.kind == "ours" || $0.kind == "event" }) {
                                Text(e.label ?? "").font(.system(size: 9)).lineLimit(1).padding(.horizontal, 3).background(Theme.olive, in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(Theme.cream)
                            }
                            Spacer(minLength: 0)
                            HStack {
                                if people.contains(where: { $0.birthday == String(d.date.suffix(5)) }) { Text("🎂").font(.system(size: 11)) }
                                Spacer()
                                if d.bothFree && d.date >= today { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(isToday ? Color(hex: 0xB9CC98) : Theme.olive) }
                            }
                        }
                        .padding(5).frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
                        .background(isToday ? Theme.coffee : Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(isToday ? Theme.cream : Theme.ink)
                        .opacity(d.date < today ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: 4) { Capsule().fill(Color(hex: 0xC9A27E)).frame(width: 14, height: 4); Text("\(state.me?.name.prefix(1) ?? "") працює") }
                HStack(spacing: 4) { Capsule().fill(Color(hex: 0x8DA06F)).frame(width: 14, height: 4); Text("\(state.partner?.name.prefix(1) ?? "") працює") }
                Text("♥ обоє вільні"); Text("🎂")
            }
            .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
        }
    }

    private var yearGrid: some View {
        let y = cal.component(.year, from: anchor)
        let today = Evening.iso(Date())
        let ours = Set(store.events.filter { $0.isOurs && $0.invitation?.status != .cancelled }.map { Evening.iso($0.startsAt) })
        let bd = Set(people.map(\.birthday))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(1...12, id: \.self) { m in
                let first = cal.date(from: DateComponents(year: y, month: m, day: 1)) ?? anchor
                let blanks = (cal.component(.weekday, from: first) + 5) % 7
                let n = cal.range(of: .day, in: .month, for: first)?.count ?? 30
                Button { withAnimation(.snappy) { anchor = first; mode = .month } } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(first.formatted(.dateTime.month(.wide).locale(Locale(identifier: "uk_UA"))).capitalized).font(.system(size: 12.5, weight: .bold))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                            ForEach(0..<blanks, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                            ForEach(1...n, id: \.self) { d in
                                let iso = String(format: "%04d-%02d-%02d", y, m, d)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(iso == today ? Theme.coffee : ours.contains(iso) ? Theme.olive : bd.contains(String(iso.suffix(5))) ? Color(hex: 0xD8B28F) : Theme.ink.opacity(0.06))
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                    .padding(8).background(Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.coffee, lineWidth: y == cal.component(.year, from: Date()) && m == cal.component(.month, from: Date()) ? 2 : 0))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: data

    private func load() async {
        let from: Date, to: Date
        switch mode {
        case .day, .week:
            from = Evening.monday(of: anchor); to = cal.date(byAdding: .day, value: 6, to: from) ?? from
        case .month:
            from = cal.date(from: cal.dateComponents([.year, .month], from: anchor)) ?? anchor
            to = cal.date(byAdding: DateComponents(month: 1, day: -1), to: from) ?? from
        case .year:
            from = anchor; to = anchor
        }
        async let p = API.current().people()
        if mode != .year { days = (try? await API.current().availability(from: Evening.iso(from), to: Evening.iso(to))) ?? days }
        people = (try? await p) ?? people
    }
}

struct PlanDraft: Identifiable { let day: String; let a: Int; let b: Int; var id: String { "\(day)-\(a)-\(b)" } }

/// What I do in those hours: mine or ours, and the timer (now, or by itself at the start).
struct PlanSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let draft: PlanDraft
    @State private var title = ""
    @State private var ours = false
    @State private var timer = true
    @State private var error: String?

    private var start: Date { at(draft.a) }
    private var end: Date { at(draft.b) }
    private func at(_ m: Int) -> Date {
        let base = Evening.date(draft.day) ?? Date()
        return Dock.calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: base) ?? base
    }
    private var isNow: Bool { start <= Date() && Date() < end }

    var body: some View {
        NavigationStack {
            SoftForm {
                Section {
                    TextField("Що робиш? Спортзал, курси…", text: $title)
                    HStack(spacing: 6) {
                        ForEach(["Спортзал", "Справи", "Навчання", "Робота"], id: \.self) { x in
                            Button(x) { title = x }.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).frame(height: 32)
                                .background(title == x ? Theme.ink : Theme.tan.opacity(0.6), in: Capsule()).foregroundStyle(title == x ? Theme.paper : Theme.ink).buttonStyle(.plain)
                        }
                    }
                    Picker("", selection: $ours) { Text("Моє").tag(false); Text("Наше з \(state.partner?.name ?? "")").tag(true) }.pickerStyle(.segmented)
                } header: { Text("\(hm(draft.a))–\(hm(draft.b)) · \(length)") }
                Section {
                    Toggle(isNow ? "Таймер зараз" : "Таймер сам о \(hm(draft.a))", isOn: $timer)
                } footer: {
                    Text(isNow ? "Острівець рахує до \(hm(draft.b))." : "Острівець з'явиться заздалегідь і сам перемкнеться на відлік о \(hm(draft.a)). Якщо до початку більше 8 годин — прийде нагадування, тап по ньому запустить таймер.")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.coffee) } }
            }
            .navigationTitle("Нова справа").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save() } } }
            }
        }
        .tint(Theme.olive)
        .presentationDetents([.medium, .large])
    }

    private var length: String { let m = draft.b - draft.a; return m % 60 == 0 ? "\(m / 60) год" : "\(m) хв" }
    private func hm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    private func save() async {
        let t = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Справа" : title.trimmingCharacters(in: .whitespaces)
        var d = EventDraft(ownerId: ours ? nil : state.me?.id, title: t, startsAt: start, endsAt: end, place: nil, mapUrl: nil, note: nil, dress: nil, message: nil)
        d.watchId = nil
        do {
            let e = try await API.current().createEvent(d)
            store.upsert(e)
            if timer { LiveTasks.add(id: e.id, title: t, start: start, end: end) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Olive timers of planned activities. A Live Activity may live about 8 hours, so it starts when the activity is
/// that close; further ones get a local notification at the start (a tap opens the app and starts the timer).
enum LiveTasks {
    struct Item: Codable { let id: String; let title: String; let start: Date; let end: Date }
    private static let key = "liveTasks"

    static func add(id: String, title: String, start: Date, end: Date) {
        var all = load().filter { $0.id != id && $0.end > Date() }
        all.append(Item(id: id, title: title, start: start, end: end))
        if let d = try? JSONEncoder().encode(all) { UserDefaults.standard.set(d, forKey: key) }
        if start.timeIntervalSinceNow > 8 * 3600 {
            let c = UNMutableNotificationContent()
            c.title = "Почалось: \(title)"
            c.body = "Відкрий DaVincit — запущу таймер до \(end.formatted(date: .omitted, time: .shortened))"
            c.sound = .default
            let trig = UNCalendarNotificationTrigger(dateMatching: Dock.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start), repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "task-\(id)", content: c, trigger: trig))
        }
        sync()
    }

    static func load() -> [Item] {
        guard let d = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: d)) ?? []
    }

    static func sync() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()
        let items = load()
        let running = Set(Activity<TaskAttributes>.activities.map(\.attributes.taskId))
        for t in items where t.end > now && t.start.timeIntervalSince(now) <= 8 * 3600 && !running.contains(t.id) {
            _ = try? Activity.request(attributes: TaskAttributes(taskId: t.id, title: t.title),
                                      content: .init(state: .init(startsAt: t.start, endsAt: t.end), staleDate: t.start))
        }
        for a in Activity<TaskAttributes>.activities where a.content.state.endsAt < now || !items.contains(where: { $0.id == a.attributes.taskId }) {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        let alive = items.filter { $0.end > now }
        if let d = try? JSONEncoder().encode(alive) { UserDefaults.standard.set(d, forKey: key) }
    }
}
