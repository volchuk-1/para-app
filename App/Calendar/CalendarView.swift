import SwiftUI

/// Week strip + events of the chosen day; filters Усе · Моє · Її · Наше.
struct CalendarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Binding var route: Route?
    @Binding var day: Date
    @State private var filter = "all"
    @State private var openEvent: Event?

    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; c.locale = Locale(identifier: "uk_UA"); return c }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.cream.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Календар").font(.serif(34, .bold))
                        Spacer()
                        Button { route = .event } label: {
                            Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                                .frame(width: 44, height: 44).background(Theme.olive.opacity(0.12), in: Circle())
                        }
                        .accessibilityLabel("Нова подія")
                    }
                    HStack {
                        Text(day.formatted(.dateTime.month(.wide).year())).font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Button { shift(-7) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                        Button { shift(7) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                    }
                    weekStrip
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip("all", "Усе", nil)
                            filterChip("me", "Моє", Theme.whose(state.me?.role))
                            filterChip("her", state.partner?.role == "f" ? "Її" : "Його", Theme.whose(state.partner?.role))
                            filterChip("us", "Наше", Theme.olive)
                        }
                    }
                    let list = events(on: day)
                    if list.isEmpty {
                        Text("На цей день нічого. Торкнись «+», щоб додати.")
                            .font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.vertical, 24)
                    }
                    ForEach(list) { e in
                        Button { openEvent = e } label: { EventRow(event: e) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 110)
            }
            .refreshable { await store.refreshAll() }
        }
        .foregroundStyle(Theme.ink)
        .sheet(item: $openEvent) { e in InviteOrEventView(event: e) }
    }

    private var weekStrip: some View {
        let start = cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let d = cal.date(byAdding: .day, value: i, to: start)!
                let on = cal.isDate(d, inSameDayAs: day)
                Button { day = d } label: {
                    VStack(spacing: 4) {
                        Text(d.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 12, weight: .medium))
                        Text(d.formatted(.dateTime.day())).font(.system(size: 17, weight: .semibold))
                        HStack(spacing: 3) {
                            ForEach(Array(dots(on: d).enumerated()), id: \.offset) { _, c in
                                Circle().fill(on ? Theme.cream : c).frame(width: 5, height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(on ? Theme.olive : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(on ? Theme.cream : Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func filterChip(_ key: String, _ text: String, _ dot: Color?) -> some View {
        Button { filter = key } label: { Chip(text: text, selected: filter == key, dot: dot) }.buttonStyle(.plain)
    }

    private func shift(_ days: Int) { day = cal.date(byAdding: .day, value: days, to: day) ?? day }

    private func matches(_ e: Event) -> Bool {
        if e.invitation?.status == .cancelled { return false }
        switch filter {
        case "me": return e.ownerId == state.me?.id
        case "her": return e.ownerId == state.partner?.id
        case "us": return e.isOurs
        default: return true
        }
    }

    private func events(on d: Date) -> [Event] {
        store.events.filter { e in
            matches(e) && (cal.isDate(e.startsAt, inSameDayAs: d) ||
                           (e.endsAt.map { e.startsAt < d && $0 >= d } ?? false))
        }
    }

    private func dots(on d: Date) -> [Color] {
        let list = store.events.filter { cal.isDate($0.startsAt, inSameDayAs: d) && $0.invitation?.status != .cancelled }
        var colors: [Color] = []
        if list.contains(where: { $0.ownerId == state.me?.id }) { colors.append(Theme.whose(state.me?.role)) }
        if list.contains(where: { $0.ownerId == state.partner?.id }) { colors.append(Theme.whose(state.partner?.role)) }
        if list.contains(where: { $0.isOurs }) { colors.append(Theme.olive) }
        return colors
    }
}

struct EventRow: View {
    @EnvironmentObject var state: AppState
    let event: Event

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.startsAt.shortTime).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                .frame(width: 46, alignment: .trailing).padding(.top, 14)
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4).padding(.vertical, 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.system(size: 15, weight: .semibold))
                    if let sub = subtitle { Text(sub).font(.system(size: 12.5)).foregroundStyle(Theme.muted) }
                    if let inv = event.invitation {
                        Label(inv.status == .accepted ? "Запрошення · прийнято" : "Запрошення · \(statusText(inv.status))",
                              systemImage: "envelope.open.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Theme.paper, in: Capsule())
                            .foregroundStyle(Theme.olive)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                Spacer()
            }
            .background(event.isOurs ? Theme.sage : Theme.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var color: Color {
        if event.isOurs { return Theme.olive }
        return event.ownerId == state.me?.id ? Theme.whose(state.me?.role) : Theme.whose(state.partner?.role)
    }

    private var subtitle: String? {
        var p: [String] = []
        if let end = event.endsAt { p.append("до \(end.shortTime)") }
        if let place = event.place { p.append(place) }
        return p.isEmpty ? nil : p.joined(separator: " · ")
    }

    private func statusText(_ s: InviteStatus) -> String {
        switch s { case .pending: "чекає"; case .accepted: "прийнято"; case .reschedule: "інший час?"; case .cancelled: "скасовано" }
    }
}
