import SwiftUI

/// The firm's look, carried over from the web site: its navy, a serif for
/// headings (New York stands in for DM Serif Display, which ships as web
/// fonts only), and a warm paper ground.
enum Theme {
    // MARK: Colour

    static let navy = dynamic(light: 0x1A4B78, dark: 0x6FA3D8)
    static let navyDeep = dynamic(light: 0x0F2E4C, dark: 0x0B1B2B)
    static let gold = dynamic(light: 0xB08D1E, dark: 0xD7B451)
    static let ink = dynamic(light: 0x11151C, dark: 0xF2F4F7)
    static let secondaryInk = dynamic(light: 0x5A6472, dark: 0xA3AEBC)
    static let ground = dynamic(light: 0xF7F5F1, dark: 0x0E1116)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x171B21)
    static let hairline = dynamic(light: 0xE2DED7, dark: 0x2A3039)
    static let successTint = dynamic(light: 0x1F6B4A, dark: 0x5BC08C)
    static let warningTint = dynamic(light: 0x8A5A12, dark: 0xE0A94B)
    static let dangerTint = dynamic(light: 0x9B2C2C, dark: 0xE08585)

    // MARK: Type

    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Screen titles and hero wordmarks.
    static let hero = display(34)
    /// Section headings inside a screen.
    static let sectionTitle = display(22)
    /// Card titles.
    static let cardTitle = display(18, weight: .medium)

    // MARK: Metrics

    static let cornerRadius: CGFloat = 14
    static let gutter: CGFloat = 20

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Reusable surfaces

extension View {
    /// A content card: the app's one container style.
    func brandCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }

    /// The paper ground every screen sits on.
    func brandBackground() -> some View {
        background(Theme.ground.ignoresSafeArea())
    }
}

/// The filled action button, in the firm's navy.
struct BrandButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(prominent ? Color.white : Theme.navy)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(prominent ? Theme.navy : Theme.navy.opacity(0.1))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var brand: BrandButtonStyle { BrandButtonStyle() }
    static var brandQuiet: BrandButtonStyle { BrandButtonStyle(prominent: false) }
}
