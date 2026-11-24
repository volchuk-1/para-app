import SwiftUI

/// Museum-style tile: outlined tag, serif title with the underlined ending, small caps meta, line + «Відкрити →».
struct MuseumTile<Extra: View>: View {
    var fill: Color
    var ink: Color = Theme.ink
    var tag: String
    var title: String
    var underlined: String = ""
    var meta: String? = nil
    var footer: String? = "Відкрити"
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TagLabel(text: tag)
            (Text(title + (underlined.isEmpty ? "" : " ")) + Text(underlined).underline())
                .font(.serif(25, .bold))
                .lineLimit(3)
                .padding(.top, 12)
                .padding(.bottom, 8)
            if let meta {
                Text(meta.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.6)
                    .lineSpacing(3)
                    .opacity(0.8)
            }
            extra()
            if let footer {
                Rectangle().fill(ink.opacity(0.18)).frame(height: 1).padding(.top, 14)
                HStack {
                    Text(footer.uppercased()).font(.system(size: 11.5, weight: .semibold)).tracking(0.9)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(.top, 12)
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

extension MuseumTile where Extra == EmptyView {
    init(fill: Color, ink: Color = Theme.ink, tag: String, title: String, underlined: String = "", meta: String? = nil, footer: String? = "Відкрити") {
        self.init(fill: fill, ink: ink, tag: tag, title: title, underlined: underlined, meta: meta, footer: footer) { EmptyView() }
    }
}

/// Splits a title so its last word can be underlined like in the museum tiles.
func splitTitle(_ s: String) -> (String, String) {
    let parts = s.split(separator: " ")
    guard parts.count > 1 else { return ("", s + ".") }
    return (parts.dropLast().joined(separator: " "), parts.last.map(String.init)! + ".")
}

/// Public image (posters, shop photos) with a soft placeholder. Kept in memory once loaded.
struct RemoteImage: View {
    let url: String?
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    init(url: String?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
        _image = State(initialValue: ImageMemo.get(url))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Theme.sage
                Image(systemName: "photo").foregroundStyle(Theme.muted.opacity(0.5))
            }
        }
        .task(id: url) {
            // a new address keeps the old picture on screen until the new one is here
            if let c = ImageMemo.get(url) { image = c; return }
            guard let u = url?.asURL, let (data, _) = try? await URLSession.shared.data(from: u), let img = UIImage(data: data) else { return }
            if let url { ImageMemo.put(url, img) }
            image = img
        }
    }
}

/// Protected image (invitation cover, our photos): loaded with the device key. Kept in memory once loaded.
struct AuthImage: View {
    let url: String?
    @State private var image: UIImage?

    init(url: String?) {
        self.url = url
        _image = State(initialValue: ImageMemo.get(url))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Theme.coffee, Theme.espresso], startPoint: .top, endPoint: .bottom)
                Image(systemName: "heart.fill").font(.system(size: 54)).foregroundStyle(Theme.biscuit.opacity(0.5))
            }
        }
        .task(id: url) {
            if let c = ImageMemo.get(url) { image = c; return }
            guard let url, let data = try? await API.current().fileData(url), let img = UIImage(data: data) else { return }
            ImageMemo.put(url, img)
            image = img
        }
    }
}

/// Rounded chip used in filters.
struct Chip: View {
    let text: String
    var selected = false
    var dot: Color? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            Text(text)
        }
        .font(.system(size: 14, weight: selected ? .semibold : .medium))
        .padding(.horizontal, 14).frame(height: 36)
        .background(selected ? Theme.olive : Theme.olive.opacity(0.10), in: Capsule())
        .foregroundStyle(selected ? Theme.cream : Theme.ink)
    }
}

/// Error / offline banner.
struct Banner: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.cream)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.espresso.opacity(0.9), in: Capsule())
    }
}

/// Initial-letter avatar: coffee for him, olive for her.
/// A Form in the palette: cream page, soft brown rows instead of grey.
struct SoftForm<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        Form { Group { content() }.listRowBackground(Theme.tan) }
            .scrollContentBackground(.hidden)
            .background(Theme.cream.ignoresSafeArea())
    }
}

struct Avatar: View {
    let member: Member?
    var size: CGFloat = 26
    var body: some View {
        Text(String(member?.name.prefix(1) ?? "?"))
            .font(.serif(size * 0.45, .bold))
            .frame(width: size, height: size)
            .background(member?.role == "m" ? Theme.coffee : Theme.oliveDeep, in: Circle())
            .foregroundStyle(Theme.cream)
    }
}

extension Date {
    /// Always the 24-hour clock, whatever the phone's own setting.
    private static let hm: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "uk_UA"); f.dateFormat = "HH:mm"; return f }()
    private static let dayHm: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "uk_UA"); f.dateFormat = "EEEE, d MMMM, HH:mm"; return f }()
    var dayTime: String { Date.dayHm.string(from: self) }
    var shortTime: String { Date.hm.string(from: self) }
}

/// Pictures already seen stay in memory: coming back to a screen shows them at once instead of blinking.
enum ImageMemo {
    private static let cache: NSCache<NSString, UIImage> = { let c = NSCache<NSString, UIImage>(); c.countLimit = 160; return c }()
    static func get(_ url: String?) -> UIImage? { url.flatMap { cache.object(forKey: $0 as NSString) } }
    static func put(_ url: String, _ img: UIImage) { cache.setObject(img, forKey: url as NSString) }
}
