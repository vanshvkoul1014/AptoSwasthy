import SwiftUI

// MARK: - Hex initializer

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var int: UInt64 = 0
        scanner.scanHexInt64(&int)
        self.init(
            .sRGB,
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8)  & 0xFF) / 255,
            blue:  Double(int         & 0xFF) / 255
        )
    }

    /// Creates a Color that uses different values in light vs dark mode.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

// MARK: - Palette

extension Color {

    // Brand - adaptive between modes
    static let pearlGreen = adaptive(
        light: Color(hex: "7BA68A"),                           // sage green
        dark:  Color(red: 0.388, green: 0.831, blue: 0.878)   // current cyan
    )
    static let pearlMint = adaptive(
        light: Color(hex: "5A9EA6"),                           // teal
        dark:  Color(red: 0.537, green: 0.890, blue: 0.957)   // current mint
    )

    // Light-mode accents (also usable as complementary highlights in dark)
    static let pearlCoral    = Color(hex: "D4836A")
    static let pearlAmber    = Color(hex: "C9A84C")
    static let pearlLavender = Color(hex: "9B8EC4")

    // Backgrounds
    static let pearlBackground = adaptive(
        light: Color(hex: "F7F5F0"),
        dark:  Color(red: 0.06, green: 0.06, blue: 0.08)
    )
    static let pearlSurface = adaptive(
        light: Color(hex: "EDEAE4"),
        dark:  Color(red: 0.12, green: 0.12, blue: 0.15)
    )
    static let pearlBorder = adaptive(
        light: Color.black.opacity(0.09),
        dark:  Color.white.opacity(0.12)
    )

    // Glass surfaces
    static let glassBackground = adaptive(
        light: Color.black.opacity(0.05),
        dark:  Color.white.opacity(0.07)
    )
    static let glassBorder = adaptive(
        light: Color.black.opacity(0.10),
        dark:  Color.white.opacity(0.14)
    )
    static let glassShadow = adaptive(
        light: Color.black.opacity(0.07),
        dark:  Color.black.opacity(0.30)
    )

    // Semantic text hierarchy (adaptive)
    static let primaryText = adaptive(
        light: Color(hex: "1C1C1E"),
        dark:  .white
    )
    static let secondaryText = adaptive(
        light: Color(hex: "1C1C1E").opacity(0.60),
        dark:  Color.white.opacity(0.70)
    )
    static let tertiaryText = adaptive(
        light: Color(hex: "1C1C1E").opacity(0.42),
        dark:  Color.white.opacity(0.50)
    )
    static let quaternaryText = adaptive(
        light: Color(hex: "1C1C1E").opacity(0.26),
        dark:  Color.white.opacity(0.30)
    )

    // Risk
    static let riskLow      = Color(red: 0.29, green: 0.82, blue: 0.56)
    static let riskModerate = Color(red: 0.99, green: 0.76, blue: 0.28)
    static let riskHigh     = Color(red: 0.96, green: 0.35, blue: 0.35)
}

// MARK: - ShapeStyle convenience (allows .pearlGreen in foregroundStyle)

extension ShapeStyle where Self == Color {
    static var pearlGreen:    Color { .pearlGreen }
    static var pearlMint:     Color { .pearlMint }
    static var pearlCoral:    Color { .pearlCoral }
    static var pearlAmber:    Color { .pearlAmber }
    static var pearlLavender: Color { .pearlLavender }
    static var primaryText:   Color { .primaryText }
    static var secondaryText: Color { .secondaryText }
}
