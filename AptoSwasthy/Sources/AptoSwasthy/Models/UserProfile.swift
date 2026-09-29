import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var name: String
    var dateOfBirth: Date
    var biologicalSex: BiologicalSex
    var ethnicity: Ethnicity
    var heightCm: Double
    var weightKg: Double
    var activityLevel: ActivityLevel
    var activityMinutesPerSession: Int
    var sleepBedtime: Date
    var sleepWakeTime: Date
    var sleepHoursPerNight: Double
    var healthConditions: [String]
    var medications: [String]
    var familyHistory: [String]
    var smokingStatus: SmokingStatus
    var alcoholFrequency: AlcoholFrequency
    var healthGoals: [HealthGoal]
    var unitPreference: UnitSystem
    var faceIDEnabled: Bool
    var onboardingComplete: Bool
    /// Names of external health apps the user has authorized (e.g. "Apple Health").
    /// Kept in the profile so we can re-prompt on a new device / reinstall.
    var connectedApps: [String]
    var createdAt: Date

    // MARK: - Rich lifestyle (added for Pearl's deeper personalization)
    // All new fields carry property-level defaults so SwiftData performs a
    // lightweight migration for existing users who onboarded pre-v2.

    /// Primary eating pattern - drives Pearl's nutrition framing and risk weighting.
    var dietType: DietType = DietType.omnivore
    /// Typical meals logged per day (incl. substantial snacks). 1–8.
    var mealsPerDay: Int = 3
    /// Fast-food / takeout meals in an average week.
    var fastFoodPerWeek: Int = 2
    /// Self-reported glasses of water per day (~8 oz each).
    var waterGlassesPerDay: Int = 6
    /// Caffeinated drinks per day (coffee, tea, energy drink).
    var caffeineCupsPerDay: Int = 2
    /// Added sugar servings per day - a strong driver of metabolic risk.
    var addedSugarServingsPerDay: Int = 2

    /// Pack-years, the clinical gold-standard smoking exposure measure.
    /// packs-per-day × years smoked. 0 for never-smokers.
    var smokingPackYears: Double = 0
    /// Years spent as an active smoker (0 if never).
    var yearsSmoking: Int = 0
    /// Only meaningful if smokingStatus == .former.
    var yearsSinceQuitSmoking: Int = 0

    /// Typical alcoholic drinks per week (standard drinks).
    var alcoholDrinksPerWeek: Int = 0

    /// Self-reported stress 1–10.
    var stressLevel: Int = 5
    /// Self-reported sleep quality.
    var sleepQuality: SleepQuality = SleepQuality.okay
    /// Average recreational screen time per day, hours.
    var screenTimeHoursPerDay: Double = 4

    /// Primary forms of movement the user engages in.
    var exerciseTypes: [String] = []

    /// Free-text field where the user can tell Pearl anything else -
    /// recent life events, symptoms, specific concerns. Fed to Pearl's
    /// system prompt so the model treats it as persistent context.
    var biographyNote: String = ""

    // MARK: - Granular lifestyle (v3 - extremely in-depth profile)
    // Every field below carries a default so SwiftData migrates silently.

    /// Cigarettes per day for current smokers (0 otherwise).
    var cigarettesPerDay: Int = 0
    /// Whether the user vapes / uses e-cigarettes.
    var vapes: Bool = false
    /// Daily exposure to secondhand smoke (workplace, household).
    var secondhandSmokeExposure: SecondhandSmokeLevel = SecondhandSmokeLevel.none
    /// Whether the user uses cannabis in any form.
    var cannabisUseFrequency: CannabisFrequency = CannabisFrequency.never

    /// How often drinking crosses into a binge (4+ drinks women / 5+ men in ~2h).
    var alcoholBingeFrequency: BingeFrequency = BingeFrequency.never
    /// Number of fully alcohol-free days per typical week (0–7).
    var alcoholFreeDaysPerWeek: Int = 7
    /// Beverage mix - helps Pearl contextualize calorie / sugar load.
    var alcoholBeverageTypes: [String] = []

    /// Servings of vegetables per day (~½ cup cooked / 1 cup raw each).
    var vegetableServingsPerDay: Int = 2
    /// Servings of fruit per day.
    var fruitServingsPerDay: Int = 1
    /// Home-cooked meals per week (0–21).
    var homeCookedMealsPerWeek: Int = 10
    /// How often they eat within 3 hours of bedtime, per week.
    var lateNightEatingTimesPerWeek: Int = 2
    /// Frequency of ultra-processed foods (packaged snacks, frozen meals, fast food).
    var processedFoodFrequency: ProcessedFoodFrequency = ProcessedFoodFrequency.sometimes
    /// Frequency of emotional / stress-driven eating.
    var emotionalEatingFrequency: EmotionalEatingFrequency = EmotionalEatingFrequency.sometimes
    /// Typical eating window (hours between first and last food/drink of the day).
    var eatingWindowHours: Int = 14
    /// Primary protein sources - shapes Pearl's diet-quality reading.
    var proteinSources: [String] = []

    init(
        id: UUID = UUID(),
        name: String = "",
        dateOfBirth: Date = Date(),
        biologicalSex: BiologicalSex = .notSpecified,
        ethnicity: Ethnicity = .preferNotToSay,
        heightCm: Double = 170,
        weightKg: Double = 70,
        activityLevel: ActivityLevel = .moderatelyActive,
        activityMinutesPerSession: Int = 30,
        sleepBedtime: Date = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date(),
        sleepWakeTime: Date = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date(),
        sleepHoursPerNight: Double = 7.5,
        healthConditions: [String] = [],
        medications: [String] = [],
        familyHistory: [String] = [],
        smokingStatus: SmokingStatus = .never,
        alcoholFrequency: AlcoholFrequency = .never,
        healthGoals: [HealthGoal] = [],
        unitPreference: UnitSystem = .imperial,
        faceIDEnabled: Bool = true,
        onboardingComplete: Bool = false,
        connectedApps: [String] = [],
        createdAt: Date = Date(),
        dietType: DietType = .omnivore,
        mealsPerDay: Int = 3,
        fastFoodPerWeek: Int = 2,
        waterGlassesPerDay: Int = 6,
        caffeineCupsPerDay: Int = 2,
        addedSugarServingsPerDay: Int = 2,
        smokingPackYears: Double = 0,
        yearsSmoking: Int = 0,
        yearsSinceQuitSmoking: Int = 0,
        alcoholDrinksPerWeek: Int = 0,
        stressLevel: Int = 5,
        sleepQuality: SleepQuality = .okay,
        screenTimeHoursPerDay: Double = 4,
        exerciseTypes: [String] = [],
        biographyNote: String = "",
        cigarettesPerDay: Int = 0,
        vapes: Bool = false,
        secondhandSmokeExposure: SecondhandSmokeLevel = .none,
        cannabisUseFrequency: CannabisFrequency = .never,
        alcoholBingeFrequency: BingeFrequency = .never,
        alcoholFreeDaysPerWeek: Int = 7,
        alcoholBeverageTypes: [String] = [],
        vegetableServingsPerDay: Int = 2,
        fruitServingsPerDay: Int = 1,
        homeCookedMealsPerWeek: Int = 10,
        lateNightEatingTimesPerWeek: Int = 2,
        processedFoodFrequency: ProcessedFoodFrequency = .sometimes,
        emotionalEatingFrequency: EmotionalEatingFrequency = .sometimes,
        eatingWindowHours: Int = 14,
        proteinSources: [String] = []
    ) {
        self.id = id
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.biologicalSex = biologicalSex
        self.ethnicity = ethnicity
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityLevel = activityLevel
        self.activityMinutesPerSession = activityMinutesPerSession
        self.sleepBedtime = sleepBedtime
        self.sleepWakeTime = sleepWakeTime
        self.sleepHoursPerNight = sleepHoursPerNight
        self.healthConditions = healthConditions
        self.medications = medications
        self.familyHistory = familyHistory
        self.smokingStatus = smokingStatus
        self.alcoholFrequency = alcoholFrequency
        self.healthGoals = healthGoals
        self.unitPreference = unitPreference
        self.faceIDEnabled = faceIDEnabled
        self.onboardingComplete = onboardingComplete
        self.connectedApps = connectedApps
        self.createdAt = createdAt
        self.dietType = dietType
        self.mealsPerDay = mealsPerDay
        self.fastFoodPerWeek = fastFoodPerWeek
        self.waterGlassesPerDay = waterGlassesPerDay
        self.caffeineCupsPerDay = caffeineCupsPerDay
        self.addedSugarServingsPerDay = addedSugarServingsPerDay
        self.smokingPackYears = smokingPackYears
        self.yearsSmoking = yearsSmoking
        self.yearsSinceQuitSmoking = yearsSinceQuitSmoking
        self.alcoholDrinksPerWeek = alcoholDrinksPerWeek
        self.stressLevel = stressLevel
        self.sleepQuality = sleepQuality
        self.screenTimeHoursPerDay = screenTimeHoursPerDay
        self.exerciseTypes = exerciseTypes
        self.biographyNote = biographyNote
        self.cigarettesPerDay = cigarettesPerDay
        self.vapes = vapes
        self.secondhandSmokeExposure = secondhandSmokeExposure
        self.cannabisUseFrequency = cannabisUseFrequency
        self.alcoholBingeFrequency = alcoholBingeFrequency
        self.alcoholFreeDaysPerWeek = alcoholFreeDaysPerWeek
        self.alcoholBeverageTypes = alcoholBeverageTypes
        self.vegetableServingsPerDay = vegetableServingsPerDay
        self.fruitServingsPerDay = fruitServingsPerDay
        self.homeCookedMealsPerWeek = homeCookedMealsPerWeek
        self.lateNightEatingTimesPerWeek = lateNightEatingTimesPerWeek
        self.processedFoodFrequency = processedFoodFrequency
        self.emotionalEatingFrequency = emotionalEatingFrequency
        self.eatingWindowHours = eatingWindowHours
        self.proteinSources = proteinSources
    }

    var age: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
    }

    var bmi: Double {
        let heightM = heightCm / 100.0
        return weightKg / (heightM * heightM)
    }

    var bmiCategory: BMICategory {
        switch bmi {
        case ..<18.5: return .underweight
        case 18.5..<25: return .normal
        case 25..<30: return .overweight
        default: return .obese
        }
    }

    var heightInches: Double { heightCm / 2.54 }
    var weightLbs: Double { weightKg * 2.20462 }

    var heightFeetString: String {
        let totalInches = Int(heightInches)
        return "\(totalInches / 12)'\(totalInches % 12)\""
    }
}

enum BiologicalSex: String, Codable, CaseIterable {
    case male = "Male"
    case female = "Female"
    case notSpecified = "Prefer not to say"
}

enum Ethnicity: String, Codable, CaseIterable {
    case white = "White"
    case blackOrAfricanAmerican = "Black or African American"
    case hispanicOrLatino = "Hispanic or Latino"
    case asian = "Asian"
    case nativeAmericanOrAlaskaNative = "Native American or Alaska Native"
    case nativeHawaiianOrPacificIslander = "Native Hawaiian or Pacific Islander"
    case middleEasternOrNorthAfrican = "Middle Eastern or North African"
    case southAsian = "South Asian"
    case multiracial = "Multiracial"
    case other = "Other"
    case preferNotToSay = "Prefer not to say"
}

enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary = "Sedentary (little or no exercise)"
    case lightlyActive = "Lightly active (1–3 days/week)"
    case moderatelyActive = "Moderately active (3–5 days/week)"
    case veryActive = "Very active (6–7 days/week)"
    case extremelyActive = "Extremely active (twice daily)"

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .lightlyActive: return 1.375
        case .moderatelyActive: return 1.55
        case .veryActive: return 1.725
        case .extremelyActive: return 1.9
        }
    }
}

enum SmokingStatus: String, Codable, CaseIterable {
    case never = "Never smoked"
    case former = "Former smoker"
    case current = "Current smoker"
}

enum AlcoholFrequency: String, Codable, CaseIterable {
    case never = "Never"
    case rarely = "Rarely (a few times a year)"
    case monthly = "Monthly"
    case weekly = "Weekly (1–2 drinks)"
    case several = "Several times a week"
    case daily = "Daily"
}

enum HealthGoal: String, Codable, CaseIterable {
    case liveLonger = "Live longer"
    case loseWeight = "Lose weight"
    case buildFitness = "Build fitness"
    case manageCondition = "Manage a condition"
    case reduceStress = "Reduce stress"
    case sleepBetter = "Sleep better"
    case stayInformed = "Just stay informed"
}

enum UnitSystem: String, Codable, CaseIterable {
    case imperial = "Imperial (lbs, ft)"
    case si = "SI (kg, cm)"
}

enum DietType: String, Codable, CaseIterable {
    case omnivore = "Omnivore (eats most things)"
    case mostlyPlantBased = "Mostly plant-based"
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case pescatarian = "Pescatarian"
    case mediterranean = "Mediterranean"
    case keto = "Keto / low-carb"
    case paleo = "Paleo"
    case lowFat = "Low-fat"
    case intermittentFasting = "Intermittent fasting"
    case highProtein = "High-protein"
    case other = "Other / mixed"
}

enum SleepQuality: String, Codable, CaseIterable {
    // Raw values keep the em-dash separator they were originally stored
    // with. SwiftData decodes existing user records by exact rawValue match,
    // so changing the separator would fail to decode previously-saved profiles.
    // UI callers should use `displayName` for the user-facing label instead.
    case poor = "Poor — wake up tired most days"
    case okay = "Okay — some good nights, some bad"
    case good = "Good — usually feel rested"
    case excellent = "Excellent — wake up refreshed"

    var displayName: String {
        switch self {
        case .poor:      return "Poor. Wake up tired most days."
        case .okay:      return "Okay. Some good nights, some bad."
        case .good:      return "Good. Usually feel rested."
        case .excellent: return "Excellent. Wake up refreshed."
        }
    }
}

enum ExerciseType: String, Codable, CaseIterable {
    case walking = "Walking"
    case running = "Running / jogging"
    case cycling = "Cycling"
    case swimming = "Swimming"
    case strength = "Strength / weights"
    case yoga = "Yoga"
    case pilates = "Pilates"
    case hiit = "HIIT / cross-training"
    case teamSports = "Team sports"
    case racketSports = "Tennis / pickleball / racket"
    case hiking = "Hiking"
    case dance = "Dance"
    case martialArts = "Martial arts"
    case climbing = "Climbing"
    case none = "None right now"
}

enum SecondhandSmokeLevel: String, Codable, CaseIterable {
    case none = "None"
    case occasional = "Occasional (social)"
    case regular = "Regular (household / friends)"
    // Raw value keeps the em-dash for SwiftData compatibility with existing
    // records; `displayName` is what the UI should show.
    case heavy = "Heavy (daily — work or home)"

    var displayName: String {
        switch self {
        case .heavy: return "Heavy (daily, work or home)"
        default:     return rawValue
        }
    }
}

enum CannabisFrequency: String, Codable, CaseIterable {
    case never = "Never"
    case rarely = "Rarely"
    case monthly = "Monthly"
    case weekly = "Weekly"
    case daily = "Daily"
}

enum BingeFrequency: String, Codable, CaseIterable {
    case never = "Never"
    case rarely = "Rarely (a few times a year)"
    case monthly = "About once a month"
    case weekly = "Weekly"
    case several = "Several times a week"
}

enum ProcessedFoodFrequency: String, Codable, CaseIterable {
    case rarely = "Rarely (mostly whole foods)"
    case sometimes = "Sometimes (few times a week)"
    case often = "Often (daily)"
    case mostly = "Mostly (multiple times a day)"
}

enum EmotionalEatingFrequency: String, Codable, CaseIterable {
    case never = "Never"
    case rarely = "Rarely"
    case sometimes = "Sometimes"
    case often = "Often"
    case daily = "Daily"
}

enum BMICategory: String {
    case underweight = "Underweight"
    case normal = "Normal"
    case overweight = "Overweight"
    case obese = "Obese"

    var bodyFatRange: String {
        switch self {
        case .underweight: return "lean"
        case .normal: return "normal"
        case .overweight: return "overweight"
        case .obese: return "obese"
        }
    }
}
