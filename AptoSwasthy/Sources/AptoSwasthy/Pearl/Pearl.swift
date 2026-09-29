import Foundation
import Observation

@Observable
final class Pearl: @unchecked Sendable {
    static let shared = Pearl()

    var lifeExpectancy: Double = 0
    var isCalculating: Bool = false

    private let lifeExpectancyEngine = PearlLifeExpectancy()
    private let diseaseRiskEngine = PearlDiseaseRisk()
    private let habitEngine = PearlHabitIntelligence()
    private let nutritionEngine = PearlNutrition()
    private let recoveryEngine = PearlRecovery()
    private let stressEngine = PearlStress()
    // Conversation engine is owned by AIViewModel (one instance per chat session).

    private init() {}

    func recalculate(profile: UserProfile, metrics: [HealthMetric], bloodTests: [BloodTest]) {
        isCalculating = true
        lifeExpectancy = lifeExpectancyEngine.calculate(profile: profile, metrics: metrics, bloodTests: bloodTests)
        isCalculating = false
    }

    func assessRisks(profile: UserProfile, metrics: [HealthMetric], bloodTests: [BloodTest]) -> [DiseaseRisk] {
        diseaseRiskEngine.assessAll(profile: profile, metrics: metrics, bloodTests: bloodTests)
    }

    func selectHabits(for profile: UserProfile, existing: [Habit], metrics: [HealthMetric]) -> [Habit] {
        habitEngine.selectHabits(for: profile, existing: existing, currentMetrics: metrics)
    }

    func scoreNutrition(meals: [Meal], profile: UserProfile) -> Double {
        nutritionEngine.dailyScore(meals: meals, profile: profile)
    }

    func scoreRecovery(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        recoveryEngine.score(profile: profile, metrics: metrics)
    }

    func scoreStress(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        stressEngine.score(profile: profile, metrics: metrics)
    }

    func generateFirstSnapshot(profile: UserProfile) -> String {
        let greeting = timeGreeting()
        let bmiNote: String
        switch profile.bmiCategory {
        case .underweight:
            bmiNote = "Your weight is slightly below the typical range for your height. Building nutrition consistency will be a great first step."
        case .normal:
            bmiNote = "Your weight is in a healthy range. The focus now is maintaining and building from here."
        case .overweight:
            bmiNote = "Your BMI suggests there's room to improve your weight, which will have a meaningful effect on several of your risk factors."
        case .obese:
            bmiNote = "Your weight is one of the most impactful areas we can work on together. Small, consistent changes compound quickly."
        }

        let goalNote: String
        if profile.healthGoals.isEmpty {
            goalNote = "I'm here whenever you're ready to explore what matters most to you."
        } else {
            let goalList = profile.healthGoals.prefix(2).map { $0.rawValue.lowercased() }.joined(separator: " and ")
            goalNote = "You've told me you want to \(goalList). Let's work toward that one step at a time."
        }

        return "\(greeting), \(profile.name.components(separatedBy: " ").first ?? profile.name). I've reviewed everything you've shared and built your first health snapshot.\n\n\(bmiNote)\n\n\(goalNote)\n\nI've selected your first three habits based on what the data says will move the needle most. Tap any of them to learn more."
    }

    func lifeExpectancyExplanation(profile: UserProfile, metrics: [HealthMetric]) -> String {
        let topFactors = lifeExpectancyEngine.topInfluencingFactors(profile: profile, metrics: metrics)
        let positive = topFactors.filter { $0.direction == .positive }.prefix(2)
        let negative = topFactors.filter { $0.direction == .negative }.prefix(2)

        var lines = ["Here's what's shaping this estimate:"]
        if !positive.isEmpty {
            lines.append("\nWorking in your favor:")
            positive.forEach { lines.append("• \($0.description)") }
        }
        if !negative.isEmpty {
            lines.append("\nAreas that could add years:")
            negative.forEach { lines.append("• \($0.description)") }
        }
        lines.append("\nThis number updates automatically as new data comes in. It's a direction, not a destiny.")
        return lines.joined(separator: "\n")
    }

    private func timeGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hey"
        }
    }

    func greetingForHome(name: String) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let firstName = name.components(separatedBy: " ").first ?? name
        switch hour {
        case 5..<12: return "Good morning, \(firstName)"
        case 12..<17: return "Good afternoon, \(firstName)"
        case 17..<22: return "Good evening, \(firstName)"
        default: return "Welcome back, \(firstName)"
        }
    }
}
