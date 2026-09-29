import SwiftUI

struct SplashScreenView: View {
    @Binding var isShowing: Bool
    @Binding var authReady: Bool
    @Environment(\.colorScheme) private var colorScheme

    @State private var blobOpacity: Double = 0
    @State private var logoScale: CGFloat = 0
    @State private var logoRotation: Double = -20
    @State private var logoOpacity: Double = 0
    @State private var aptosOffset: CGFloat = 50
    @State private var aptosOpacity: Double = 0
    @State private var washtyOffset: CGFloat = 50
    @State private var washtyOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var progressFill: Double = 0
    @State private var exitScale: CGFloat = 1.0
    @State private var exitOpacity: Double = 1.0
    @State private var exitBlur: CGFloat = 0
    /// True once the minimum display animation has played. Exit only fires
    /// when BOTH this AND authReady are true, so a slow network doesn't
    /// leave the user staring at an empty screen after the splash disappears.
    @State private var minTimeElapsed = false

    private let green = Color(red: 0.13, green: 0.77, blue: 0.37)
    private let mint  = Color(red: 0.45, green: 0.92, blue: 0.70)

    private var isDark: Bool { colorScheme == .dark }

    // Palette adapts to appearance - dark mode swaps to an AMOLED-leaning
    // background with brighter accent glows to stay punchy against black.
    private var backgroundColor: Color {
        isDark ? Color(red: 0.04, green: 0.06, blue: 0.09) : .white
    }
    private var wordmarkColor: Color {
        isDark ? Color(red: 0.95, green: 0.97, blue: 1.00)
               : Color(red: 0.07, green: 0.09, blue: 0.15)
    }
    private var taglineColor: Color {
        isDark ? Color(red: 0.65, green: 0.72, blue: 0.80)
               : Color(red: 0.55, green: 0.60, blue: 0.65)
    }
    private var progressTrackColor: Color {
        isDark ? Color.white.opacity(0.10)
               : Color(red: 0.90, green: 0.92, blue: 0.95)
    }
    private var blobStrength: Double { isDark ? 0.55 : 0.40 }
    private var secondaryBlobColor: Color {
        isDark ? mint.opacity(0.14) : Color.blue.opacity(0.10)
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            // Ambient blobs - brighter accent glow in dark mode so the
            // composition doesn't feel flat against the near-black backdrop.
            ZStack {
                Circle()
                    .fill(green.opacity(isDark ? 0.28 : 0.18))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(x: -120, y: -280)
                Circle()
                    .fill(secondaryBlobColor)
                    .frame(width: 300, height: 300)
                    .blur(radius: 90)
                    .offset(x: 130, y: 320)
            }
            .opacity(blobOpacity)
            .ignoresSafeArea()

            // Content
            VStack(spacing: 0) {
                // App icon
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(green)
                        .frame(width: 96, height: 96)
                        .shadow(color: green.opacity(isDark ? 0.55 : 0.35),
                                radius: isDark ? 36 : 28, x: 0, y: 10)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(logoScale)
                .rotationEffect(.degrees(logoRotation))
                .opacity(logoOpacity)
                .padding(.bottom, 36)

                // Wordmark: "APTO SWASTHY"
                HStack(spacing: 12) {
                    Text("APTO")
                        .font(.system(size: 50, weight: .black))
                        .tracking(-1.5)
                        .foregroundColor(wordmarkColor)
                        .offset(y: aptosOffset)
                        .opacity(aptosOpacity)

                    Text("SWASTHY")
                        .font(.system(size: 50, weight: .black))
                        .tracking(-1.5)
                        .foregroundColor(green)
                        .offset(y: washtyOffset)
                        .opacity(washtyOpacity)
                }

                // Tagline + progress bar
                VStack(spacing: 0) {
                    Text("Your Health, Our Priority")
                        .font(.system(size: 16, weight: .medium))
                        .italic()
                        .foregroundColor(taglineColor)
                        .padding(.top, 14)

                    // Progress bar
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(progressTrackColor)
                            .frame(width: 176, height: 3)
                        Capsule()
                            .fill(green)
                            .frame(width: 176 * progressFill, height: 3)
                    }
                    .padding(.top, 28)
                }
                .opacity(taglineOpacity)
            }
        }
        .scaleEffect(exitScale)
        .opacity(exitOpacity)
        .blur(radius: exitBlur)
        .onAppear {
            blobOpacity = 0; logoScale = 0; logoRotation = -20; logoOpacity = 0
            aptosOffset = 50; aptosOpacity = 0; washtyOffset = 50; washtyOpacity = 0
            taglineOpacity = 0; progressFill = 0
            runSequence()
        }
        .onChange(of: authReady) { _, ready in
            if ready { tryExit() }
        }
    }

    private func runSequence() {
        // Blobs fade in
        withAnimation(.easeIn(duration: 1.8)) {
            blobOpacity = blobStrength
        }

        // Logo springs in after 0.2s
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2)) {
            logoScale = 1.0
            logoRotation = 0
            logoOpacity = 1.0
        }

        // "APTOS" slides up after 1.0s
        withAnimation(.easeOut(duration: 0.6).delay(1.0)) {
            aptosOffset = 0
            aptosOpacity = 1.0
        }

        // "wasthy" slides up after 1.4s
        withAnimation(.easeOut(duration: 0.6).delay(1.4)) {
            washtyOffset = 0
            washtyOpacity = 1.0
        }

        // Tagline fades in after 2.2s
        withAnimation(.easeIn(duration: 0.8).delay(2.2)) {
            taglineOpacity = 1.0
        }

        // Progress bar fills over 2.2s starting at 2.4s
        withAnimation(.linear(duration: 2.2).delay(2.4)) {
            progressFill = 1.0
        }

        // Mark minimum display time reached after 4.8s, then attempt exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.8) {
            minTimeElapsed = true
            tryExit()
        }
        // Hard timeout: if auth is still pending after 8s (slow network /
        // biometric prompt dismissed), exit anyway so the splash never hangs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            guard isShowing else { return }
            performExit()
        }
    }

    private func tryExit() {
        guard minTimeElapsed, authReady else { return }
        performExit()
    }

    private func performExit() {
        guard exitOpacity > 0 else { return }   // already exiting
        withAnimation(.easeInOut(duration: 0.7)) {
            exitScale = 1.08
            exitOpacity = 0
            exitBlur = 12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            isShowing = false
        }
    }
}
