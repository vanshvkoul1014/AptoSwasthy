import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class OnboardingViewModel {
    var currentStep = 0
    var totalSteps = 17
    var isComplete = false

    // Step data
    var name = ""
    var dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    var biologicalSex: BiologicalSex = .male
    var ethnicity: Ethnicity = .preferNotToSay
    var heightCm: Double = 170
    var weightKg: Double = 70
    var unitPreference: UnitSystem = .imperial
    var activityLevel: ActivityLevel = .moderatelyActive
    var activityMinutesPerSession: Int = 30
    var sleepBedtime: Date = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
    var sleepWakeTime: Date = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    var sleepHours: Double = 7.5
    var sleepQuality: SleepQuality = .okay
    var selectedConditions: Set<String> = []
    var selectedMedications: Set<String> = []
    var selectedFamilyHistory: Set<String> = []
    var smokingStatus: SmokingStatus = .never
    var smokingPackYears: Double = 0
    var yearsSmoking: Int = 0
    var yearsSinceQuitSmoking: Int = 0
    var alcoholFrequency: AlcoholFrequency = .never
    var alcoholDrinksPerWeek: Int = 0

    // Smoking detail
    var cigarettesPerDay: Int = 0
    var vapes: Bool = false
    var secondhandSmokeExposure: SecondhandSmokeLevel = .none
    var cannabisUseFrequency: CannabisFrequency = .never

    // Alcohol detail
    var alcoholBingeFrequency: BingeFrequency = .never
    var alcoholFreeDaysPerWeek: Int = 7
    var alcoholBeverageTypes: [String] = []

    // Eating
    var dietType: DietType = .omnivore
    var mealsPerDay: Int = 3
    var fastFoodPerWeek: Int = 2
    var waterGlassesPerDay: Int = 6
    var caffeineCupsPerDay: Int = 2
    var addedSugarServingsPerDay: Int = 2

    // Eating detail
    var vegetableServingsPerDay: Int = 2
    var fruitServingsPerDay: Int = 1
    var homeCookedMealsPerWeek: Int = 10
    var lateNightEatingTimesPerWeek: Int = 2
    var processedFoodFrequency: ProcessedFoodFrequency = .sometimes
    var emotionalEatingFrequency: EmotionalEatingFrequency = .sometimes
    var eatingWindowHours: Int = 14
    var proteinSources: [String] = []

    // Movement
    var selectedExerciseTypes: Set<ExerciseType> = []

    // Wellbeing
    var stressLevel: Int = 5
    var screenTimeHoursPerDay: Double = 4

    // Free text
    var biographyNote: String = ""

    var selectedGoals: Set<HealthGoal> = []

    var canAdvance: Bool {
        switch currentStep {
        case 0: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 4: return heightCm >= 100 && heightCm <= 250 && weightKg >= 20 && weightKg <= 300
        case 16: return !selectedGoals.isEmpty
        default: return true
        }
    }

    var stepTitle: String {
        switch currentStep {
        case 0:  return "What's your name?"
        case 1:  return "When were you born?"
        case 2:  return "Biological sex"
        case 3:  return "Your background"
        case 4:  return "Height & weight"
        case 5:  return "Activity level"
        case 6:  return "How do you like to move?"
        case 7:  return "Sleep schedule"
        case 8:  return "Health conditions"
        case 9:  return "Medications"
        case 10: return "Family history"
        case 11: return "Smoking"
        case 12: return "Drinking"
        case 13: return "How do you eat?"
        case 14: return "Stress & screen time"
        case 15: return "Anything else Pearl should know?"
        case 16: return "Your goals"
        default: return ""
        }
    }

    var stepSubtitle: String {
        switch currentStep {
        case 0:  return "Pearl uses this for personalized greetings."
        case 1:  return "Used to calculate age-appropriate risk models."
        case 2:  return "Used for clinical risk calculations."
        case 3:  return "Used for population-specific risk models."
        case 4:  return "Pearl needs this to work for you."
        case 5:  return "Be honest. This affects your estimates."
        case 6:  return "Pick the activities you actually enjoy. Pearl will suggest habits around them."
        case 7:  return "Pearl uses this as a baseline before any app is connected."
        case 8:  return "Select all that apply, or mark None."
        case 9:  return "Optional but strongly encouraged. Stays on device."
        case 10: return "Conditions in first-degree relatives."
        case 11: return "Smoking history drives a lot of Pearl's risk math. Detail helps."
        case 12: return "Rough averages are fine. Pearl just needs a ballpark."
        case 13: return "No judgment. Pearl meets you where you are."
        case 14: return "Context Pearl uses when your metrics move unexpectedly."
        case 15: return "Optional. A sentence or two goes a long way."
        case 16: return "Pearl will prioritize around this."
        default: return ""
        }
    }

    func advance() {
        guard canAdvance else { return }
        if currentStep < totalSteps - 1 {
            withAnimation(.easeInOut(duration: 0.35)) {
                currentStep += 1
            }
        } else {
            saveProfile()
        }
    }

    func back() {
        guard currentStep > 0 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep -= 1
        }
    }

    func saveProfile() {
        let persistence = PersistenceService.shared
        let profile = UserProfile(
            name: name,
            dateOfBirth: dateOfBirth,
            biologicalSex: biologicalSex,
            ethnicity: ethnicity,
            heightCm: heightCm,
            weightKg: weightKg,
            activityLevel: activityLevel,
            activityMinutesPerSession: activityMinutesPerSession,
            sleepBedtime: sleepBedtime,
            sleepWakeTime: sleepWakeTime,
            sleepHoursPerNight: sleepHours,
            healthConditions: Array(selectedConditions),
            medications: Array(selectedMedications),
            familyHistory: Array(selectedFamilyHistory),
            smokingStatus: smokingStatus,
            alcoholFrequency: alcoholFrequency,
            healthGoals: Array(selectedGoals),
            unitPreference: unitPreference,
            onboardingComplete: true,
            dietType: dietType,
            mealsPerDay: mealsPerDay,
            fastFoodPerWeek: fastFoodPerWeek,
            waterGlassesPerDay: waterGlassesPerDay,
            caffeineCupsPerDay: caffeineCupsPerDay,
            addedSugarServingsPerDay: addedSugarServingsPerDay,
            smokingPackYears: smokingPackYears,
            yearsSmoking: yearsSmoking,
            yearsSinceQuitSmoking: yearsSinceQuitSmoking,
            alcoholDrinksPerWeek: alcoholDrinksPerWeek,
            stressLevel: stressLevel,
            sleepQuality: sleepQuality,
            screenTimeHoursPerDay: screenTimeHoursPerDay,
            exerciseTypes: selectedExerciseTypes.map(\.rawValue),
            biographyNote: biographyNote.trimmingCharacters(in: .whitespacesAndNewlines),
            cigarettesPerDay: cigarettesPerDay,
            vapes: vapes,
            secondhandSmokeExposure: secondhandSmokeExposure,
            cannabisUseFrequency: cannabisUseFrequency,
            alcoholBingeFrequency: alcoholBingeFrequency,
            alcoholFreeDaysPerWeek: alcoholFreeDaysPerWeek,
            alcoholBeverageTypes: alcoholBeverageTypes,
            vegetableServingsPerDay: vegetableServingsPerDay,
            fruitServingsPerDay: fruitServingsPerDay,
            homeCookedMealsPerWeek: homeCookedMealsPerWeek,
            lateNightEatingTimesPerWeek: lateNightEatingTimesPerWeek,
            processedFoodFrequency: processedFoodFrequency,
            emotionalEatingFrequency: emotionalEatingFrequency,
            eatingWindowHours: eatingWindowHours,
            proteinSources: proteinSources
        )
        persistence.insert(profile)
        NotificationCenter.default.post(name: .profileUpdated, object: nil)
        isComplete = true

        // Snapshot into a Sendable DTO on the main actor before crossing
        // the task boundary - SwiftData @Model instances aren't Sendable.
        let dto = ProfileDTO(from: profile)
        Task.detached {
            do {
                try await ProfileAPIService.shared.putProfile(dto)
            } catch ProfileAPIError.cloudDisabled {
                // Stack not yet deployed - local-only is the intended behaviour.
            } catch {
                #if DEBUG
                print("[OnboardingViewModel] cloud profile push failed: \(error)")
                #endif
            }
        }
    }
}
