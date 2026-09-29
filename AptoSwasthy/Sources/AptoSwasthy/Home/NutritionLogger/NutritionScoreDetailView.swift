import SwiftUI

struct NutritionScoreDetailView: View {
    let score: Double
    let meals: [Meal]
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss

    private var totalCalories: Double { meals.reduce(0) { $0 + $1.totalCalories } }
    private var totalProtein: Double { meals.reduce(0) { $0 + $1.totalProtein } }
    private var totalFat: Double { meals.reduce(0) { $0 + $1.totalFat } }
    private var totalFiber: Double { meals.reduce(0) { $0 + $1.totalFiber } }

    private var tdee: Double {
        let engine = PearlNutrition()
        return engine.tdeePublic(profile: profile)
    }

    private var minProtein: Double { profile.weightKg * 0.8 }
    private var optimalProtein: Double { profile.weightKg * 1.6 }
    private var fiberTarget: Double { profile.biologicalSex == .female ? 25.0 : 38.0 }

    private var scoreColor: Color {
        switch score {
        case 80...: return .riskLow
        case 60...: return .riskModerate
        default: return .riskHigh
        }
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nutrition Score")
                                .font(.pearlCaption)
                                .foregroundColor(.tertiaryText)
                                .textCase(.uppercase)
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text("\(Int(score))")
                                    .font(.pearlNumber)
                                    .foregroundColor(scoreColor)
                                Text("/ 100")
                                    .font(.pearlTitle3)
                                    .foregroundColor(.tertiaryText)
                            }
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.quaternaryText)
                        }
                    }

                    // How it's calculated
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How it's calculated")
                            .font(.pearlHeadline)
                            .foregroundColor(.primaryText)

                        FactorLine(
                            label: "Caloric balance",
                            detail: "\(Int(totalCalories)) of ~\(Int(tdee)) kcal target",
                            healthy: abs(totalCalories / max(tdee, 1) - 1.0) <= 0.15
                        )
                        FactorLine(
                            label: "Protein",
                            detail: "\(Int(totalProtein))g vs \(Int(minProtein))–\(Int(optimalProtein))g target",
                            healthy: totalProtein >= minProtein
                        )
                        FactorLine(
                            label: "Fiber",
                            detail: "\(Int(totalFiber))g vs \(Int(fiberTarget))g target",
                            healthy: totalFiber >= fiberTarget * 0.8
                        )
                        FactorLine(
                            label: "Fat quality",
                            detail: totalCalories > 0
                                ? "\(Int((totalFat * 9 / totalCalories) * 100))% of calories from fat"
                                : "No data yet",
                            healthy: totalCalories > 0 && (totalFat * 9 / totalCalories) <= 0.40
                        )
                        FactorLine(
                            label: "Meal variety",
                            detail: "\(Set(meals.map { $0.mealType }).count) distinct meal types today",
                            healthy: Set(meals.map { $0.mealType }).count >= 3
                        )
                    }
                    .padding(18)
                    .glassBackground(cornerRadius: 20)

                    // Interpretation
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.pearlGreen)
                            Text("Pearl's take")
                                .font(.pearlHeadline)
                                .foregroundColor(.primaryText)
                        }
                        Text(interpretation)
                            .font(.pearlBody)
                            .foregroundColor(.secondaryText)
                            .lineSpacing(5)
                    }
                    .padding(18)
                    .glassBackground(cornerRadius: 20)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .presentationDetents([.large])
    }

    private var interpretation: String {
        if meals.isEmpty {
            return "Log what you eat today and I'll score it against your personal TDEE and macro targets."
        }
        switch score {
        case 80...:
            return "Excellent balance today. Caloric intake, protein, and fiber are all within healthy bounds. Keep this pattern going. It's one of the strongest inputs into your long-term risk profile."
        case 60..<80:
            return "Solid day with room to refine. Check the factors above. Bumping the one marked as a gap usually pushes the score above 80."
        default:
            return "There's meaningful room to improve today. The factors marked below target are the fastest wins. Small, specific changes (like adding a protein source or a fiber-rich food) compound quickly."
        }
    }
}

private struct FactorLine: View {
    let label: String
    let detail: String
    let healthy: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: healthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(healthy ? .pearlGreen : .riskModerate)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.pearlSubheadline.weight(.semibold))
                    .foregroundColor(.primaryText)
                Text(detail)
                    .font(.pearlCaption)
                    .foregroundColor(.tertiaryText)
            }
            Spacer()
        }
    }
}

extension PearlNutrition {
    func tdeePublic(profile: UserProfile) -> Double {
        calculateTDEE(profile: profile)
    }
}
