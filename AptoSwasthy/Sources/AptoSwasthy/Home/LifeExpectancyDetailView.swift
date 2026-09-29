import SwiftUI

struct LifeExpectancyDetailView: View {
    let projected: Double
    let base: Double
    let factors: [LifeFactor]
    let profile: UserProfile?
    @Environment(\.dismiss) private var dismiss

    private var sexLabel: String {
        profile?.biologicalSex == .female ? "female" : "male"
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Projected years header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Life Expectancy")
                            .font(.pearlCaption)
                            .foregroundColor(.tertiaryText)
                            .textCase(.uppercase)
                            .kerning(0.8)

                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", projected))
                                .font(.pearlNumber)
                                .foregroundStyle(
                                    LinearGradient(colors: [.pearlGreen, .pearlMint],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                            Text("years")
                                .font(.pearlTitle3)
                                .foregroundColor(.tertiaryText)
                        }

                        Text("Pearl's estimate based on your health data and profile")
                            .font(.pearlCaption)
                            .foregroundColor(.quaternaryText)
                    }

                    // Breakdown card
                    VStack(alignment: .leading, spacing: 0) {
                        Text("How we got here")
                            .font(.pearlSubheadline)
                            .foregroundColor(.tertiaryText)
                            .padding(.bottom, 12)

                        // Baseline row
                        LEFactorRow(
                            label: "Baseline (\(sexLabel), US population)",
                            years: base,
                            isBase: true
                        )

                        if !factors.isEmpty {
                            Divider()
                                .background(Color.glassBorder)
                                .padding(.vertical, 6)
                        }

                        ForEach(factors, id: \.description) { factor in
                            LEFactorRow(
                                label: factor.description,
                                years: factor.yearsImpact,
                                isBase: false
                            )
                        }

                        Divider()
                            .background(Color.glassBorder)
                            .padding(.vertical, 10)

                        HStack {
                            Text("Projected total")
                                .font(.pearlSubheadline)
                                .foregroundColor(.primaryText)
                            Spacer()
                            Text(String(format: "%.1f yrs", projected))
                                .font(.pearlHeadline)
                                .foregroundStyle(
                                    LinearGradient(colors: [.pearlGreen, .pearlMint],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                        }
                    }
                    .padding(20)
                    .glassBackground(cornerRadius: 20)

                    // Disclaimer
                    Text("This projection is a statistical estimate based on population-level research and your self-reported data. It is not a medical forecast. Consult a physician for personalized health guidance.")
                        .font(.pearlCaption)
                        .foregroundColor(.quaternaryText)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.large])
    }
}

private struct LEFactorRow: View {
    let label: String
    let years: Double
    let isBase: Bool

    private var valueColor: Color {
        isBase ? .tertiaryText : (years >= 0 ? .pearlGreen : .riskHigh)
    }

    private var valueText: String {
        if isBase { return String(format: "%.1f", years) }
        return years >= 0 ? String(format: "+%.1f", years) : String(format: "%.1f", years)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if isBase {
                Circle()
                    .fill(Color.quaternaryText)
                    .frame(width: 6, height: 6)
                    .padding(.horizontal, 3)
            } else {
                Image(systemName: years >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(valueColor)
            }

            Text(label)
                .font(.pearlBody)
                .foregroundColor(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Text(valueText)
                .font(.pearlSubheadline)
                .fontWeight(isBase ? .regular : .semibold)
                .foregroundColor(valueColor)
                .monospacedDigit()
        }
        .padding(.vertical, 5)
    }
}
