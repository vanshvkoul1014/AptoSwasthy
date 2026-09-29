import SwiftUI

/// Spinning gradient ring used wherever the app is fetching or computing.
struct PearlLoadingView: View {
    var message: String = "Loading…"
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 4)
                    .frame(width: 52, height: 52)

                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        LinearGradient(
                            colors: [.pearlGreen, .pearlMint, .pearlGreen.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(rotation))
            }

            if !message.isEmpty {
                Text(message)
                    .font(.pearlCaption)
                    .foregroundColor(.tertiaryText)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}
