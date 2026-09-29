import Foundation
import Observation

@MainActor
@Observable
final class AIViewModel {
    var messages: [ConversationMessage] = []
    var isStreaming = false
    var streamingContent = ""
    var profile: UserProfile? = nil
    var metrics: [HealthMetric] = []
    var meals: [Meal] = []
    var bloodTests: [BloodTest] = []
    var habits: [Habit] = []
    /// True when Pearl is running on Apple's on-device Foundation Models.
    /// False when we've fallen back to the rule-based engine.
    var usingFoundationModel: Bool = false

    private let persistence = PersistenceService.shared
    private let ruleConversation = PearlConversation()
    /// Typed as AnyObject so we can hold it without leaking the iOS-26-gated
    /// type through the stored-property declaration.
    @ObservationIgnored private var foundationConversationStorage: AnyObject?
    @ObservationIgnored var streamingTask: Task<Void, Never>?
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored nonisolated(unsafe) private var profileUpdateObserver: NSObjectProtocol?

    init() {
        profileUpdateObserver = NotificationCenter.default.addObserver(
            forName: .profileUpdated, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reloadForProfileChange() }
        }
    }

    deinit {
        if let token = profileUpdateObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Re-read profile + data from disk and rewire both engines so Pearl's
    /// next reply reflects the updated profile. Conversation history stays
    /// intact - this is a refresh, not a reset.
    private func reloadForProfileChange() {
        profile = persistence.fetchProfile()
        metrics = fetchMetricsForAI()
        meals = persistence.fetchTodayMeals()
        bloodTests = persistence.fetchLatestBloodTests()
        habits = persistence.fetchActiveHabits()
        refreshAllEngines()
    }

    // AI trend analysis spans 30 days across multiple metric types. 500 covers ~4 months
    // of daily logging across 4+ metrics - well beyond what display views need (100).
    private func fetchMetricsForAI() -> [HealthMetric] {
        persistence.fetchMetrics(limit: 500)
    }

    func load() {
        guard !hasLoaded else {
            profile = persistence.fetchProfile()
            metrics = fetchMetricsForAI()
            meals = persistence.fetchTodayMeals()
            bloodTests = persistence.fetchLatestBloodTests()
            habits = persistence.fetchActiveHabits()
            refreshAllEngines()
            return
        }
        hasLoaded = true
        profile = persistence.fetchProfile()
        metrics = fetchMetricsForAI()
        meals = persistence.fetchTodayMeals()
        bloodTests = persistence.fetchLatestBloodTests()
        habits = persistence.fetchActiveHabits()
        messages = persistence.fetchConversationHistory()
        ruleConversation.setup(profile: profile, metrics: metrics, meals: meals)
        spinUpFoundationModelIfAvailable()
    }

    func send(_ text: String) {
        guard !isStreaming else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Refresh data so both engines see anything logged on other tabs since load().
        metrics = fetchMetricsForAI()
        meals = persistence.fetchTodayMeals()
        bloodTests = persistence.fetchLatestBloodTests()
        habits = persistence.fetchActiveHabits()
        refreshAllEngines()

        let userMsg = ConversationMessage(role: .user, content: trimmed)
        messages.append(userMsg)
        persistence.insert(userMsg)

        streamingTask?.cancel()
        isStreaming = true
        streamingContent = ""

        streamingTask = Task { [weak self] in
            defer {
                self?.isStreaming = false
                self?.streamingContent = ""
            }
            guard let self else { return }
            do {
                for try await snapshot in self.chosenStream(userMessage: trimmed) {
                    self.streamingContent = snapshot
                }
                guard !Task.isCancelled else { return }
                let final = self.streamingContent
                guard !final.isEmpty else { return }
                let response = ConversationMessage(role: .pearl, content: final)
                self.messages.append(response)
                self.persistence.insert(response)
            } catch {
                guard !Task.isCancelled else { return }
                // If the Foundation Models path errored, fall back to rule engine
                // for this single turn so the user still gets a reply.
                if self.usingFoundationModel {
                    self.ruleConversation.refreshData(profile: self.profile, metrics: self.metrics, meals: self.meals)
                    do {
                        var accumulated = ""
                        for try await snapshot in self.ruleConversation.stream(userMessage: trimmed) {
                            accumulated = snapshot
                            self.streamingContent = accumulated
                        }
                        let response = ConversationMessage(role: .pearl, content: accumulated)
                        self.messages.append(response)
                        self.persistence.insert(response)
                        return
                    } catch {
                        // fall through to generic error
                    }
                }
                let response = ConversationMessage(role: .pearl, content: "Something went wrong. Please try again.")
                self.messages.append(response)
                self.persistence.insert(response)
            }
        }
    }

    /// Dynamically generated welcome prompts based on the user's actual data.
    /// Picks the most relevant questions for what Pearl can answer right now,
    /// rather than showing the same five hardcoded strings to every user.
    func welcomeSuggestions() -> [String] {
        var picks: [String] = []
        let firstName = profile?.name.split(separator: " ").first.map(String.init) ?? ""
        let greeting = firstName.isEmpty ? "" : ", \(firstName)"

        // For time-sensitive metrics (sleep, steps, RHR), only surface suggestions
        // if data is from the last 48 hours - avoids stale readings triggering alerts.
        let cutoff48h = Date().addingTimeInterval(-48 * 3600)
        let recent: (MetricType) -> Double? = { type in
            self.metrics.first(where: { $0.type == type && $0.recordedAt >= cutoff48h })?.value
        }
        // Weight/blood tests update less frequently; use the latest regardless of age.
        let latest: (MetricType) -> Double? = { type in
            self.metrics.first(where: { $0.type == type })?.value
        }

        if let sleep = recent(.sleepDuration) {
            if sleep < 6.5 {
                picks.append("Why am I only sleeping \(String(format: "%.1f", sleep))h and what's that costing me?")
            } else {
                picks.append("Is my sleep enough to support recovery\(greeting)?")
            }
        }
        if let weight = latest(.weight), let p = profile, p.heightCm > 0 {
            let bmi = weight / pow(p.heightCm / 100.0, 2)
            if bmi >= 25 {
                picks.append("What would I need to change to get my BMI into the healthy range?")
            } else if bmi < 18.5 {
                picks.append("My BMI is on the low side. What should I focus on?")
            }
        }
        if let rhr = recent(.restingHeartRate) {
            if rhr > 75 {
                picks.append("My resting heart rate is \(Int(rhr)). Should I be concerned?")
            }
        }
        if let steps = recent(.steps) {
            if steps < 6000 {
                picks.append("I averaged \(Int(steps)) steps today. How much does that hurt my longevity?")
            } else {
                picks.append("How are my step counts impacting my health goals?")
            }
        }
        if !bloodTests.isEmpty {
            picks.append("Walk me through my latest blood test results.")
        }
        if !habits.isEmpty {
            picks.append("Which of my habits is moving the needle the most?")
        }

        // Always-useful fallbacks if we don't have enough data yet.
        let fallbacks = [
            "What's the single biggest thing I could change for my health\(greeting)?",
            "Explain what's driving my life expectancy estimate.",
            "What should I track that I'm not already tracking?",
            "Summarize how I'm doing this week."
        ]
        for f in fallbacks where picks.count < 5 { picks.append(f) }

        return Array(picks.prefix(5))
    }

    func clearConversation() {
        streamingTask?.cancel()
        streamingTask = nil
        messages = []
        streamingContent = ""
        isStreaming = false
        let history = persistence.fetchConversationHistory()
        history.forEach { persistence.delete($0) }
        ruleConversation.setup(profile: profile, metrics: metrics, meals: meals)
        if #available(iOS 26.0, *) {
            (foundationConversationStorage as? PearlFoundationConversation)?.resetSession(profile: profile)
        }
    }

    // MARK: - Routing

    /// Return a stream from whichever engine is active, keeping call sites tidy.
    private func chosenStream(userMessage: String) -> AsyncThrowingStream<String, Error> {
        if #available(iOS 26.0, *),
           let foundation = foundationConversationStorage as? PearlFoundationConversation {
            return foundation.stream(userMessage: userMessage)
        }
        return ruleConversation.stream(userMessage: userMessage)
    }

    private func refreshAllEngines() {
        ruleConversation.refreshData(profile: profile, metrics: metrics, meals: meals)
        if #available(iOS 26.0, *),
           let foundation = foundationConversationStorage as? PearlFoundationConversation {
            foundation.refreshData(profile: profile,
                                   metrics: metrics,
                                   meals: meals,
                                   bloodTests: bloodTests,
                                   habits: habits)
        }
    }

    private func spinUpFoundationModelIfAvailable() {
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            guard PearlFoundationConversation.isAvailable else {
                usingFoundationModel = false
                return
            }
            foundationConversationStorage = PearlFoundationConversation(
                profile: profile,
                metrics: metrics,
                meals: meals,
                bloodTests: bloodTests,
                habits: habits
            )
            usingFoundationModel = true
            #else
            usingFoundationModel = false
            #endif
        } else {
            usingFoundationModel = false
        }
    }
}
