import Foundation
import Observation
import SwiftData
import HealthKit

@MainActor
@Observable
final class HomeViewModel {
    var profile: UserProfile?
    var lifeExpectancy: Double = 0
    var lifeExpectancyBase: Double = 0
    var lifeExpectancyFactors: [LifeFactor] = []
    var weeklyLEDelta: Double? = nil
    var metrics: [HealthMetric] = []
    var todayMeals: [Meal] = []
    var habits: [Habit] = []
    var nutritionScore: Double = 0
    var recoveryScore: Double = 0
    var stressScore: Double = 0
    var isLoading = false
    var showFirstSnapshot = false
    var firstSnapshotText = ""
    var visibleCards: [MetricCardConfig] = MetricCardConfig.defaults
    var risks: [DiseaseRisk] = []

    private let persistence = PersistenceService.shared
    private let pearl = Pearl.shared
    private let nutritionEngine = PearlNutrition()
    private let habitEngine = PearlHabitIntelligence()
    @ObservationIgnored nonisolated(unsafe) private var profileUpdateObserver: NSObjectProtocol?

    init() {
        profileUpdateObserver = NotificationCenter.default.addObserver(
            forName: .profileUpdated, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit {
        if let token = profileUpdateObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func load() {
        isLoading = true
        // Kick off HealthKit sync; on completion, reload all derived data so
        // life expectancy, risks, and scores reflect the freshest values.
        Task { [weak self] in
            await HealthKitService.shared.syncIfAuthorized()
            guard let self else { return }
            self.recomputeFromLatestData()
        }
        let fetchedProfile = persistence.fetchProfile()
        let fetchedMetrics = persistence.fetchMetrics()
        let fetchedMeals = persistence.fetchTodayMeals()
        let allHabits = persistence.fetchActiveHabits()
        let bloodTests = persistence.fetchLatestBloodTests()

        loadMetricPreferences()
        guard let fetchedProfile else { isLoading = false; return }

        // Seed habits if none exist and schedule reminders for new ones.
        var activeHabits = allHabits
        if activeHabits.isEmpty {
            activeHabits = habitEngine.selectHabits(for: fetchedProfile, existing: [], currentMetrics: fetchedMetrics)
            let reminderTime = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: Date()) ?? Date()
            activeHabits.forEach { habit in
                persistence.insert(habit)
                NotificationService.shared.scheduleHabitReminder(habit: habit, at: reminderTime)
            }
        }

        let leEngine = PearlLifeExpectancy()
        let le = leEngine.calculate(profile: fetchedProfile, metrics: fetchedMetrics, bloodTests: bloodTests)
        let leBase = leEngine.baseValue(for: fetchedProfile)
        var leFactors = leEngine.allFactors(profile: fetchedProfile, metrics: fetchedMetrics, bloodTests: bloodTests)
        // calculate() and allFactors() share the same decomposition, so the sum
        // is exact unless the hard age-floor clamp kicks in (projected < age+1
        // for a very old user with many negative factors). Append a correction
        // factor in that corner case so the breakdown still reconciles.
        let unclamped = leBase + leFactors.reduce(0.0) { $0 + $1.yearsImpact }
        if le > unclamped + 0.1 {
            leFactors.append(LifeFactor(
                description: "Age floor (projected minimum is current age + 1 yr)",
                direction: .positive,
                yearsImpact: le - unclamped
            ))
        }
        let score = nutritionEngine.dailyScore(meals: fetchedMeals, profile: fetchedProfile)
        let recovery = pearl.scoreRecovery(profile: fetchedProfile, metrics: fetchedMetrics)
        let stress = pearl.scoreStress(profile: fetchedProfile, metrics: fetchedMetrics)
        let computedRisks = pearl.assessRisks(profile: fetchedProfile, metrics: fetchedMetrics, bloodTests: bloodTests)

        self.profile = fetchedProfile
        self.lifeExpectancy = le
        self.lifeExpectancyBase = leBase
        self.lifeExpectancyFactors = leFactors
        self.weeklyLEDelta = Self.computeWeeklyLEDelta(current: le)
        self.metrics = fetchedMetrics
        self.todayMeals = fetchedMeals
        self.habits = activeHabits.filter { $0.isActive && !$0.isRetired }
        self.nutritionScore = score
        self.recoveryScore = recovery
        self.stressScore = stress
        self.risks = computedRisks
        self.isLoading = false

        if !UserDefaults.standard.bool(forKey: "firstSnapshotShown") {
            self.firstSnapshotText = pearl.generateFirstSnapshot(profile: fetchedProfile)
            self.showFirstSnapshot = true
            UserDefaults.standard.set(true, forKey: "firstSnapshotShown")
        }

        evaluateAutoCompletions()
        UserDefaults.standard.set(reEngagementMessage(), forKey: "pearl_reengage_message")
    }

    func refresh() { load() }

    // MARK: - Weekly LE Delta

    /// Returns change in projected life expectancy vs. 7 days ago.
    /// Persists a weekly snapshot in UserDefaults; nil on first install.
    private static func computeWeeklyLEDelta(current: Double) -> Double? {
        guard current > 0 else { return nil }
        let keyVal  = "pearl_le_snapshot_value"
        let keyDate = "pearl_le_snapshot_date"
        let ud = UserDefaults.standard

        if ud.object(forKey: keyVal) == nil {
            ud.set(current, forKey: keyVal)
            ud.set(Date(), forKey: keyDate)
            return nil
        }

        let storedVal  = ud.double(forKey: keyVal)
        let storedDate = (ud.object(forKey: keyDate) as? Date) ?? Date()
        let daysSince  = Calendar.current.dateComponents([.day], from: storedDate, to: Date()).day ?? 0
        let delta: Double? = storedVal > 0 ? current - storedVal : nil

        if daysSince >= 7 {
            ud.set(current, forKey: keyVal)
            ud.set(Date(), forKey: keyDate)
        }
        return delta
    }

    // MARK: - Re-engagement message

    private func reEngagementMessage() -> String {
        let sorted = metrics.sorted { $0.recordedAt > $1.recordedAt }
        let val: (MetricType) -> Double? = { type in sorted.first { $0.type == type }?.value }
        if let rhr = val(.restingHeartRate), rhr > 80 {
            return "Your resting HR was \(Int(rhr)) bpm. Pearl wants to show you what might be driving it."
        }
        if let sleep = val(.sleepDuration), sleep < 6.5 {
            return "You slept \(String(format: "%.1f", sleep))h recently. Pearl has a thought on what that's costing you."
        }
        if let steps = val(.steps), steps < 5000 {
            return "Only \(Int(steps)) steps recently. Pearl has one change that would make the biggest difference."
        }
        return "Pearl has new insights about your health data. Tap to see what changed."
    }

    /// Recompute all derived outputs (life expectancy, risks, scores) from the
    /// latest persisted data. Called after the async HealthKit sync completes so
    /// the displayed values reflect newly synced metrics without a pull-to-refresh.
    private func recomputeFromLatestData() {
        let freshMetrics = persistence.fetchMetrics()
        let bloodTests = persistence.fetchLatestBloodTests()
        guard let p = profile else {
            metrics = freshMetrics
            return
        }

        let leEngine = PearlLifeExpectancy()
        let le = leEngine.calculate(profile: p, metrics: freshMetrics, bloodTests: bloodTests)
        let leBase = leEngine.baseValue(for: p)
        var leFactors = leEngine.allFactors(profile: p, metrics: freshMetrics, bloodTests: bloodTests)
        let unclamped = leBase + leFactors.reduce(0.0) { $0 + $1.yearsImpact }
        if le > unclamped + 0.1 {
            leFactors.append(LifeFactor(
                description: "Age floor (projected minimum is current age + 1 yr)",
                direction: .positive,
                yearsImpact: le - unclamped
            ))
        }

        metrics = freshMetrics
        lifeExpectancy = le
        lifeExpectancyBase = leBase
        lifeExpectancyFactors = leFactors
        recoveryScore = pearl.scoreRecovery(profile: p, metrics: freshMetrics)
        stressScore = pearl.scoreStress(profile: p, metrics: freshMetrics)
        risks = pearl.assessRisks(profile: p, metrics: freshMetrics, bloodTests: bloodTests)

        evaluateAutoCompletions()
    }

    // MARK: - Habit auto-completion

    /// For any habit with a measurable daily target (steps, water, sleep),
    /// check today's actual value and tick the habit if the target's met.
    private func evaluateAutoCompletions() {
        let candidates = habits.filter { !$0.isCompletedToday && $0.autoCompletionTarget != nil }
        guard !candidates.isEmpty else { return }

        Task { @MainActor in
            var didChange = false
            for habit in candidates {
                guard let (metric, threshold) = habit.autoCompletionTarget else { continue }
                guard let value = await todayValue(for: metric) else { continue }
                if value >= threshold {
                    habit.markComplete()
                    didChange = true
                }
            }
            if didChange { persistence.save() }
        }
    }

    private func todayValue(for metric: MetricType) async -> Double? {
        switch metric {
        case .steps:
            return await HealthKitService.shared.todayTotal(
                identifier: .stepCount, unit: .count()
            )
        case .waterIntake:
            return await HealthKitService.shared.todayTotal(
                identifier: .dietaryWater, unit: .literUnit(with: .milli)
            )
        case .sleepDuration:
            // Use the most recently persisted sleep sample - only trust it if
            // it represents last night (recorded within ~36 h to cover both
            // morning loads and late-evening loads).
            guard let latest = persistence.fetchMetrics(type: .sleepDuration, limit: 1).first
            else { return nil }
            if Date().timeIntervalSince(latest.recordedAt) < 36 * 3600 {
                return latest.value
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: Metric Preferences

    private let metricPrefsKey = "customVisibleMetrics"

    func saveMetricPreferences() {
        let types = visibleCards.map { $0.type.rawValue }
        UserDefaults.standard.set(types, forKey: metricPrefsKey)
    }

    func loadMetricPreferences() {
        guard let typeStrings = UserDefaults.standard.stringArray(forKey: metricPrefsKey) else { return }
        let loaded = typeStrings.compactMap { MetricType(rawValue: $0) }
            .map { MetricCardConfig(id: UUID(), type: $0, isVisible: true) }
        if !loaded.isEmpty { visibleCards = loaded }
    }

    func deleteMeal(_ meal: Meal) {
        persistence.delete(meal)
        todayMeals.removeAll { $0.id == meal.id }
        if let profile { nutritionScore = nutritionEngine.dailyScore(meals: todayMeals, profile: profile) }
    }

    func addWater(ml: Double) {
        let water = Meal(name: "Water", mealType: .snack)
        let entry = FoodEntry(foodName: "Water", servingSize: ml, servingUnit: "ml",
                              calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
        water.foodItems = [entry]
        persistence.insert(water)
        todayMeals.append(water)
    }

    var greeting: String {
        profile.map { Pearl.shared.greetingForHome(name: $0.name) } ?? "Welcome"
    }

    var lifeExpectancyFormatted: String {
        lifeExpectancy > 0 ? String(format: "%.1f", lifeExpectancy) : "-"
    }

    var totalCaloriesToday: Double { todayMeals.reduce(0) { $0 + $1.totalCalories } }
    var totalProteinToday: Double { todayMeals.reduce(0) { $0 + $1.totalProtein } }
    var totalCarbsToday: Double { todayMeals.reduce(0) { $0 + $1.totalCarbs } }
    var totalFatToday: Double { todayMeals.reduce(0) { $0 + $1.totalFat } }

    func latestValue(for type: MetricType) -> Double? {
        switch type {
        case .nutritionScore: return nutritionScore > 0 ? nutritionScore : nil
        case .recoveryScore:  return profile == nil ? nil : recoveryScore
        case .stressScore:    return profile == nil ? nil : stressScore
        default:
            // Try the in-memory cache first, but fall back to a scoped query
            // if the 100-row cache has been dominated by another metric type
            // (common when one type - e.g. steps - has daily data going back
            // years and pushes rarer types like weight/HRV out of the window).
            if let cached = metrics
                .filter({ $0.type == type })
                .sorted(by: { $0.recordedAt > $1.recordedAt })
                .first?.value {
                return cached
            }
            return persistence.fetchMetrics(type: type, limit: 1).first?.value
        }
    }

    /// Daily score series for the three derived scores. Recovery/stress are
    /// recomputed per day from the metrics recorded up to that day; nutrition
    /// is recomputed from the meals logged that day. Days with insufficient
    /// signal are skipped rather than zeroed so the chart isn't dominated by
    /// noise.
    func scoreSeries(for type: MetricType, days: Int) -> [ChartPoint] {
        guard let profile else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -days, to: today) else { return [] }

        var points: [ChartPoint] = []
        var day = start
        while day <= today {
            guard let nextDay = cal.date(byAdding: .day, value: 1, to: day) else { break }
            switch type {
            case .nutritionScore:
                let dayMeals = persistence.fetchMeals(from: day, to: nextDay)
                if !dayMeals.isEmpty {
                    let v = nutritionEngine.dailyScore(meals: dayMeals, profile: profile)
                    points.append(ChartPoint(date: day, value: v))
                }
            case .recoveryScore:
                let metricsUpTo = metrics.filter { $0.recordedAt <= nextDay }
                if !metricsUpTo.isEmpty {
                    let v = pearl.scoreRecovery(profile: profile, metrics: metricsUpTo)
                    points.append(ChartPoint(date: day, value: v))
                }
            case .stressScore:
                let metricsUpTo = metrics.filter { $0.recordedAt <= nextDay }
                if !metricsUpTo.isEmpty {
                    let v = pearl.scoreStress(profile: profile, metrics: metricsUpTo)
                    points.append(ChartPoint(date: day, value: v))
                }
            default: break
            }
            day = nextDay
        }
        return points
    }
}

struct MetricCardConfig: Identifiable, Hashable {
    let id: UUID
    var type: MetricType
    var isVisible: Bool

    static let defaults: [MetricCardConfig] = [
        MetricCardConfig(id: UUID(), type: .steps, isVisible: true),
        MetricCardConfig(id: UUID(), type: .activeEnergy, isVisible: true),
        MetricCardConfig(id: UUID(), type: .sleepDuration, isVisible: true),
        MetricCardConfig(id: UUID(), type: .nutritionScore, isVisible: true),
        MetricCardConfig(id: UUID(), type: .recoveryScore, isVisible: true),
        MetricCardConfig(id: UUID(), type: .stressScore, isVisible: true),
        MetricCardConfig(id: UUID(), type: .weight, isVisible: true),
        MetricCardConfig(id: UUID(), type: .restingHeartRate, isVisible: true)
    ]
}

