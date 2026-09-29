import Foundation

final class PearlHabitIntelligence {

    private let habitLibrary: [HabitTemplate] = [
        HabitTemplate(name: "10-minute morning walk", description: "Start your day with a short walk. Morning light helps regulate your circadian rhythm and boosts mood.", cadence: .daily, category: .activity, formationDays: 21, targetGoals: [.buildFitness, .liveLonger, .reduceStress], conditionsHelped: ["hypertension", "diabetes", "obesity"]),
        HabitTemplate(name: "Drink 8 glasses of water", description: "Hydration affects energy, focus, and nearly every metabolic process in your body.", cadence: .daily, category: .hydration, formationDays: 21, targetGoals: [.liveLonger, .stayInformed], conditionsHelped: ["kidney", "fatigue"]),
        HabitTemplate(name: "7–9 hours of sleep", description: "Sleep is the most powerful recovery tool you have. Consistent sleep timing matters as much as duration.", cadence: .daily, category: .sleep, formationDays: 66, targetGoals: [.sleepBetter, .liveLonger, .reduceStress], conditionsHelped: ["hypertension", "diabetes", "obesity", "depression"]),
        HabitTemplate(name: "30-minute workout", description: "Moderate exercise three times a week reduces risk for cardiovascular disease, diabetes, and depression.", cadence: .daily, category: .activity, formationDays: 66, targetGoals: [.buildFitness, .liveLonger, .loseWeight], conditionsHelped: ["hypertension", "diabetes", "cardiovascular", "depression"]),
        HabitTemplate(name: "5 servings of vegetables", description: "Each additional serving of vegetables per day is associated with reduced all-cause mortality.", cadence: .daily, category: .nutrition, formationDays: 66, targetGoals: [.liveLonger, .manageCondition, .loseWeight], conditionsHelped: ["cardiovascular", "diabetes", "cancer"]),
        HabitTemplate(name: "No screens 1 hour before bed", description: "Blue light exposure delays melatonin production. This one change measurably improves sleep quality.", cadence: .daily, category: .sleep, formationDays: 21, targetGoals: [.sleepBetter, .reduceStress], conditionsHelped: ["sleep"]),
        HabitTemplate(name: "10-minute mindfulness practice", description: "Even brief daily meditation reduces cortisol levels and improves stress resilience over time.", cadence: .daily, category: .mindfulness, formationDays: 66, targetGoals: [.reduceStress, .sleepBetter, .manageCondition], conditionsHelped: ["hypertension", "depression", "anxiety"]),
        HabitTemplate(name: "Log all meals", description: "Food awareness is the first step to nutritional change. You can't optimize what you don't measure.", cadence: .daily, category: .nutrition, formationDays: 30, targetGoals: [.loseWeight, .manageCondition, .stayInformed], conditionsHelped: ["diabetes", "obesity"]),
        HabitTemplate(name: "Strength training twice a week", description: "Resistance training preserves muscle mass, improves insulin sensitivity, and supports bone density.", cadence: .weekly, category: .activity, formationDays: 66, targetGoals: [.buildFitness, .liveLonger, .loseWeight], conditionsHelped: ["osteoporosis", "diabetes", "obesity"]),
        HabitTemplate(name: "Take prescribed medications", description: "Consistent medication adherence is one of the highest-impact things you can do for your health.", cadence: .daily, category: .medical, formationDays: 14, targetGoals: [.manageCondition, .liveLonger], conditionsHelped: ["all"]),
        HabitTemplate(name: "Limit alcohol to 1 drink", description: "Keeping alcohol at moderate levels reduces risk for liver disease, certain cancers, and cardiovascular events.", cadence: .daily, category: .nutrition, formationDays: 30, targetGoals: [.liveLonger, .manageCondition], conditionsHelped: ["liver", "cardiovascular", "cancer"]),
        HabitTemplate(name: "Walk 8,000 steps", description: "Step count is one of the most researched markers of longevity. 8,000 daily steps shows significant mortality benefit.", cadence: .daily, category: .activity, formationDays: 30, targetGoals: [.liveLonger, .buildFitness, .loseWeight], conditionsHelped: ["cardiovascular", "diabetes", "obesity"])
    ]

    func selectHabits(for profile: UserProfile, existing: [Habit], currentMetrics: [HealthMetric] = []) -> [Habit] {
        let activeCount = existing.filter { $0.isActive }.count
        guard activeCount < 3 else { return existing }

        let slotsNeeded = 3 - activeCount
        let existingNames = existing.map { $0.name }

        let candidates = habitLibrary
            .filter { !existingNames.contains($0.name) }
            .sorted { scoreHabit($0, for: profile) > scoreHabit($1, for: profile) }
            .prefix(slotsNeeded)

        var newHabits = existing
        for template in candidates {
            let rationale = generateRationale(template: template, profile: profile)
            newHabits.append(Habit(
                name: template.name,
                habitDescription: template.description,
                cadence: template.cadence,
                formationDays: template.formationDays,
                category: template.category,
                pearlRationale: rationale
            ))
        }
        return newHabits
    }

    func alternativeHabit(for declined: Habit, profile: UserProfile, existing: [Habit]) -> Habit? {
        let existingNames = existing.map { $0.name }
        let declined_category = declined.category

        let alternative = habitLibrary
            .filter { !existingNames.contains($0.name) && $0.category == declined_category && $0.name != declined.name }
            .sorted { scoreHabit($0, for: profile) > scoreHabit($1, for: profile) }
            .first

        guard let template = alternative else { return nil }
        return Habit(
            name: template.name,
            habitDescription: template.description,
            cadence: template.cadence,
            formationDays: template.formationDays,
            category: template.category,
            pearlRationale: generateRationale(template: template, profile: profile)
        )
    }

    private func scoreHabit(_ template: HabitTemplate, for profile: UserProfile) -> Double {
        var score = 0.0

        // Goal alignment
        let goalOverlap = template.targetGoals.filter { profile.healthGoals.contains($0) }.count
        score += Double(goalOverlap) * 2.0

        // Condition relevance
        for condition in profile.healthConditions {
            let lc = condition.lowercased()
            if template.conditionsHelped.contains(where: { lc.contains($0) || $0 == "all" }) {
                score += 3.0
            }
        }

        // BMI relevance
        if profile.bmi >= 25 && (template.category == .activity || template.category == .nutrition) {
            score += 1.5
        }

        // Sleep relevance
        if profile.sleepHoursPerNight < 7 && template.category == .sleep {
            score += 2.0
        }

        return score
    }

    private func generateRationale(template: HabitTemplate, profile: UserProfile) -> String {
        let firstName = profile.name.components(separatedBy: " ").first ?? "you"

        if template.category == .activity && profile.bmi >= 25 {
            return "Based on your BMI and activity data, \(template.name.lowercased()) will have the highest impact on your weight and cardiovascular health right now."
        }
        if template.category == .sleep && profile.sleepHoursPerNight < 7 {
            return "Your sleep data shows you're averaging under 7 hours. Improving sleep quality affects nearly every other metric Pearl tracks."
        }
        if template.category == .nutrition {
            return "Nutrition quality is one of the most modifiable longevity factors. This habit targets your daily nutrition score directly."
        }
        return "Based on your goals and health profile, Pearl selected this as one of the highest-impact changes \(firstName) can make right now."
    }

    func retirementPrompt(habit: Habit) -> String {
        "You've been showing up for '\(habit.name)' consistently. That kind of follow-through is how habits become part of who you are, not just what you do. Ready to mark this as a lasting habit?"
    }

    func missedHabitResponse(habit: Habit) -> String {
        let responses = [
            "Missing a day doesn't break a habit. It's what you do next that matters. You've got this.",
            "One off day is just that. The research is clear: self-compassion after a miss leads to better long-term adherence than guilt does.",
            "That's okay. Pearl doesn't track misses. Just pick it back up when you're ready.",
            "Rest days are part of the arc. You're still building '\(habit.name)'. This is just one data point."
        ]
        return responses[Int.random(in: 0..<responses.count)]
    }
}

private struct HabitTemplate {
    let name: String
    let description: String
    let cadence: HabitCadence
    let category: HabitCategory
    let formationDays: Int
    let targetGoals: [HealthGoal]
    let conditionsHelped: [String]
}
