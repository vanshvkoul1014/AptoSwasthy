import SwiftUI

struct RiskCard: View {
    let risk: DiseaseRisk
    @State private var expanded = false

    var tierColor: Color {
        switch risk.tier {
        case .low: return .riskLow
        case .moderate: return .riskModerate
        case .high: return .riskHigh
        }
    }

    var tierLabel: String {
        switch risk.tier {
        case .low:      return "Looking Good"
        case .moderate: return "Worth Monitoring"
        case .high:     return "Needs Attention"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row
            HStack(spacing: 12) {
                // Tier indicator
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tierColor)
                    .frame(width: 4, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(risk.condition.rawValue)
                        .font(.pearlHeadline)
                        .foregroundColor(.primaryText)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tierColor)
                            .frame(width: 7, height: 7)
                        Text(tierLabel)
                            .font(.pearlCaption)
                            .foregroundColor(tierColor)
                    }
                }

                Spacer()

                // AI-estimated probability badge - directional, not clinical.
                VStack(alignment: .trailing, spacing: 1) {
                    Text("~\(risk.estimatedPercent)%")
                        .font(.pearlTitle3.weight(.semibold))
                        .foregroundColor(tierColor)
                        .monospacedDigit()
                    Text("Pearl estimate")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(.quaternaryText)
                        .textCase(.uppercase)
                }

                Button {
                    withAnimation(.spring(response: 0.35)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.quaternaryText)
                        .frame(width: 32, height: 32)
                        .glassBackground(cornerRadius: 10)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Condition description
                    Text(risk.condition.description)
                        .font(.pearlSubheadline)
                        .foregroundColor(.tertiaryText)
                        .lineSpacing(4)

                    // Driving factors
                    if !risk.drivingFactors.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What's driving this")
                                .font(.pearlFootnote.weight(.semibold))
                                .foregroundColor(.tertiaryText)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            ForEach(risk.drivingFactors, id: \.self) { factor in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(tierColor.opacity(0.7))
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)
                                    Text(factor)
                                        .font(.pearlSubheadline)
                                        .foregroundColor(.secondaryText)
                                }
                            }
                        }
                    }

                    // Recommendations
                    if !risk.recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What you can do")
                                .font(.pearlFootnote.weight(.semibold))
                                .foregroundColor(.tertiaryText)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            ForEach(risk.recommendations, id: \.self) { rec in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.pearlGreen)
                                        .padding(.top, 3)
                                    Text(rec)
                                        .font(.pearlSubheadline)
                                        .foregroundColor(.secondaryText)
                                        .lineSpacing(3)
                                }
                            }
                        }
                    }

                    // Doctor disclaimer for high risk
                    if risk.tier == .high {
                        HStack(spacing: 8) {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 14))
                                .foregroundColor(.riskHigh)
                            Text("We recommend speaking with your doctor about this.")
                                .font(.pearlSubheadline)
                                .foregroundColor(.riskHigh.opacity(0.9))
                        }
                        .padding(12)
                        .background(Color.riskHigh.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color.glassBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    risk.tier == .low ? Color.glassBorder : tierColor.opacity(0.25),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
