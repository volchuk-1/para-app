import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Mockup v3b: olive and cream backgrounds, brown only as an accent.
enum Theme {
    static let olive = Color(hex: 0x4B5E3A)
    static let oliveDeep = Color(hex: 0x3A4A2C)
    static let cream = Color(hex: 0xF2EEE2)
    static let paper = Color(hex: 0xF9F6EE)
    static let sage = Color(hex: 0xDCDEC8)
    static let sand = Color(hex: 0xE2C7A7)
    static let coffee = Color(hex: 0x80513A)
    static let espresso = Color(hex: 0x3B211A)
    static let biscuit = Color(hex: 0xD8B28F)
    static let ink = Color(hex: 0x2B1B14)
    static let muted = Color(hex: 0x7A6656)
    static let line = Color(hex: 0xDCDAC6)
    /// Soft brown for fields, form rows and segmented controls (instead of the system grey).
    static let tan = Color(hex: 0xEBDDCB)
    static let tanDeep = Color(hex: 0xDCC5A8)

    /// System controls follow the palette: segmented pickers, navigation titles.
    static func applyAppearance() {
        let seg = UISegmentedControl.appearance()
        seg.backgroundColor = UIColor(tan)
        seg.selectedSegmentTintColor = UIColor(paper)
        seg.setTitleTextAttributes([.foregroundColor: UIColor(muted)], for: .normal)
        seg.setTitleTextAttributes([.foregroundColor: UIColor(ink), .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .selected)
        let nav = UINavigationBar.appearance()
        nav.titleTextAttributes = [.foregroundColor: UIColor(coffee)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(coffee)]
    }

    /// Colour of "whose" an event is.
    static func whose(_ role: String?) -> Color {
        switch role {
        case "m": return coffee
        case "f": return biscuit
        default: return olive
        }
    }
}

extension Font {
    /// Headings: New York (system serif, has Cyrillic).
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Small uppercase captions of the museum tiles.
    static let caps = Font.system(size: 11, weight: .semibold)
}

/// Outlined uppercase tag, like the museum tiles.
struct TagLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .overlay(Capsule().stroke(lineWidth: 1.4))
    }
}

/// Big rounded primary button.
struct PillButtonStyle: ButtonStyle {
    var fill: Color = Theme.olive
    var text: Color = Theme.cream
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(fill, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// Rounded input field on cream.
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 18)
            .frame(minHeight: 54)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .foregroundStyle(Theme.ink)
    }
}

extension View {
    func field() -> some View { modifier(FieldStyle()) }
}

/// Text field whose placeholder stays readable on the light field background.
func inputField(_ placeholder: String, _ text: Binding<String>) -> some View {
    TextField("", text: text, prompt: Text(placeholder).foregroundColor(Theme.muted))
        .field()
        .tint(Theme.olive)
}
