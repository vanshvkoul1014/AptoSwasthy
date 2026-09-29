import Foundation

final class PearlNutrition {

    func dailyScore(meals: [Meal], profile: UserProfile) -> Double {
        guard !meals.isEmpty else { return 0 }

        // Guard against malformed profiles (weight=0 or extreme age) that would
        // produce a non-positive TDEE and make the calorie ratio NaN/inf.
        let tdee = max(calculateTDEE(profile: profile), 1.0)
        let totalCalories = meals.reduce(0) { $0 + $1.totalCalories }
        let totalProtein = meals.reduce(0) { $0 + $1.totalProtein }
        let totalFat = meals.reduce(0) { $0 + $1.totalFat }
        let totalFiber = meals.reduce(0) { $0 + $1.totalFiber }

        var score = 100.0

        // Caloric balance (±30% of TDEE = max penalty)
        let calorieRatio = totalCalories / tdee
        let calorieDeviation = abs(calorieRatio - 1.0)
        score -= min(calorieDeviation * 40.0, 25.0)

        // Protein adequacy (0.8g/kg minimum, 1.6g/kg optimal)
        let minProtein = profile.weightKg * 0.8
        let optimalProtein = profile.weightKg * 1.6
        if totalProtein < minProtein {
            score -= 20.0 * (1.0 - totalProtein / minProtein)
        } else if totalProtein >= optimalProtein {
            score += 5.0
        }

        // Fiber (25g women, 38g men daily recommendation)
        let fiberTarget = profile.biologicalSex == .female ? 25.0 : 38.0
        let fiberRatio = totalFiber / fiberTarget
        if fiberRatio < 0.5 { score -= 15.0 }
        else if fiberRatio < 0.8 { score -= 5.0 }
        else if fiberRatio >= 1.0 { score += 5.0 }

        // Fat quality (penalize if fat exceeds 40% of calories)
        let fatCalories = totalFat * 9
        if fatCalories / max(totalCalories, 1) > 0.40 { score -= 10.0 }

        // Meal timing diversity bonus
        let mealTypes = Set(meals.map { $0.mealType })
        if mealTypes.count >= 3 { score += 5.0 }

        return max(0, min(100, score))
    }

    func macroSummary(meals: [Meal]) -> MacroSummary {
        MacroSummary(
            calories: meals.reduce(0) { $0 + $1.totalCalories },
            protein: meals.reduce(0) { $0 + $1.totalProtein },
            carbs: meals.reduce(0) { $0 + $1.totalCarbs },
            fat: meals.reduce(0) { $0 + $1.totalFat },
            fiber: meals.reduce(0) { $0 + $1.totalFiber }
        )
    }

    func scoreReport(score: Double, meals: [Meal], profile: UserProfile) -> String {
        let summary = macroSummary(meals: meals)
        let tdee = calculateTDEE(profile: profile)

        if meals.isEmpty {
            return "Nothing logged yet today. Pearl's score updates as you log meals."
        }

        if score >= 85 {
            return "Excellent nutrition day. Your macros are well-balanced and your caloric intake aligns with your goals. Protein is \(Int(summary.protein))g, fiber is \(Int(summary.fiber))g."
        } else if score >= 70 {
            return "Good day overall. You're at \(Int(summary.calories)) kcal out of a target \(Int(tdee)) kcal. \(fiberNote(fiber: summary.fiber, sex: profile.biologicalSex))"
        } else {
            return "There's room to improve today. \(calorieNote(calories: summary.calories, tdee: tdee)) \(fiberNote(fiber: summary.fiber, sex: profile.biologicalSex))"
        }
    }

    func calculateTDEE(profile: UserProfile) -> Double {
        // Mifflin-St Jeor BMR
        let bmr: Double
        if profile.biologicalSex == .female {
            bmr = 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * Double(profile.age) - 161
        } else {
            bmr = 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * Double(profile.age) + 5
        }
        return bmr * profile.activityLevel.multiplier
    }

    private func calorieNote(calories: Double, tdee: Double) -> String {
        let diff = calories - tdee
        if diff > 300 { return "You're \(Int(diff)) kcal over your target." }
        if diff < -400 { return "You're \(Int(abs(diff))) kcal under. Make sure you're fueling recovery." }
        return "Calories are on track."
    }

    private func fiberNote(fiber: Double, sex: BiologicalSex) -> String {
        let target = sex == .female ? 25.0 : 38.0
        if fiber < target * 0.5 { return "Fiber is low at \(Int(fiber))g. Try adding vegetables or legumes." }
        return ""
    }
}

struct MacroSummary {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
}
