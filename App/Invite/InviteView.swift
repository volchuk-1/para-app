import SwiftUI

/// Invitation screen (tennis-app style): photo on half the screen, sheet with details, «Я прийду».
struct InviteView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State var event: Event
    @State private var edit = false
    @State private var askTime = false
    @State private var note = ""
    @State private var confirmCancel = false

    init(event: Event) { _event = State(initialValue: event) }

    private var mine: Bool { event.createdBy == state.me?.id }
    private var inv: Invitation { event.invitation ?? Invitation(status: .pending) }
    private var fromName: String { mine ? (state.me?.name ?? "") : (state.partner?.name ?? "") }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.paper.ignoresSafeArea()
                AuthImage(url: inv.coverUrl)
                    .frame(width: geo.size.width, height: geo.size.height * 0.52)
                    .clipped()
                    .ignoresSafeArea(edges: .top)

                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Закрити")
                    Spacer()
                    (Text("Запрошення від ") + Text(fromName).italic().bold())
                        .font(.system(size: 13)).padding(.horizontal, 13).frame(height: 32)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.top, 8)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: geo.size.height * 0.46)
                    sheet
                }
            }
        }
        .sheet(isPresented: $edit) { InviteEditor(existing: event) }
        .alert("Інший час?", isPresented: $askTime) {
            TextField("Повідомлення", text: $note)
            Button("Надіслати") { Task { await answer(accept: false) } }
            Button("Скасувати", role: .cancel) {}
        }
        .confirmationDialog("Скасувати запрошення?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Скасувати запрошення", role: .destructive) { Task { await cancel() } }
        }
        .onReceive(store.$events) { list in if let e = list.first(where: { $0.id == event.id }) { event = e } }
    }

    private var sheet: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                let (first, rest) = firstWord(event.title)
                (Text(first).font(.serif(29, .bold)) + Text(rest).font(.serif(29, .bold)))
                    .padding(.trailing, 70)
                Text("#побачення #наше").font(.system(size: 12)).foregroundStyle(Theme.muted.opacity(0.7))
                VStack(alignment: .leading, spacing: 6) {
                    Label(event.startsAt.dayTime, systemImage: "clock")
                    if let p = event.place { Label(p, systemImage: "mappin.and.ellipse") }
                    if let d = inv.dress { Label(d, systemImage: "tshirt") }
                }
                .font(.system(size: 14.5)).foregroundStyle(Theme.muted)
                if let m = inv.message { Text(m).font(.system(size: 15)).foregroundStyle(Theme.ink) }
                if inv.status == .reschedule, let n = inv.replyNote {
                    Label(n, systemImage: "bubble.left.fill").font(.system(size: 14, weight: .medium))
                        .padding(12).background(Theme.sand, in: RoundedRectangle(cornerRadius: 16))
                }
                HStack(spacing: 8) {
                    if event.place != nil || event.mapUrl != nil {
                        chip("Маршрут", "map") { openMap() }
                    }
                    if mine && inv.status != .cancelled {
                        chip("Змінити", "pencil") { edit = true }
                        chip("Скасувати", "xmark") { confirmCancel = true }
                    }
                }
                .padding(.top, 4)
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 22).padding(.top, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.paper, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
            .overlay(alignment: .bottom) { bottomBar }

            Image(systemName: "heart.fill").font(.system(size: 28))
                .frame(width: 68, height: 68)
                .background(Theme.espresso, in: Circle())
                .foregroundStyle(Theme.biscuit)
                .shadow(color: Theme.espresso.opacity(0.35), radius: 12, y: 8)
                .offset(x: -22, y: -34)
        }
        .foregroundStyle(Theme.ink)
    }

    private var bottomBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.startsAt.formatted(.dateTime.weekday(.wide))).font(.serif(20)).italic()
                Text(statusLine).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if !mine && (inv.status == .pending || inv.status == .reschedule) {
                Button("Інший час?") { askTime = true }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.coffee).padding(.trailing, 6)
                Button { Task { await answer(accept: true) } } label: {
                    Label("Я прийду", systemImage: "checkmark").font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 22).frame(height: 54)
                        .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                }
            } else if inv.status == .accepted, let buy = inv.buyUrl?.asURL {
                Button { openURL(buy) } label: {
                    Label("Купити квитки", systemImage: "ticket.fill").font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 22).frame(height: 54)
                        .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                }
            } else {
                Text(badge).font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 18).frame(height: 54)
                    .background(inv.status == .cancelled ? Theme.sand : Theme.olive, in: Capsule())
                    .foregroundStyle(inv.status == .cancelled ? Theme.ink : Theme.cream)
            }
        }
        .padding(.leading, 24).padding(.trailing, 8)
        .frame(height: 72)
        .background(Theme.cream, in: Capsule())
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    private var statusLine: String {
        let s = event.startsAt.timeIntervalSinceNow
        if s <= 0 { return event.startsAt.shortTime }
        let days = Int(s / 86400)
        return days >= 1 ? "\(event.startsAt.shortTime) · через \(days) дн." : "\(event.startsAt.shortTime) · сьогодні"
    }

    private var badge: String {
        switch inv.status {
        case .accepted: return mine ? "\(state.partner?.name ?? "") прийде ✓" : "Ти прийдеш ✓"
        case .pending: return "Чекаємо відповіді"
        case .reschedule: return "Просять інший час"
        case .cancelled: return "Скасовано"
        }
    }

    private func chip(_ t: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { Text(t); Image(systemName: icon).foregroundStyle(Theme.coffee) }
                .font(.system(size: 13.5, weight: .medium))
                .padding(.horizontal, 12).frame(height: 38)
                .background(Theme.cream, in: Capsule())
        }
        .foregroundStyle(Theme.ink)
    }

    private func firstWord(_ s: String) -> (String, String) {
        guard let i = s.firstIndex(of: " ") else { return (s, "") }
        return (String(s[..<i]), String(s[i...]))
    }

    private func openMap() {
        if let m = event.mapUrl?.asURL { openURL(m); return }
        let q = (event.place ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let u = URL(string: "http://maps.apple.com/?q=\(q)") { openURL(u) }
    }

    private func answer(accept: Bool) async {
        await store.run {
            let e = try await API.current().answer(event.id, accept: accept, note: accept ? nil : note)
            store.upsert(e); event = e
        }
    }

    private func cancel() async {
        await store.run {
            let e = try await API.current().cancelInvitation(event.id)
            store.upsert(e); event = e
        }
    }
}

private extension Invitation {
    init(status: InviteStatus) { self.init(dress: nil, message: nil, coverUrl: nil, status: status, replyNote: nil, answeredAt: nil) }
}
