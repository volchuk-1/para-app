import SwiftUI

// MARK: - Wave 6.2: a vertical stack like Apple's Smart Stack (for any set of pages), «Натхнення»

/// Pages that flip like Apple's Smart Stack: a swipe up or down slides the page away (it shrinks a little) and
/// the next one in; dots on the side show only while it moves. One page — no swiping, no dots.
struct StackPager<Content: View>: View {
    let count: Int
    @Binding var index: Int
    var onTap: (Int) -> Void = { _ in }
    @ViewBuilder var page: (Int) -> Content
    @State private var drag: CGFloat = 0
    @State private var showDots = false

    var body: some View {
        GeometryReader { g in
            let h = g.size.height + 12
            let p = max(-1, min(1, drag / h))
            let cur = count > 0 ? (index % count + count) % count : 0
            ZStack {
                if count > 1, p != 0 {
                    let i = p < 0 ? (cur + 1) % count : (cur - 1 + count) % count
                    page(i)
                        .frame(width: g.size.width, height: g.size.height)
                        .scaleEffect(0.88 + 0.12 * abs(p))
                        .offset(y: (p < 0 ? h : -h) + p * h)
                }
                if count > 0 {
                    page(cur)
                        .frame(width: g.size.width, height: g.size.height)
                        .scaleEffect(1 - 0.12 * abs(p))
                        .opacity(1 - 0.4 * abs(p))
                        .offset(y: p * h)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
            .overlay(alignment: .trailing) {
                if count > 1 {
                    VStack(spacing: 4) {
                        ForEach(0..<count, id: \.self) { i in Circle().fill(Color.white.opacity(i == cur ? 1 : 0.4)).frame(width: 5, height: 5) }
                    }
                    .padding(.vertical, 5).padding(.horizontal, 3)
                    .background(Color.black.opacity(0.28), in: Capsule())
                    .padding(.trailing, 6)
                    .opacity(showDots ? 1 : 0)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if count > 0 { onTap(cur) } }
            .highPriorityGesture(swipe(h, cur), including: count > 1 ? .all : .subviews)
        }
    }

    private func swipe(_ h: CGFloat, _ cur: Int) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                guard drag != 0 || abs(v.translation.height) > abs(v.translation.width) else { return }
                if !showDots { withAnimation(.easeOut(duration: 0.2)) { showDots = true } }
                drag = v.translation.height
            }
            .onEnded { v in
                guard drag != 0 else { return }
                let far = abs(v.translation.height) > 44 || abs(v.predictedEndTranslation.height) > h * 0.6
                let go = far ? (v.translation.height < 0 ? 1 : -1) : 0
                if go == 0 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { drag = 0 }
                    hideDots()
                    return
                }
                Haptic.hit(.heavy)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { drag = CGFloat(-go) * h } completion: {
                    index = (cur + go + count) % count
                    drag = 0
                    hideDots()
                }
            }
    }

    private func hideDots() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            if drag == 0 { withAnimation(.easeOut(duration: 0.3)) { showDots = false } }
        }
    }
}

/// «Натхнення»: the card of the day from the server — a tip, a yoga pose, a YouTube lesson.
struct CardSheet: View {
    let card: DashCard
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let i = card.image {
                    Color(hex: 0x333333).frame(height: 200).overlay { RemoteImage(url: i) }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay { if card.youtube != nil { Image(systemName: "play.circle.fill").font(.system(size: 54)).foregroundStyle(.white).shadow(radius: 8) } }
                }
                Text(card.tag.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Theme.muted)
                Text(card.title).font(.serif(28, .bold))
                if !card.text.isEmpty { Text(card.text).font(.system(size: 15.5)).lineSpacing(3) }
                if let u = card.url?.asURL {
                    Button { openURL(u) } label: {
                        Label(card.youtube != nil ? "Дивитись на YouTube" : "Відкрити", systemImage: card.youtube != nil ? "play.rectangle.fill" : "arrow.up.right")
                            .font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 50)
                            .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .presentationDetents([.medium, .large])
    }
}

/// Pictures already seen stay in memory: coming back to a screen shows them at once instead of blinking.
enum ImageMemo {
    private static let cache: NSCache<NSString, UIImage> = { let c = NSCache<NSString, UIImage>(); c.countLimit = 160; return c }()
    static func get(_ url: String?) -> UIImage? { url.flatMap { cache.object(forKey: $0 as NSString) } }
    static func put(_ url: String, _ img: UIImage) { cache.setObject(img, forKey: url as NSString) }
}
