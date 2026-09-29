import SwiftUI

// MARK: - Liquid Glass Card

struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.glassBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.glassBorder, lineWidth: 1)
                    }
            }
            .shadow(color: Color.glassShadow, radius: 12, x: 0, y: 4)
    }
}

// MARK: - Liquid Glass Background

struct LiquidGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.glassBorder, lineWidth: 0.5)
                    }
            }
    }
}

// MARK: - Animated Gradient Background (light + dark adaptive)

struct AnimatedGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var animate = false

    var body: some View {
        ZStack {
            Color.pearlBackground.ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    // Primary blob - sage green (light) / cyan (dark)
                    Circle()
                        .fill(Color.pearlGreen.opacity(colorScheme == .dark ? 0.08 : 0.14))
                        .frame(width: geo.size.width * 0.8)
                        .offset(
                            x: animate ? -geo.size.width  * 0.15 : geo.size.width  * 0.10,
                            y: animate ? -geo.size.height * 0.20 : -geo.size.height * 0.10
                        )
                        .blur(radius: colorScheme == .dark ? 80 : 60)

                    // Secondary blob - teal (light) / mint (dark)
                    Circle()
                        .fill(Color.pearlMint.opacity(colorScheme == .dark ? 0.05 : 0.10))
                        .frame(width: geo.size.width * 0.6)
                        .offset(
                            x: animate ?  geo.size.width  * 0.20 : -geo.size.width  * 0.10,
                            y: animate ?  geo.size.height * 0.30 :  geo.size.height * 0.15
                        )
                        .blur(radius: colorScheme == .dark ? 60 : 48)

                    // Light-mode only: warm coral accent
                    if colorScheme == .light {
                        Circle()
                            .fill(Color.pearlCoral.opacity(0.06))
                            .frame(width: geo.size.width * 0.5)
                            .offset(
                                x: animate ? geo.size.width * 0.30 : geo.size.width * 0.15,
                                y: animate ? geo.size.height * 0.40 : geo.size.height * 0.55
                            )
                            .blur(radius: 56)
                    }
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: animate)
            .onAppear { animate = true }
        }
    }
}

// MARK: - Liquid Glass Pill (iOS 26 aesthetic)

/// Floating "liquid glass" look for pills/chips layered over a full-bleed scene
/// (e.g. the body avatar on the You tab). Multi-layer composite: refractive
/// base material + top-edge specular sheen + bright-to-dark rim stroke + soft
/// bloom shadow. Reads as a droplet of glass catching the light rather than a
/// flat frosted card.
struct LiquidGlassPill: ViewModifier {
    var cornerRadius: CGFloat = 14
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Base material - refractive blur
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Specular sheen - bright top, vanishes by center
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.22 : 0.38),
                                    Color.white.opacity(0.04),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .blendMode(.plusLighter)

                    // Faint mint refraction bloom from the brand palette
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.pearlMint.opacity(isDark ? 0.14 : 0.10),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.plusLighter)
                }
            }
            .overlay {
                // Bright-to-dark rim - gives the shape apparent curvature
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.55 : 0.75),
                                Color.white.opacity(0.12),
                                Color.black.opacity(isDark ? 0.18 : 0.06),
                                Color.white.opacity(0.22)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.18),
                    radius: 14, x: 0, y: 8)
            .shadow(color: Color.pearlMint.opacity(isDark ? 0.12 : 0.08),
                    radius: 22, x: 0, y: 0)
    }
}

// MARK: - Keyboard dismissal

/// Adds a "Done" button above the keyboard so users can always dismiss it,
/// and taps outside text inputs resign first responder as a fallback.
struct KeyboardDismissable: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .foregroundColor(.pearlGreen)
                    .fontWeight(.semibold)
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, padding: padding))
    }

    func glassBackground(cornerRadius: CGFloat = 16) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius))
    }

    func liquidGlass(cornerRadius: CGFloat = 14) -> some View {
        modifier(LiquidGlassPill(cornerRadius: cornerRadius))
    }

    func keyboardDismissable() -> some View {
        modifier(KeyboardDismissable())
    }
}
