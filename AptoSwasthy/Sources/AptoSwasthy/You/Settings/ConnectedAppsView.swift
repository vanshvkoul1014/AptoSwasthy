import SwiftUI

struct ConnectedAppsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var healthKit = HealthKitService.shared

    let apps: [(name: String, icon: String, color: Color, description: String)] = [
        ("Apple Health", "heart.fill", .riskHigh, "Syncs steps, heart rate, weight, sleep, and more."),
        ("Fitbit", "figure.walk", .pearlGreen, "Activity, sleep, and heart rate from your Fitbit device."),
        ("Oura Ring", "circle.fill", .pearlMint, "Recovery, HRV, and detailed sleep staging."),
        ("Garmin", "bolt.fill", .riskModerate, "Activity, GPS workouts, and VO2 max estimates."),
        ("Whoop", "waveform.path", .pearlGreen, "Strain, recovery, and sleep from your Whoop strap.")
    ]

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("Connected Apps").font(.pearlTitle2).foregroundColor(.primaryText)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundColor(.quaternaryText)
                    }
                }
                .padding(20)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(apps, id: \.name) { app in
                            ConnectedAppRow(
                                name: app.name,
                                icon: app.icon,
                                color: app.color,
                                description: app.description,
                                isAppleHealth: app.name == "Apple Health",
                                isConnected: app.name == "Apple Health" ? healthKit.isAuthorized : false
                            ) {
                                if app.name == "Apple Health" {
                                    Task { await healthKit.requestAuthorization() }
                                }
                            }
                        }

                        if healthKit.isAuthorized {
                            Button {
                                healthKit.triggerFullHistoricalBackfill()
                            } label: {
                                HStack(spacing: 12) {
                                    SyncHistoryIndicator(
                                        isActive: healthKit.isBackfilling,
                                        progress: healthKit.backfillProgress
                                    )

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(healthKit.isBackfilling
                                             ? syncTitle(progress: healthKit.backfillProgress)
                                             : "Sync Full History")
                                            .font(.pearlHeadline).foregroundColor(.primaryText)
                                        Text("Import all available Apple Health data, up to 5 years of steps, sleep, heart rate, and more.")
                                            .font(.pearlCaption).foregroundColor(.tertiaryText).lineLimit(3)
                                    }

                                    Spacer()
                                }
                                .padding(14)
                                .glassBackground(cornerRadius: 16)
                            }
                            .disabled(healthKit.isBackfilling)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func syncTitle(progress: Double) -> String {
        if progress >= 1.0 { return "Sync complete" }
        if progress <= 0 { return "Syncing history…" }
        return "Syncing history… \(Int(progress * 100))%"
    }
}

/// Circular progress ring shown while Apple Health history is importing.
/// Animates smoothly from 0→100% as each metric type completes.
private struct SyncHistoryIndicator: View {
    let isActive: Bool
    let progress: Double

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .stroke(Color.glassBorder, lineWidth: 3)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0, to: max(0.02, min(progress, 1.0)))
                    .stroke(
                        LinearGradient(
                            colors: [.pearlGreen, .pearlMint],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: progress)

                Text("\(Int(progress * 100))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primaryText)
            } else {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 18))
                    .foregroundColor(.pearlGreen)
                    .frame(width: 44, height: 44)
                    .glassBackground(cornerRadius: 12)
            }
        }
    }
}

struct ConnectedAppRow: View {
    let name: String
    let icon: String
    let color: Color
    let description: String
    let isAppleHealth: Bool
    let isConnected: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .glassBackground(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.pearlHeadline).foregroundColor(.primaryText)
                Text(description).font(.pearlCaption).foregroundColor(.tertiaryText).lineLimit(2)
            }

            Spacer()

            if isAppleHealth {
                if isConnected {
                    Text("Connected")
                        .font(.pearlCaption)
                        .foregroundColor(.riskLow)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.riskLow.opacity(0.12))
                        .clipShape(Capsule())
                } else {
                    Button(action: onConnect) {
                        Text("Connect")
                            .font(.pearlCaption)
                            .foregroundColor(.pearlGreen)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .glassBackground(cornerRadius: 12)
                    }
                }
            } else {
                Text("Coming Soon")
                    .font(.pearlCaption)
                    .foregroundColor(.tertiaryText)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.tertiaryText.opacity(0.10))
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .glassBackground(cornerRadius: 16)
        .opacity(isAppleHealth ? 1.0 : 0.7)
    }
}
