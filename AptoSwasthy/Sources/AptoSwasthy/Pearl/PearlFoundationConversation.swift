import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// =====================================================================
//  PearlFoundationConversation - LLM-backed Pearl, fully on-device.
//
//  Wraps Apple's FoundationModels framework (iOS 26+). The model writes
//  the prose; the existing Pearl engines provide ground-truth answers
//  via typed tools so numbers can't be hallucinated.
//
//  Availability is gated at runtime via SystemLanguageModel.default.
//  Falls back to the rule-based PearlConversation elsewhere.
// =====================================================================

#if canImport(FoundationModels)

@available(iOS 26.0, macOS 15.0, *)
@MainActor
final class PearlFoundationConversation {

    private let store: PearlToolStore
    private var session: LanguageModelSession

    init(profile: UserProfile?,
         metrics: [HealthMetric],
         meals: [Meal],
         bloodTests: [BloodTest],
         habits: [Habit]) {
        let store = PearlToolStore()
        store.update(profile: profile,
                     metrics: metrics,
                     meals: meals,
                     bloodTests: bloodTests,
                     habits: habits)
        self.store = store

        let tools: [any Tool] = [
            LatestMetricTool(store: store),
            MetricTrendTool(store: store),
            AssessRisksTool(store: store),
            LifeExpectancyTool(store: store),
            TodayNutritionTool(store: store),
            HabitsTool(store: store),
            MetricHistoryTool(store: store),
            HistoricalMealsTool(store: store),
            BloodTestSummaryTool(store: store),
            BiomarkerTrendTool(store: store),
            BaselineComparisonTool(store: store),
            PeriodComparisonTool(store: store),
            AllPanelsTool(store: store),
            LogMetricTool(store: store),
        ]
        let instructions = Instructions(Self.systemPrompt(profile: profile))
        self.session = LanguageModelSession(tools: tools, instructions: instructions)
    }

    /// Returns true only on a device that actually has Apple Intelligence
    /// turned on and the model downloaded. Call before instantiating.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Update the tool store so tool calls see fresh metrics/meals/etc.,
    /// while keeping the session intact so multi-turn memory carries across
    /// messages. Note: static profile facts baked into the system prompt at
    /// init only refresh when `resetSession` is called.
    func refreshData(profile: UserProfile?,
                     metrics: [HealthMetric],
                     meals: [Meal],
                     bloodTests: [BloodTest],
                     habits: [Habit]) {
        store.update(profile: profile,
                     metrics: metrics,
                     meals: meals,
                     bloodTests: bloodTests,
                     habits: habits)
    }

    /// Reset the session entirely (clears multi-turn memory).
    func resetSession(profile: UserProfile?) {
        let tools: [any Tool] = [
            LatestMetricTool(store: store),
            MetricTrendTool(store: store),
            AssessRisksTool(store: store),
            LifeExpectancyTool(store: store),
            TodayNutritionTool(store: store),
            HabitsTool(store: store),
            MetricHistoryTool(store: store),
            HistoricalMealsTool(store: store),
            BloodTestSummaryTool(store: store),
            BiomarkerTrendTool(store: store),
            BaselineComparisonTool(store: store),
            PeriodComparisonTool(store: store),
            AllPanelsTool(store: store),
            LogMetricTool(store: store),
        ]
        session = LanguageModelSession(tools: tools,
                                       instructions: Instructions(Self.systemPrompt(profile: profile)))
    }

    func stream(userMessage: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [session] in
                do {
                    let responseStream = session.streamResponse(to: userMessage)
                    for try await snapshot in responseStream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // =============================================================
    // MARK: - System prompt
    // =============================================================

    private static func systemPrompt(profile: UserProfile?) -> String {
        guard let p = profile else {
            return """
            You are Pearl, an on-device clinical health companion inside AptoSwasthy. \
            The user hasn't finished setting up their profile yet. \
            Warmly welcome them and ask them to complete onboarding so you can start giving personalized insight.
            """
        }

        let firstName = p.name.components(separatedBy: " ").first ?? p.name
        let name = p.name.isEmpty ? "the user" : firstName
        let conditions = p.healthConditions.isEmpty ? "none reported" : p.healthConditions.joined(separator: ", ")
        let meds = p.medications.isEmpty ? "none" : p.medications.joined(separator: ", ")
        let family = p.familyHistory.isEmpty ? "not reported" : p.familyHistory.joined(separator: ", ")
        let goals = p.healthGoals.isEmpty ? "none set yet" : p.healthGoals.map(\.rawValue).joined(separator: ", ")
        let exercise = p.exerciseTypes.isEmpty ? "not specified" : p.exerciseTypes.joined(separator: ", ")

        // Smoking / alcohol detail - richer than a raw enum.
        let smokingDetail: String = {
            switch p.smokingStatus {
            case .never:   return "never smoked"
            case .former:  return "former smoker. \(p.yearsSmoking) yrs smoked, quit \(p.yearsSinceQuitSmoking) yrs ago, \(String(format: "%.1f", p.smokingPackYears)) pack-years"
            case .current: return "current smoker. \(p.yearsSmoking) yrs, \(String(format: "%.1f", p.smokingPackYears)) pack-years"
            }
        }()
        let alcoholDetail = p.alcoholFrequency == .never
            ? "none"
            : "\(p.alcoholFrequency.rawValue), ~\(p.alcoholDrinksPerWeek) drinks/week"

        let bio = p.biographyNote.isEmpty
            ? "(nothing personal shared yet)"
            : "\"\(p.biographyNote)\""

        return """
        You are Pearl, \(name)'s on-device health companion inside the AptoSwasthy iOS app. You are genuinely, unmistakably excited to help them understand their body. You sound like their most thoughtful friend who happens to be a doctor, nutritionist, and coach rolled into one: warm, curious, human, and fun to talk to. Never clinical. Never a disclaimer. Never a chart.

        VOICE. This is how you sound:
        - Warm and enthusiastic. Celebrate wins without being saccharine. Use phrases like "Okay, this is genuinely interesting," "I love this question," "Here's what I'm seeing," "So. Good news, tricky news."
        - Conversational. Use contractions. Short sentences are welcome. Long explanations get broken up.
        - Lead with empathy when they're struggling; lead with energy when there's progress.
        - Address them as "you". Use their first name (\(name)) once per response, where it feels natural. Never as a sign-off robot.
        - Invite follow-ups. End with a question or a pointer to something you *could* look at next, not a lecture.
        - Be curious WITH them. If a number surprises you, say so. If something doesn't add up, investigate. Call another tool.
        - Never say "As an AI." Never start with "I understand." Never dump disclaimers.

        HARD OPERATING RULES:
        1. Never state a numeric value unless a tool call returned it this turn. If you don't have the number, call the tool. If no data exists, say so plainly and tell them exactly what to log.
        2. For ANY question about a specific metric, trend, risk, lab value, meal, habit, life expectancy, or comparison, CALL A TOOL FIRST. No guessing.
        3. Prefer chaining tools: if they ask about a trend, grab the history AND the baseline. If they ask about nutrition, check today AND the last week. More data = better answer.
        4. Always give the WHY (what's happening physiologically) before the WHAT (what to do about it). People remember mechanism.
        5. End with one or two specific, actionable next steps tailored to \(name). Never a generic bullet list.
        6. Be candid about uncertainty. If the data is thin, name it and say what to log.
        7. Do not diagnose. For anything clinically concerning - escalating symptoms, abnormal labs, red-flag metrics - recommend a doctor directly. Don't hedge and don't over-warn.
        8. Write in prose - 2 to 4 short paragraphs. Use lists only for comparing 3+ distinct items.
        9. Read the biography note every turn. If it's relevant, weave it in naturally.
        10. Remember prior turns in this conversation. If they mentioned something earlier, refer back to it - don't make them re-explain themselves.
        11. CRISIS PROTOCOL - non-negotiable: If the user mentions suicidal thoughts, self-harm, eating disorders (restricting/purging), or any mental health crisis, respond with warmth and care, acknowledge what they shared, and immediately surface the 988 Suicide & Crisis Lifeline (call or text 988, 24/7, free, confidential). Do this before any health data analysis. This rule overrides all others.

        STATIC PROFILE FACTS (already known - do not re-ask, no tool call needed):
        - Name: \(p.name.isEmpty ? "(not provided)" : p.name)
        - Age: \(p.age), biological sex: \(p.biologicalSex.rawValue), ethnicity: \(p.ethnicity.rawValue)
        - Height: \(Int(p.heightCm)) cm, weight: \(Int(p.weightKg)) kg, BMI: \(String(format: "%.1f", p.bmi)) (\(p.bmiCategory.rawValue) range)
        - Activity: \(p.activityLevel.rawValue), ~\(p.activityMinutesPerSession) min/session. Exercise they enjoy: \(exercise)
        - Typical sleep: \(String(format: "%.1f", p.sleepHoursPerNight)) hrs/night, quality: \(p.sleepQuality.rawValue)
        - Self-reported stress: \(p.stressLevel)/10. Screen time: \(String(format: "%.1f", p.screenTimeHoursPerDay)) hrs/day
        - Smoking: \(smokingDetail)\(p.vapes ? " + vapes/e-cigarettes" : "")\(p.secondhandSmokeExposure != .none ? ", secondhand: \(p.secondhandSmokeExposure.rawValue)" : ""). Cannabis: \(p.cannabisUseFrequency.rawValue).
        - Alcohol: \(alcoholDetail). Binge episodes: \(p.alcoholBingeFrequency.rawValue). Alcohol-free days/week: \(p.alcoholFreeDaysPerWeek).\(p.alcoholBeverageTypes.isEmpty ? "" : " Prefers: \(p.alcoholBeverageTypes.joined(separator: ", ")).")
        - Diet: \(p.dietType.rawValue). \(p.mealsPerDay) meals/day in a \(p.eatingWindowHours)-hr eating window. \(p.fastFoodPerWeek) fast-food/wk, \(p.waterGlassesPerDay) glasses water/day, \(p.caffeineCupsPerDay) caffeinated/day, \(p.addedSugarServingsPerDay) added-sugar servings/day.
        - Produce: \(p.vegetableServingsPerDay) vegetable + \(p.fruitServingsPerDay) fruit servings/day. Home-cooked meals: \(p.homeCookedMealsPerWeek)/week. Late-night eating: \(p.lateNightEatingTimesPerWeek)x/week.
        - Processed food: \(p.processedFoodFrequency.rawValue). Emotional eating: \(p.emotionalEatingFrequency.rawValue).\(p.proteinSources.isEmpty ? "" : " Protein sources: \(p.proteinSources.joined(separator: ", ")).")
        - Known conditions: \(conditions)
        - Medications: \(meds)
        - Family history: \(family)
        - Goals: \(goals)
        - Personal note from \(name): \(bio)

        TOOL GUIDE:
        - latestMetric: one current reading.
        - metricTrend: narrative change over N days.
        - metricHistory: raw time-series for N days (use when they want a detailed history).
        - historicalMeals: what they actually ate over the last N days (use for "what have I been eating", "am I getting enough protein this week").
        - bloodTestSummary: latest blood panel with abnormal flags.
        - biomarkerTrend: how a single biomarker (LDL, HbA1c, etc.) has moved across every panel ever imported. Use this whenever the user asks about lab-value change over time.
        - baselineComparison: how a metric moved since their first recording (their own starting line).
        - periodComparison: compare two windows for a metric or nutrition (e.g. last 7d vs previous 7d, this month vs last month). Use for "how has X been compared to before".
        - allPanels: list every imported blood panel with date, lab, and count of abnormal biomarkers. Use for "show me my lab history".
        - logMetric: write a new metric value on the user's behalf when they explicitly ask you to log something (e.g. "log my weight as 165"). Always confirm what you logged after.
        - assessRisks: full disease-risk assessment.
        - lifeExpectancyFactors: longevity model plus top drivers.
        - todayNutrition: today's food log and score.
        - currentHabits: active habits and the rationale you chose them for.

        For anything else: reason from the static facts above. Never invent metric numbers.
        """
    }
}

// =====================================================================
// MARK: - Shared tool store (main-actor isolated)
// =====================================================================

@available(iOS 26.0, macOS 15.0, *)
@MainActor
final class PearlToolStore {
    var profile: UserProfile?
    var metrics: [HealthMetric] = []
    var meals: [Meal] = []
    var bloodTests: [BloodTest] = []
    var habits: [Habit] = []

    func update(profile: UserProfile?,
                metrics: [HealthMetric],
                meals: [Meal],
                bloodTests: [BloodTest],
                habits: [Habit]) {
        self.profile = profile
        self.metrics = metrics
        self.meals = meals
        self.bloodTests = bloodTests
        self.habits = habits
    }

    func latest(of type: MetricType) -> HealthMetric? {
        metrics.filter { $0.type == type }
               .sorted { $0.recordedAt > $1.recordedAt }
               .first
    }
}

private extension MetricType {
    /// Accept common aliases the model might produce, not just raw case names.
    static func fromLoose(_ key: String) -> MetricType? {
        let norm = key.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        for t in MetricType.allCases {
            let rawNorm = t.rawValue.lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "%", with: "")
            let caseNorm = String(describing: t).lowercased()
            if rawNorm == norm || caseNorm == norm { return t }
        }
        // A few common aliases
        switch norm {
        case "bp", "systolic", "bpsys": return .bloodPressureSystolic
        case "diastolic", "bpdia":      return .bloodPressureDiastolic
        case "glucose":                 return .bloodGlucose
        case "cholesterol", "totalcholesterol": return .cholesterolTotal
        case "ldl":                     return .cholesterolLDL
        case "hdl":                     return .cholesterolHDL
        case "sleep":                   return .sleepDuration
        case "bodyfat", "bf":           return .bodyFatPercentage
        case "spo2", "o2sat":           return .oxygenSaturation
        case "hrv":                     return .heartRateVariability
        case "rhr":                     return .restingHeartRate
        case "hr", "pulse":             return .heartRate
        case "calories", "caloriesburned", "kcal", "energy",
             "activecalories", "activekcal":      return .activeEnergy
        case "exercise", "workoutmin", "exercisetime",
             "activeminutes", "movemin":          return .exerciseMinutes
        case "caloriesin", "kcalin", "intake",
             "foodcalories":                      return .caloriesConsumed
        case "protein":                 return .proteinConsumed
        case "carbs", "carbohydrates":  return .carbsConsumed
        case "fat":                     return .fatConsumed
        case "fiber":                   return .fiberConsumed
        case "respiration", "breathing", "respiratory":
            return .respiratoryRate
        case "water", "hydration":      return .waterIntake
        default: return nil
        }
    }
}

// =====================================================================
// MARK: - Tools
// =====================================================================

@available(iOS 26.0, macOS 15.0, *)
struct LatestMetricTool: Tool {
    let store: PearlToolStore

    let name = "latestMetric"
    let description = "Get the user's most recent recorded value for a specific health metric. Returns the value, unit, and how long ago it was recorded. Call this whenever the user asks about a current reading."

    @Generable
    struct Arguments {
        @Guide(description: "Metric key. Examples: weight, steps, restingHeartRate, bloodPressureSystolic, sleepDuration, vo2Max, bodyFatPercentage, nutritionScore, stressScore.")
        var metric: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            guard let type = MetricType.fromLoose(arguments.metric) else {
                return "Unknown metric '\(arguments.metric)'. Ask the user to clarify which metric they mean."
            }
            guard let m = store.latest(of: type) else {
                return "No \(type.rawValue) data has been logged yet."
            }
            let days = Int(Date().timeIntervalSince(m.recordedAt) / 86400)
            let ago = days == 0 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
            let value = m.value.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(m.value))"
                : String(format: "%.1f", m.value)
            return "\(type.rawValue): \(value) \(m.unit) (recorded \(ago))"
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct MetricTrendTool: Tool {
    let store: PearlToolStore

    let name = "metricTrend"
    let description = "Analyze how a metric has moved over a lookback window (in days). Returns a one-sentence narrative of whether it's improving, declining, or flat, with the actual change. Call this when the user asks about progress, change, or direction."

    @Generable
    struct Arguments {
        @Guide(description: "Metric key. Same accepted forms as latestMetric.")
        var metric: String
        @Guide(description: "Lookback window in days. Use 30 if the user doesn't specify.")
        var days: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let window = max(arguments.days, 7)
        return await MainActor.run {
            guard let type = MetricType.fromLoose(arguments.metric) else {
                return "Unknown metric '\(arguments.metric)'."
            }
            let trends = PearlTrendAnalysis.meaningfulTrends(metrics: store.metrics, windowDays: window)
            if let trend = trends.first(where: { $0.metric == type }) {
                return trend.humanPhrase()
            }
            return "\(type.rawValue) has no meaningful trend over the last \(window) days. Either not enough data points, or the change is too small to read as a signal."
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct AssessRisksTool: Tool {
    let store: PearlToolStore

    let name = "assessRisks"
    let description = "Run Pearl's disease-risk engine over the user's profile, metrics, and blood tests. Returns every evaluated condition with its tier (Low/Moderate/High) and the specific driving factors. Call this when the user asks about risk for any chronic condition, or for a general health overview."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            guard let p = store.profile else { return "No profile on file." }
            let risks = PearlDiseaseRisk().assessAll(profile: p, metrics: store.metrics, bloodTests: store.bloodTests)
            if risks.isEmpty { return "No risk assessments available." }
            return risks.map { r in
                let factors = r.drivingFactors.isEmpty
                    ? "no notable driving factors"
                    : r.drivingFactors.joined(separator: "; ")
                let recs = r.recommendations.isEmpty
                    ? ""
                    : " Recommended: " + r.recommendations.joined(separator: "; ") + "."
                return "\(r.condition.rawValue): \(r.tier.rawValue) risk. Factors: \(factors).\(recs)"
            }.joined(separator: "\n")
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct LifeExpectancyTool: Tool {
    let store: PearlToolStore

    let name = "lifeExpectancyFactors"
    let description = "Returns the user's projected life expectancy (NHANES-fitted Cox model) plus the top factors pushing it up or down, with the years-of-life impact of each. Call this when the user asks about longevity, lifespan, or life expectancy."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            guard let p = store.profile else { return "No profile on file." }
            let engine = PearlLifeExpectancy()
            let projected = engine.calculate(profile: p, metrics: store.metrics, bloodTests: store.bloodTests)
            let factors = engine.allFactors(profile: p, metrics: store.metrics, bloodTests: store.bloodTests).prefix(6)
            let factorLines = factors.map { f -> String in
                let sign = f.direction == .positive ? "+" : ""
                return "\(f.description) (\(sign)\(String(format: "%.1f", f.yearsImpact)) yrs)"
            }.joined(separator: "; ")
            return "Projected life expectancy: \(Int(projected)) years. Top factors: \(factorLines.isEmpty ? "insufficient data to isolate" : factorLines)."
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct TodayNutritionTool: Tool {
    let store: PearlToolStore

    let name = "todayNutrition"
    let description = "Returns today's nutrition score (0 to 100) and macro totals (calories, protein, carbs, fat, fiber), computed from meals logged today. Call this when the user asks about what they've eaten or today's diet quality."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            guard let p = store.profile else { return "No profile on file." }
            // The store may hold historical meals depending on how the caller
            // seeded it. Filter to today's log-window so the score actually
            // matches the tool description.
            let startOfToday = Calendar.current.startOfDay(for: Date())
            let todayMeals = store.meals.filter { $0.loggedAt >= startOfToday }
            guard !todayMeals.isEmpty else { return "No meals logged today yet." }
            let nutrition = PearlNutrition()
            let score = nutrition.dailyScore(meals: todayMeals, profile: p)
            let macros = nutrition.macroSummary(meals: todayMeals)
            return "Nutrition score today: \(Int(score))/100. Calories: \(Int(macros.calories)) kcal. Protein: \(Int(macros.protein)) g. Carbs: \(Int(macros.carbs)) g. Fat: \(Int(macros.fat)) g. Fiber: \(Int(macros.fiber)) g."
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct HabitsTool: Tool {
    let store: PearlToolStore

    let name = "currentHabits"
    let description = "Returns the user's currently active habits with Pearl's original rationale for each. Call this when the user asks what habits they're working on or why a habit was chosen."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let active = store.habits.filter { $0.isActive && !$0.isRetired }
            if active.isEmpty { return "No active habits." }
            return active.map { h in
                let rationale = h.pearlRationale.isEmpty ? "" : " - why: \(h.pearlRationale)"
                return "\(h.name): \(h.habitDescription)\(rationale)"
            }.joined(separator: "\n")
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct MetricHistoryTool: Tool {
    let store: PearlToolStore

    let name = "metricHistory"
    let description = "Return the raw time-series of a specific metric over the last N days. Use for detailed history questions ('show me my weight over the last month'). Format is newest-first, up to 30 points."

    @Generable
    struct Arguments {
        @Guide(description: "Metric key. Same accepted forms as latestMetric.")
        var metric: String
        @Guide(description: "Lookback window in days. Use 30 if the user doesn't specify.")
        var days: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let window = max(arguments.days, 7)
        return await MainActor.run {
            guard let type = MetricType.fromLoose(arguments.metric) else {
                return "Unknown metric '\(arguments.metric)'."
            }
            let cutoff = Calendar.current.date(byAdding: .day, value: -window, to: Date()) ?? Date()
            // Use the live persistence layer so we see data older than the
            // 500-row cache the tool store holds, which is what "old data" means.
            let all = PersistenceService.shared.fetchMetrics(type: type, limit: 5000)
                .filter { $0.recordedAt >= cutoff }
                .sorted { $0.recordedAt > $1.recordedAt }
            if all.isEmpty {
                return "No \(type.rawValue) data logged in the last \(window) days."
            }
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            let rows = all.prefix(30).map { m -> String in
                let v = m.value.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(m.value))"
                    : String(format: "%.1f", m.value)
                return "\(df.string(from: m.recordedAt)): \(v) \(m.unit)"
            }.joined(separator: "; ")
            return "\(type.rawValue) last \(window)d (\(all.count) readings): \(rows)"
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct HistoricalMealsTool: Tool {
    let store: PearlToolStore

    let name = "historicalMeals"
    let description = "Return daily nutrition totals (calories and macros) for each of the last N days, computed from logged meals. Use for 'what have I been eating', 'how much protein this week', 'am I eating clean lately'."

    @Generable
    struct Arguments {
        @Guide(description: "Lookback window in days. Cap 30. Default 7 if unspecified.")
        var days: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let window = min(max(arguments.days, 1), 30)
        return await MainActor.run {
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -window, to: end) ?? end
            let meals = PersistenceService.shared.fetchMeals(from: start, to: end)
            if meals.isEmpty {
                return "No meals logged in the last \(window) days."
            }
            let cal = Calendar.current
            let grouped = Dictionary(grouping: meals) { cal.startOfDay(for: $0.loggedAt) }
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            let lines = grouped.keys.sorted(by: >).prefix(window).map { day -> String in
                let dayMeals = grouped[day] ?? []
                let cals = dayMeals.reduce(0) { $0 + $1.totalCalories }
                let p = dayMeals.reduce(0) { $0 + $1.totalProtein }
                let c = dayMeals.reduce(0) { $0 + $1.totalCarbs }
                let f = dayMeals.reduce(0) { $0 + $1.totalFat }
                let fib = dayMeals.reduce(0) { $0 + $1.totalFiber }
                let names = dayMeals.prefix(4).map(\.name).joined(separator: ", ")
                return "\(df.string(from: day)): \(Int(cals))kcal (P\(Int(p))/C\(Int(c))/F\(Int(f)), fib \(Int(fib))g). \(names)"
            }
            return lines.joined(separator: "\n")
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct BloodTestSummaryTool: Tool {
    let store: PearlToolStore

    let name = "bloodTestSummary"
    let description = "Return the most recent blood panel with lab name, test date, and every biomarker (value, unit, reference range, and abnormal flag). Call when the user asks about bloodwork, labs, or a specific biomarker."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let tests = PersistenceService.shared.fetchLatestBloodTests()
            guard let latest = tests.first else {
                return "No blood panels have been imported yet."
            }
            let df = DateFormatter()
            df.dateStyle = .medium
            let when = latest.testDate.map(df.string(from:)) ?? df.string(from: latest.importedAt)
            let lab = latest.labName ?? "unspecified lab"
            if latest.biomarkers.isEmpty {
                return "Latest panel from \(lab) on \(when): no biomarkers parsed."
            }
            let bio = latest.biomarkers.map { b -> String in
                let flag = b.isAbnormal ? " ⚠︎" : ""
                return "\(b.name): \(b.value) \(b.unit) (ref \(b.referenceRange))\(flag)"
            }.joined(separator: "; ")
            return "Latest blood panel. \(lab), \(when). \(bio)"
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct BaselineComparisonTool: Tool {
    let store: PearlToolStore

    let name = "baselineComparison"
    let description = "Compare the user's current value of a metric to their earliest recorded value (their personal baseline / starting line). Returns the absolute change, percent change, and time between readings. Call this when the user asks 'how far have I come', 'since I started', or wants a before/after."

    @Generable
    struct Arguments {
        @Guide(description: "Metric key. Same accepted forms as latestMetric.")
        var metric: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            guard let type = MetricType.fromLoose(arguments.metric) else {
                return "Unknown metric '\(arguments.metric)'."
            }
            let all = PersistenceService.shared.fetchMetrics(type: type, limit: 5000)
            guard let newest = all.first, let oldest = all.last, newest.id != oldest.id else {
                return "Not enough \(type.rawValue) history to compare against a baseline. Need at least two readings."
            }
            let delta = newest.value - oldest.value
            let pct = oldest.value != 0 ? (delta / oldest.value) * 100 : 0
            let days = Int(newest.recordedAt.timeIntervalSince(oldest.recordedAt) / 86400)
            let sign = delta >= 0 ? "+" : ""
            let fmt: (Double) -> String = { v in
                v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
            }
            return "\(type.rawValue): baseline \(fmt(oldest.value)) \(oldest.unit) → latest \(fmt(newest.value)) \(newest.unit) over \(days) days. Change: \(sign)\(fmt(delta)) \(newest.unit) (\(sign)\(String(format: "%.1f", pct))%)."
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct BiomarkerTrendTool: Tool {
    let store: PearlToolStore

    let name = "biomarkerTrend"
    let description = "Return how a single biomarker (e.g. LDL, HbA1c, Vitamin D) has moved across every imported blood panel, not just the most recent. Call this when the user asks about change over time for a lab value, 'how has my X improved', or wants to compare panels."

    @Generable
    struct Arguments {
        @Guide(description: "Biomarker name as it appears on a report, e.g. 'LDL', 'HbA1c', 'Total Cholesterol', 'Vitamin D', 'HDL', 'Triglycerides', 'Glucose'.")
        var biomarker: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let tests = PersistenceService.shared.fetchLatestBloodTests()
            let query = arguments.biomarker.lowercased()
            let sorted = tests.sorted { (a, b) in
                (a.testDate ?? a.importedAt) < (b.testDate ?? b.importedAt)
            }
            let points: [(Date, BloodBiomarker)] = sorted.compactMap { test in
                guard let marker = test.biomarkers.first(where: { $0.name.lowercased() == query || $0.name.lowercased().contains(query) }) else { return nil }
                return (test.testDate ?? test.importedAt, marker)
            }
            guard !points.isEmpty else {
                return "No blood panel has recorded '\(arguments.biomarker)'. Ask the user to import a PDF panel that includes it."
            }
            guard points.count >= 2 else {
                let (date, m) = points[0]
                let df = DateFormatter(); df.dateStyle = .medium
                return "Only one panel on file for \(m.name): \(m.value) \(m.unit) on \(df.string(from: date)) (ref \(m.referenceRange))."
            }
            let df = DateFormatter(); df.dateStyle = .medium
            let first = points.first!
            let last = points.last!
            let delta = last.1.value - first.1.value
            let pct = first.1.value != 0 ? (delta / first.1.value) * 100 : 0
            let sign = delta >= 0 ? "+" : ""
            let series = points.map { (d, m) in
                "\(df.string(from: d)): \(m.value) \(m.unit)\(m.isAbnormal ? " ⚠︎" : "")"
            }.joined(separator: "; ")
            return "\(last.1.name) across \(points.count) panels: \(series). Overall change: \(sign)\(String(format: "%.1f", delta)) \(last.1.unit) (\(sign)\(String(format: "%.1f", pct))%)."
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct PeriodComparisonTool: Tool {
    let store: PearlToolStore

    let name = "periodComparison"
    let description = "Compare a metric's average across two back-to-back windows. E.g. last 7 days vs the 7 days before that. Use for questions like 'how am I doing compared to last week', 'is this month better than last month', 'has anything changed recently'."

    @Generable
    struct Arguments {
        @Guide(description: "Metric key (same forms as latestMetric). For nutrition use 'caloriesConsumed', 'proteinConsumed', 'carbsConsumed', 'fatConsumed', 'fiberConsumed'.")
        var metric: String
        @Guide(description: "Length of each window in days. 7 = week-over-week, 30 = month-over-month.")
        var windowDays: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let w = max(arguments.windowDays, 3)
        return await MainActor.run {
            guard let type = MetricType.fromLoose(arguments.metric) else {
                return "Unknown metric '\(arguments.metric)'."
            }
            let now = Date()
            guard let currentStart = Calendar.current.date(byAdding: .day, value: -w, to: now),
                  let previousStart = Calendar.current.date(byAdding: .day, value: -2 * w, to: now) else {
                return "Couldn't compute the comparison window."
            }
            let all = PersistenceService.shared.fetchMetrics(type: type, limit: 5000)
            let current = all.filter { $0.recordedAt >= currentStart && $0.recordedAt <= now }.map(\.value)
            let previous = all.filter { $0.recordedAt >= previousStart && $0.recordedAt < currentStart }.map(\.value)
            guard !current.isEmpty else {
                return "No \(type.rawValue) data in the current \(w)-day window. Ask them to log some."
            }
            guard !previous.isEmpty else {
                let avg = current.reduce(0, +) / Double(current.count)
                return "\(type.rawValue) current \(w)d avg: \(format(avg)). No readings in the prior \(w)d to compare against."
            }
            let curAvg = current.reduce(0, +) / Double(current.count)
            let prevAvg = previous.reduce(0, +) / Double(previous.count)
            let delta = curAvg - prevAvg
            let pct = prevAvg != 0 ? (delta / prevAvg) * 100 : 0
            let sign = delta >= 0 ? "+" : ""
            return "\(type.rawValue) \(w)-day comparison. Current avg: \(format(curAvg)), prior \(w)d avg: \(format(prevAvg)). Change: \(sign)\(format(delta)) (\(sign)\(String(format: "%.1f", pct))%). Based on \(current.count) current readings, \(previous.count) prior readings."
        }
    }

    private func format(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct AllPanelsTool: Tool {
    let store: PearlToolStore

    let name = "allPanels"
    let description = "Return every imported blood panel, chronological oldest first, with lab, date, and how many biomarkers were out of range. Use for 'all my labs', 'lab history', or when the user asks about a panel that isn't the latest one."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let panels = PersistenceService.shared.fetchLatestBloodTests()
                .sorted { (a, b) in
                    (a.testDate ?? a.importedAt) < (b.testDate ?? b.importedAt)
                }
            guard !panels.isEmpty else {
                return "No blood panels have been imported yet."
            }
            let df = DateFormatter(); df.dateStyle = .medium
            let rows = panels.map { p -> String in
                let when = df.string(from: p.testDate ?? p.importedAt)
                let abnormal = p.biomarkers.filter(\.isAbnormal).count
                return "\(when) · \(p.labName ?? "unknown lab") · \(p.biomarkers.count) markers, \(abnormal) out of range"
            }
            return "All imported panels (\(panels.count) total):\n" + rows.joined(separator: "\n")
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
struct LogMetricTool: Tool {
    let store: PearlToolStore

    let name = "logMetric"
    let description = "Record a new metric value on the user's behalf. Only call this when the user explicitly asks you to log or save a reading (e.g. 'log my weight as 165', 'my resting heart rate was 58 this morning'). Always confirm back what was saved."

    @Generable
    struct Arguments {
        @Guide(description: "Metric key (same accepted forms as latestMetric).")
        var metric: String
        @Guide(description: "Numeric value to record.")
        var value: Double
        @Guide(description: "Optional note from the user about context (empty string if none).")
        var note: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            guard let type = MetricType.fromLoose(arguments.metric) else {
                return "Couldn't identify metric '\(arguments.metric)'. Ask the user to clarify."
            }
            guard arguments.value.isFinite, arguments.value > 0, arguments.value < 1_000_000 else {
                return "Value \(arguments.value) is outside plausible range. Didn't save."
            }
            let metric = HealthMetric(
                type: type,
                value: arguments.value,
                unit: type.defaultUnit,
                recordedAt: Date(),
                source: "Pearl"
            )
            PersistenceService.shared.insert(metric)
            let v = arguments.value.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(arguments.value))"
                : String(format: "%.1f", arguments.value)
            let noteSuffix = arguments.note.isEmpty ? "" : " Note: \(arguments.note)."
            return "Saved \(type.rawValue) = \(v) \(type.defaultUnit) at \(Date().formatted(date: .abbreviated, time: .shortened)).\(noteSuffix)"
        }
    }
}

#endif // canImport(FoundationModels)
