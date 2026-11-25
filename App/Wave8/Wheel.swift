import SwiftUI

// MARK: - The wheel of pages: hold an empty spot, turn it like a dial, let go on a page.
// Sections are big, their pages normal, the hidden pages small. The mode (bar / both / wheel) is in Налаштування → Системні.

struct WheelItem { let page: Page?; let label: String; let icon: String; let color: UInt32; let size: Int } // size: 2 section · 1 page · 0 hidden

enum WheelItems {
    static let all: [WheelItem] = [
        WheelItem(page: .home, label: "Я", icon: "person.crop.circle.fill", color: 0x7B9E57, size: 2),
        WheelItem(page: .home, label: "Головна", icon: "house", color: 0x7B9E57, size: 1),
        WheelItem(page: .tasks, label: "Справи", icon: "checkmark.square", color: 0x2F7DD1, size: 1),
        WheelItem(page: .money, label: "Гроші", icon: "wallet.pass", color: 0xC8742A, size: 1),
        WheelItem(page: nil, label: "Налаштування", icon: "gearshape", color: 0x7A6656, size: 1),
        WheelItem(page: .stats, label: "Статистика", icon: "chart.bar", color: 0x8E6BD8, size: 0),
        WheelItem(page: .cal, label: "Календар", icon: "calendar", color: 0xE0567A, size: 2),
        WheelItem(page: .cal, label: "Сьогодні", icon: "calendar.badge.clock", color: 0xE0567A, size: 1),
        WheelItem(page: .invites, label: "Запрошення", icon: "envelope.open", color: 0xD9A21B, size: 1),
        WheelItem(page: .trips, label: "Поїздки", icon: "suitcase.rolling", color: 0x2BA39A, size: 1),
        WheelItem(page: .evening, label: "Разом", icon: "heart.fill", color: 0xC0453A, size: 2),
        WheelItem(page: .evening, label: "Вечір", icon: "moon.stars", color: 0x5B6BD6, size: 1),
        WheelItem(page: .cinema, label: "Кіно", icon: "film", color: 0xE2463F, size: 1),
        WheelItem(page: .watch, label: "Дивимось", icon: "popcorn", color: 0xE08A1E, size: 1),
        WheelItem(page: .books, label: "Книжки", icon: "books.vertical", color: 0x8C5E3C, size: 1),
        WheelItem(page: .wishes, label: "Бажання", icon: "gift", color: 0xD84FA6, size: 0),
        WheelItem(page: .finance, label: "Банки", icon: "banknote", color: 0xE0567A, size: 0),
        WheelItem(page: .archive, label: "Спогади", icon: "photo.on.rectangle", color: 0x3FA0D8, size: 0),
        WheelItem(page: .games, label: "Ігри", icon: "gamecontroller", color: 0x6BBF59, size: 0),
    ]
}

final class WheelNav: ObservableObject {
    static let shared = WheelNav()
    static let step = 10.0
    @Published var open = false
    @Published var rot = 0.0
    @Published var hot = 1
    /// where the wheel stands: nil — the middle of the screen; a value — the height of the finger
    @Published var cy: CGFloat?
    private var rot0 = 0.0
    private var y0: CGFloat = 0
    /// RootView answers: open this item (nil page = Налаштування)
    var onPick: ((WheelItem) -> Void)?
    var current: Page = .home
    private let tick = UISelectionFeedbackGenerator()

    static var mode: String { UserDefaults.standard.string(forKey: "dv-nav") ?? "bar" }

    func begin(_ y: CGFloat) {
        let h = UIScreen.main.bounds.height
        cy = (UserDefaults.standard.string(forKey: "dv-wheel-at") ?? "center") == "finger" ? max(h * 0.28, min(h * 0.72, y)) : nil
        let i = WheelItems.all.firstIndex { $0.page == current && $0.size != 2 } ?? 1
        rot = Double(i) * Self.step; rot0 = rot; y0 = y; hot = i
        Haptic.hit(.medium)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { open = true }
    }
    func drag(_ y: CGFloat) {
        guard open else { return }
        let maxRot = Double(WheelItems.all.count - 1) * Self.step
        rot = max(-20, min(maxRot + 20, rot0 - Double(y - y0) * 0.62))
        let h = max(0, min(WheelItems.all.count - 1, Int((rot / Self.step).rounded())))
        if h != hot { hot = h; tick.selectionChanged() }
    }
    func end(_ x: CGFloat) {
        guard open else { return }
        let i = hot
        withAnimation(.snappy(duration: 0.2)) { rot = Double(i) * Self.step }
        withAnimation(.easeOut(duration: 0.25).delay(0.12)) { open = false }
        if x > 50 { Haptic.hit(.medium); onPick?(WheelItems.all[i]) }
    }

    /// press and hold, then slide — the same gesture wherever it is attached
    var gesture: some Gesture {
        LongPressGesture(minimumDuration: 0.32)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { [weak self] v in
                guard let self, Self.mode != "bar" else { return }
                guard case .second(true, let d) = v else { return }
                if !self.open { self.begin(d?.location.y ?? UIScreen.main.bounds.midY) }
                if let d { self.drag(d.location.y) }
            }
            .onEnded { [weak self] v in
                guard let self else { return }
                if case .second(true, let d) = v { self.end(d?.location.x ?? 200) }
            }
    }
}

extension View {
    /// Makes the empty space of a page a place to call the wheel (cards and buttons keep their own touches).
    func wheelHold() -> some View {
        background { Color.clear.contentShape(Rectangle()).gesture(WheelNav.shared.gesture) }
    }
}

/// The wheel itself, drawn over the whole screen while the finger holds it.
struct WheelOverlay: View {
    @ObservedObject var nav = WheelNav.shared

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let R = max(300, H * 0.42), CX = W + R * 0.48, CY = nav.cy.map { $0 - g.frame(in: .global).minY } ?? H / 2, RT = R - 62
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Theme.cream.opacity(0.86), Theme.paper.opacity(0.96), Theme.paper.opacity(0.98)], startPoint: .leading, endPoint: .trailing)
                    .ignoresSafeArea()
                Circle().stroke(Theme.ink.opacity(0.12), lineWidth: 1.5)
                    .frame(width: (RT - 18) * 2, height: (RT - 18) * 2)
                    .position(x: CX, y: CY)
                ForEach(Array(WheelItems.all.enumerated()), id: \.offset) { i, it in
                    let a = Double(i) * WheelNav.step - nav.rot
                    let r = CGFloat(a * .pi / 180)
                    if abs(a) < 76 {
                        let rr = RT + (it.size == 2 ? 0 : 6)
                        let len: CGFloat = it.size == 2 ? 22 : it.size == 0 ? 7 : 12
                        Capsule().fill(Theme.ink.opacity(it.size == 2 ? 0.62 : 0.25)).frame(width: len, height: it.size == 2 ? 3 : 2)
                            .rotationEffect(.degrees(-a), anchor: .leading)
                            .position(x: CX - rr * cos(r) + len / 2, y: CY + rr * sin(r))
                    }
                    if abs(a) < 64 {
                        row(it, on: i == nav.hot)
                            .frame(width: 260, alignment: .trailing)
                            .rotationEffect(.degrees(-a), anchor: .trailing)
                            .position(x: CX - R * cos(r) - 130, y: CY + R * sin(r))
                            .opacity(0.22 + 0.78 * max(0, 1 - abs(a) / 64))
                    }
                }
                Capsule().fill(Color(hex: 0x2E2E30)).frame(width: 50, height: 18).position(x: CX - RT + 27, y: CY)
            }
            .drawingGroup()
        }
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .offset(x: 60)))
    }

    private func row(_ it: WheelItem, on: Bool) -> some View {
        let c = Color(hex: it.color)
        let w: CGFloat = on ? 82 : it.size == 2 ? 68 : it.size == 0 ? 44 : 60
        let h: CGFloat = on ? 58 : it.size == 2 ? 54 : it.size == 0 ? 36 : 48
        return HStack(spacing: 12) {
            Text(it.size == 2 ? it.label.uppercased() : it.label)
                .font(.system(size: it.size == 2 ? 13 : it.size == 0 ? 12.5 : 15, weight: it.size == 2 ? .bold : .semibold))
                .tracking(it.size == 2 ? 1.6 : 0)
                .foregroundStyle(on ? Theme.ink : Theme.ink.opacity(it.size == 2 ? 0.6 : 0.42))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(on ? Color.white : .clear, in: Capsule())
                .overlay(Capsule().stroke(Theme.ink.opacity(on ? 0.12 : 0), lineWidth: 1))
            Image(systemName: it.icon).font(.system(size: it.size == 2 ? 24 : it.size == 0 ? 16 : 20, weight: .regular)).foregroundStyle(c)
                .frame(width: w, height: h)
                .scaleEffect(on ? 1.08 : 1)
                .background(on || it.size == 2 ? c.opacity(0.14) : Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: on ? 22 : 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: on ? 22 : 18, style: .continuous).stroke(c, lineWidth: on ? 2 : 0))
                .shadow(color: c.opacity(on ? 0.3 : 0), radius: 12, y: 8)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: on)
    }
}

/// A thin strip at the right edge: the wheel is always reachable from there.
struct WheelEdge: View {
    var body: some View {
        HStack {
            Spacer()
            Capsule().fill(Theme.ink.opacity(0.16)).frame(width: 4, height: 56)
                .padding(.trailing, 3)
                .frame(width: 28, height: 140)
                .contentShape(Rectangle())
                .gesture(WheelNav.shared.gesture)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - «Котел»: the plug at home (only for the member it belongs to)

struct BoilerState: Codable, Equatable {
    let configured: Bool
    var online: Bool? = nil
    var on: Bool? = nil
    var countdown: Int? = nil
    var watts: Double? = nil
    var volts: Double? = nil
    var error: String? = nil
}
extension API {
    struct BoilerAction: Encodable { let action: String }
    func boiler() async throws -> BoilerState { try await get("/boiler") }
    func boiler(_ action: String) async throws -> BoilerState { try await send("POST", "/boiler", BoilerAction(action: action)) }
}
