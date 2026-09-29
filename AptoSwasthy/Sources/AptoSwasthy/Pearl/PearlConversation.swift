import Foundation

// =====================================================================
//  Pearl - an original on-device reasoning engine.
//
//  No external APIs. No Foundation Models. No Claude. No internet.
//  Pure Swift: semantic intent classification, a clinical knowledge
//  base, a rule-based inference engine, and a response composer that
//  builds coherent prose from structured findings over the user's
//  actual biometric data. Output is streamed word-by-word to feel
//  like it's thinking.
// =====================================================================

@MainActor
final class PearlConversation {

    private let brain = PearlBrain()
    private let context = ConversationContext()

    /// Full reset: clears conversation context AND loads new data. Call on first load or clear.
    func setup(profile: UserProfile?, metrics: [HealthMetric], meals: [Meal]) {
        context.reset()
        brain.attach(profile: profile, metrics: metrics, meals: meals)
    }

    /// Live refresh: updates the brain's health data without clearing conversation context.
    /// Call before each message so Pearl sees new metrics/meals logged on other tabs.
    func refreshData(profile: UserProfile?, metrics: [HealthMetric], meals: [Meal]) {
        brain.attach(profile: profile, metrics: metrics, meals: meals)
    }

    func stream(userMessage: String) -> AsyncThrowingStream<String, Error> {
        let reply = brain.reply(to: userMessage, context: context)
        context.remember(query: userMessage, response: reply)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var accumulated = ""
                let tokens = Self.tokenizeForStreaming(reply)
                for token in tokens {
                    guard !Task.isCancelled else { break }
                    accumulated += token
                    continuation.yield(accumulated)
                    let pause = token.last.map { c -> UInt64 in
                        switch c {
                        case ".", "!", "?": return 140_000_000
                        case ",", ";", ":": return 70_000_000
                        default: return 20_000_000
                        }
                    } ?? 20_000_000
                    try? await Task.sleep(nanoseconds: pause)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func tokenizeForStreaming(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in text {
            if ch == " " {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(" ")
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

// =====================================================================
// MARK: - User Intent (what the user wants, not just what topic)
// =====================================================================

enum UserIntent {
    case seeking_info       // "what is my blood pressure?"
    case seeking_action     // "what should I do about my weight?"
    case expressing_worry   // "I'm worried about my heart"
    case checking_progress  // "am I getting better?"
    case comparing          // "how does my BP compare to normal?"
    case confirming         // "is 120/80 good?"
    case venting            // "I can't sleep at all lately"
    case general            // fallback
}

// =====================================================================
// MARK: - PearlBrain (the actual thinking)
// =====================================================================

@MainActor
final class PearlBrain {
    private var profile: UserProfile?
    private var metrics: [HealthMetric] = []
    private var meals: [Meal] = []

    func attach(profile: UserProfile?, metrics: [HealthMetric], meals: [Meal]) {
        self.profile = profile
        self.metrics = metrics
        self.meals = meals
    }

    private static func containsCrisisKeywords(_ lower: String) -> Bool {
        let keywords = ["suicid", "kill myself", "end my life", "want to die",
                        "don't want to live", "dont want to live", "no reason to live",
                        "not worth living", "self-harm", "self harm", "cutting myself",
                        "hurt myself", "eating disorder", "anorexia", "bulimia",
                        "starving myself", "purging", "binge and purge"]
        return keywords.contains { lower.contains($0) }
    }

    func conceptFor(metric: MetricType) -> HealthConcept? {
        switch metric {
        case .steps, .vo2Max, .fitnessScore,
             .activeEnergy, .exerciseMinutes:                return .activity
        case .restingHeartRate, .heartRate:                  return .cardiovascular
        case .bloodPressureSystolic, .bloodPressureDiastolic: return .bloodPressure
        case .weight, .bodyFatPercentage:                    return .weight
        case .bloodGlucose:                                  return .bloodSugar
        case .cholesterolTotal, .cholesterolLDL,
             .cholesterolHDL, .triglycerides:                return .cholesterol
        case .sleepDuration:                                 return .sleep
        case .waterIntake:                                   return .hydration
        case .nutritionScore, .caloriesConsumed,
             .proteinConsumed, .carbsConsumed,
             .fatConsumed, .fiberConsumed:                   return .nutrition
        case .oxygenSaturation, .respiratoryRate:            return .cardiovascular
        case .heartRateVariability, .recoveryScore,
             .stressScore:                                   return .stress
        }
    }

    func reply(to rawQuery: String, context: ConversationContext) -> String {
        guard let profile else {
            return "I need your profile to reason about your health. Complete onboarding and I'll have a full picture to work with."
        }

        let lowerRaw = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Crisis protocol - surface 988 before any other processing.
        if Self.containsCrisisKeywords(lowerRaw) {
            return "I hear you, and I want to make sure you have the right support right now. Please reach out to the 988 Suicide & Crisis Lifeline. Call or text 988, available 24/7, free, and confidential. They're trained for exactly these moments. You don't have to navigate this alone. I'm here too. Want to talk about what's going on?"
        }

        // Pass metrics to context so SmallTalk can use them for snapshot summaries
        context.lastMetrics = metrics

        // 1. Tokenize
        let tokens = SemanticEncoder.tokenize(rawQuery)

        // 2. Detect negation context - prevents "I don't smoke" from triggering smoking advice
        let negationContext = SemanticEncoder.detectNegation(rawQuery: lowerRaw)

        // 3. Detect user intent
        let intent = SemanticEncoder.classifyIntent(tokens: tokens, rawQuery: lowerRaw)

        // 4. Follow-up detection
        let isFollowUp = context.turnCount > 0 && SemanticEncoder.isFollowUp(tokens: tokens, rawQuery: rawQuery)

        // 5. Classify health concepts
        var concepts = SemanticEncoder.classify(tokens: tokens)

        // Filter out negated concepts: "I don't smoke" shouldn't trigger .smoking
        if !negationContext.isEmpty {
            concepts = concepts.filter { concept in
                let conceptTerms = concept.vocabulary.keys
                let negatedTerms = Set(negationContext)
                let overlap = conceptTerms.filter { term in
                    negatedTerms.contains(where: { neg in term.hasPrefix(neg) || neg.hasPrefix(term) })
                }
                return overlap.isEmpty
            }
        }

        if isFollowUp, concepts.isEmpty, let recent = context.lastConcepts.first {
            concepts = [recent]
        }

        // 5b. Neural re-rank
        if concepts.count > 1 {
            let reranked = PearlNeuralEmbedding.rerank(query: rawQuery, candidates: concepts)
            concepts = reranked.map(\.0)
        }

        // 5c. Trend detection
        let wantsTrend = PearlNeuralEmbedding.isAskingTrend(tokens) ||
                         PearlNeuralEmbedding.isAskingPast(tokens) ||
                         intent == .checking_progress
        if wantsTrend, let narrative = PearlTrendAnalysis.summaryNarrative(metrics: metrics) {
            let trendFindings = PearlTrendAnalysis.meaningfulTrends(metrics: metrics).prefix(3).map { t in
                Finding(concept: conceptFor(metric: t.metric) ?? concepts.first ?? .longevity,
                        severity: t.direction == .declining ? .concerning : .normal,
                        headline: t.humanPhrase(),
                        evidence: nil, mechanism: nil, lever: nil)
            }
            if !trendFindings.isEmpty {
                context.record(concepts: concepts, findings: Array(trendFindings), intent: intent)
                return "Looking at the last 30 days of your data: " + narrative
            }
        }

        // 6. Quick-path for greetings, thanks, identity questions
        if concepts.isEmpty {
            if let small = SmallTalk.handle(tokens: tokens, rawQuery: rawQuery, profile: profile, context: context) {
                context.record(concepts: [], findings: [], intent: intent)
                return small
            }
        }

        // 7. Run inference
        let deduped: [HealthConcept] = {
            var seen = Set<HealthConcept>()
            var out: [HealthConcept] = []
            for c in concepts {
                let canonical: HealthConcept = (c == .bloodSugar) ? .metabolism : c
                if seen.insert(canonical).inserted {
                    out.append(c)
                }
            }
            return out
        }()
        let engine = InferenceEngine(profile: profile, metrics: metrics, meals: meals)
        var findings: [Finding] = []
        for concept in deduped.prefix(3) {
            findings.append(contentsOf: engine.findings(for: concept))
        }

        // 8. Classified but no data
        if !concepts.isEmpty, findings.isEmpty {
            context.record(concepts: concepts, findings: [], intent: intent)
            let list = concepts.map(\.humanName).joined(separator: ", ")
            return "I understood you're asking about \(list), but I don't have enough of your data logged yet to reason about it. Log more metrics and I'll be able to give you specifics."
        }

        // 9. No concepts matched
        if concepts.isEmpty {
            context.record(concepts: [], findings: [], intent: intent)
            // Try to give a helpful response based on intent
            if intent == .expressing_worry {
                return "I can hear that something's on your mind. I can look at sleep, weight, cardiovascular health, blood pressure, activity, nutrition, metabolism, stress, and longevity. Which area would help most?"
            }
            if intent == .seeking_action {
                let summary = engine.snapshotSummary()
                return "Here's a quick snapshot: \(summary) Tell me which area you'd like actionable guidance on, and I'll dig in."
            }
            let summary = engine.snapshotSummary()
            return "I'm not sure which area of your health you're asking about. I can reason about sleep, weight, cardiovascular risk, activity, nutrition, blood pressure, metabolism, stress, and longevity. Here's where you stand right now: \(summary)"
        }

        // 10. Compose
        context.record(concepts: concepts, findings: findings, intent: intent)
        return ResponseComposer.compose(
            findings: findings,
            concepts: concepts,
            profile: profile,
            query: rawQuery,
            intent: intent,
            isFollowUp: isFollowUp,
            context: context
        )
    }
}

// =====================================================================
// MARK: - Semantic Encoder
// =====================================================================

enum SemanticEncoder {

    private static let stopwords: Set<String> = [
        "a","an","the","is","are","was","were","be","been","being","do","does",
        "did","have","has","had","i","me","my","mine","you","your","we","us",
        "our","it","its","and","or","but","if","in","on","at","to","for","of",
        "with","from","by","as","that","this","these","those","what","which",
        "who","whom","why","how","when","where","can","could","would","should",
        "may","might","will","shall","must","about","above","after","before",
        "am","up","down","so","not","just","like","really","very","much",
        "also","too","than","then","now","here","there","some","any","all",
        "each","every","both","few","more","most","other","such","no","only",
        "same","own","into","over","through","during","between","again","once"
    ]

    static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let split = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return split.filter { !$0.isEmpty && !stopwords.contains($0) }.map(stem)
    }

    static func stem(_ word: String) -> String {
        let suffixes = ["ational", "iveness", "fulness", "ization", "ation", "ments",
                        "ment", "ness", "able", "ible", "ing", "ied", "ies", "eds",
                        "ly", "ed", "es", "s"]
        for suf in suffixes {
            if word.count > suf.count + 2, word.hasSuffix(suf) {
                return String(word.dropLast(suf.count))
            }
        }
        return word
    }

    // Detect negated terms: "I don't smoke", "I'm not diabetic", "never drank"
    // Conservative: only grab the 1-2 words immediately after negation to avoid
    // over-filtering (e.g. "I have no idea about my blood sugar" should NOT negate "blood").
    static func detectNegation(rawQuery: String) -> [String] {
        let negPatterns = [
            "don't ", "dont ", "do not ", "doesn't ", "doesnt ", "does not ",
            "didn't ", "didnt ", "did not ", "never ", "i'm not ",
            "im not ", "haven't ", "havent ", "have not ", "isn't ", "isnt ",
            "gave up "
        ]
        // Common filler words that shouldn't count as the negated concept
        let fillers: Set<String> = ["a","an","the","any","really","very","much","even","been","have","had","doing"]
        var negated: [String] = []
        let lower = rawQuery.lowercased()
        for pattern in negPatterns {
            if let range = lower.range(of: pattern) {
                let after = lower[range.upperBound...]
                let words = after.components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty && !fillers.contains($0) }
                    .prefix(2)
                negated.append(contentsOf: words.map { stem($0) })
            }
        }
        return negated
    }

    // Classify user intent from the query
    static func classifyIntent(tokens: [String], rawQuery: String) -> UserIntent {
        let lower = rawQuery.lowercased()

        // Worry / concern patterns
        let worryPatterns = ["worried", "worry", "concerned", "scared", "afraid",
                            "nervous", "anxious about", "freaking out", "bad sign",
                            "is it serious", "should i be worried", "is this normal",
                            "am i okay", "am i ok"]
        if worryPatterns.contains(where: { lower.contains($0) }) {
            return .expressing_worry
        }

        // Action-seeking patterns
        let actionPatterns = ["what should i", "what can i", "how do i", "how can i",
                             "what do i do", "help me", "fix", "improve", "lower",
                             "reduce", "increase", "boost", "tips", "advice",
                             "recommend", "suggestion"]
        if actionPatterns.contains(where: { lower.contains($0) }) {
            return .seeking_action
        }

        // Progress / comparison
        let progressPatterns = ["getting better", "improving", "progress", "changed",
                               "trending", "compared to", "vs", "versus", "better or worse",
                               "going up", "going down", "over time"]
        if progressPatterns.contains(where: { lower.contains($0) }) {
            return .checking_progress
        }

        // Venting
        let ventPatterns = ["can't sleep", "cant sleep", "hate", "struggle",
                           "frustrated", "exhausted", "terrible", "awful",
                           "miserable", "sick of", "fed up"]
        if ventPatterns.contains(where: { lower.contains($0) }) {
            return .venting
        }

        // Confirming / checking
        let confirmPatterns = ["is that good", "is that bad", "is that okay", "is that ok",
                              "is that normal", "is this good", "is this bad", "is this okay",
                              "is this ok", "is this normal", "good or bad"]
        if confirmPatterns.contains(where: { lower.contains($0) }) {
            return .confirming
        }

        // Comparing
        if lower.contains("compare") || lower.contains("normal range") ||
           lower.contains("average") || lower.contains("typical") {
            return .comparing
        }

        // Check raw query for question openers (these get filtered as stopwords from tokens)
        let questionOpeners = ["what ", "how ", "tell me", "show me", "give me"]
        if questionOpeners.contains(where: { lower.hasPrefix($0) || lower.contains($0) }) {
            return .seeking_info
        }
        return tokens.contains(where: { ["tell", "show", "give"].contains($0) })
            ? .seeking_info : .general
    }

    static func isFollowUp(tokens: [String], rawQuery: String) -> Bool {
        let triggers: Set<String> = ["tell","more","detail","explain","expand","elaborate",
                                     "go","deeper","further","continu","keep","unpack",
                                     "break","mean","specif"]
        let lower = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("tell me more") || lower.contains("go on") ||
           lower.contains("what do you mean") || lower.contains("break that down") ||
           lower.contains("be more specific") || lower.contains("explain that") { return true }
        if lower == "why" || lower == "why?" || lower == "how?" || lower == "and?" { return true }
        return tokens.contains(where: triggers.contains) && tokens.count <= 5
    }

    static func classify(tokens: [String]) -> [HealthConcept] {
        guard !tokens.isEmpty else { return [] }

        var scores: [(HealthConcept, Double)] = []
        for concept in HealthConcept.allCases {
            let vocab = concept.vocabulary
            var score = 0.0
            for token in tokens {
                if let w = vocab[token] {
                    score += w
                    continue
                }
                let stemmed = stem(token)
                if let w = vocab[stemmed] {
                    score += w * 0.9
                    continue
                }
                for (term, w) in vocab where term.count >= 4 && stemmed.count >= 4 {
                    if term.hasPrefix(stemmed) || stemmed.hasPrefix(term) {
                        score += w * 0.5
                        break
                    }
                }
            }
            let normalized = score / Double(max(tokens.count, 1))
            if normalized > 0.18 {
                scores.append((concept, normalized))
            }
        }
        return scores.sorted { $0.1 > $1.1 }.map(\.0)
    }
}

// =====================================================================
// MARK: - Health Concepts (weighted vocabularies)
// =====================================================================

enum HealthConcept: String, CaseIterable, Hashable {
    case sleep
    case weight
    case cardiovascular
    case bloodPressure
    case activity
    case nutrition
    case metabolism
    case longevity
    case stress
    case strength
    case hydration
    case aging
    case bloodSugar
    case cholesterol
    case smoking
    case alcohol
    case medication
    case pain
    case mentalHealth

    var humanName: String {
        switch self {
        case .sleep: return "sleep"
        case .weight: return "weight"
        case .cardiovascular: return "cardiovascular health"
        case .bloodPressure: return "blood pressure"
        case .activity: return "activity"
        case .nutrition: return "nutrition"
        case .metabolism: return "metabolism"
        case .longevity: return "longevity"
        case .stress: return "stress"
        case .strength: return "strength"
        case .hydration: return "hydration"
        case .aging: return "aging"
        case .bloodSugar: return "blood sugar"
        case .cholesterol: return "cholesterol"
        case .smoking: return "smoking"
        case .alcohol: return "alcohol"
        case .medication: return "medications"
        case .pain: return "pain"
        case .mentalHealth: return "mental health"
        }
    }

    var vocabulary: [String: Double] {
        switch self {
        case .sleep: return [
            "sleep":1.0,"sleeping":1.0,"slept":1.0,"rest":0.7,"bed":0.6,"bedtime":0.8,
            "wake":0.6,"awake":0.6,"tired":0.8,"tire":0.8,"fatigue":0.8,"insomnia":1.0,"nap":0.6,
            "drowsy":0.7,"rem":0.8,"deep":0.4,"nighttime":0.6,"night":0.5,"dream":0.5,
            "restless":0.7,"restl":0.7,"hour":0.3,"snore":0.7,"snoring":0.7,"apnea":0.9,
            "toss":0.6,"turn":0.4,"melatonin":0.7,"circadian":0.8,
            "wired":0.5,"crash":0.4,"groggy":0.7,"exhaust":0.6
        ]
        case .weight: return [
            "weight":1.0,"bmi":1.0,"fat":0.7,"lose":0.7,"gain":0.7,"obese":1.0,"obesity":1.0,
            "overweight":1.0,"underweight":1.0,"slim":0.6,"heavy":0.5,"kilo":0.5,"pound":0.5,
            "scale":0.5,"body":0.4,"mass":0.5,"lean":0.6,"chubby":0.6,
            "belly":0.7,"waist":0.7,"midsection":0.6,"skinny":0.6,"thin":0.5,
            "chunk":0.5,"bloat":0.5,"gut":0.5
        ]
        case .cardiovascular: return [
            "heart":1.0,"cardiac":1.0,"cardiovascular":1.0,"cardio":0.9,"pulse":0.7,
            "rhr":0.8,"beat":0.5,"attack":0.7,"artery":0.8,"arteries":0.8,"vascular":0.8,
            "chest":0.6,"circulat":0.7,"stroke":0.8,"palpitation":0.8,
            "ticker":0.8,"flutter":0.7,"racing":0.6,"skip":0.5,
            "winded":0.6,"breathless":0.6,"shortness":0.5
        ]
        case .bloodPressure: return [
            "pressure":1.0,"hypertension":1.0,"systolic":1.0,"diastolic":1.0,"bp":1.0,
            "mmhg":0.8,"hypertensive":0.9,"blood":0.4
        ]
        case .activity: return [
            "step":1.0,"walk":0.9,"walking":0.9,"walked":0.9,"run":0.9,"running":0.9,
            "exercise":1.0,"workout":1.0,"train":0.7,"training":0.7,"active":0.8,
            "activity":1.0,"fit":0.7,"fitness":0.9,"cardio":0.6,"gym":0.8,"sport":0.7,
            "move":0.5,"movement":0.5,"aerobic":0.8,"vo2":0.9,
            "hike":0.8,"hiking":0.8,"bike":0.8,"cycling":0.8,"swim":0.8,"swimming":0.8,
            "jog":0.8,"jogging":0.8,"yoga":0.7,"pilates":0.7,"stretch":0.5,
            "couch":0.5,"lazy":0.5,"inactive":0.8
        ]
        case .nutrition: return [
            "food":0.9,"eat":0.9,"eating":0.9,"ate":0.8,"diet":1.0,"nutrition":1.0,
            "meal":0.9,"calorie":1.0,"calori":0.9,"protein":1.0,"carb":0.9,"carbs":1.0,
            "carbohydrate":1.0,"fat":0.6,"macro":0.9,"micronutrient":0.9,"vitamin":0.8,
            "fiber":0.8,"sugar":0.7,"sodium":0.7,"salt":0.6,"snack":0.7,"breakfast":0.6,
            "lunch":0.6,"dinner":0.6,"junk":0.7,"healthy":0.5,"hungry":0.6,
            "fasting":0.7,"intermittent":0.6,"keto":0.8,"paleo":0.7,"vegan":0.7,
            "vegetarian":0.7,"supplement":0.6,"craving":0.7,"binge":0.7,
            "overeating":0.8,"portion":0.7,"processed":0.7
        ]
        case .metabolism: return [
            "metabolism":1.0,"metabolic":1.0,"insulin":1.0,"glucose":1.0,"sugar":0.6,
            "diabet":1.0,"diabetes":1.0,"prediabet":1.0,"a1c":0.9,"burn":0.5,"thyroid":0.8
        ]
        case .longevity: return [
            "life":1.0,"lifespan":1.0,"longev":1.0,"longevity":1.0,"expectancy":1.0,
            "years":0.7,"live":0.9,"living":0.7,"age":0.6,"die":0.8,"death":0.8,
            "mortality":0.9,"survive":0.7,"health":0.3,"long":0.4
        ]
        case .stress: return [
            "stress":1.0,"stres":1.0,
            "anxiety":1.0,"anxious":1.0,"worry":0.8,"worried":0.8,
            "cortisol":0.9,"mood":0.7,"mental":0.7,"depress":0.8,"overwhelm":0.8,
            "burnout":0.9,"tense":0.7,"panic":0.8,"calm":0.5,
            "freak":0.6,"spiral":0.6,"meltdown":0.6,"cope":0.6,"coping":0.6
        ]
        case .strength: return [
            "strength":1.0,"muscle":1.0,"muscular":1.0,"lift":0.8,"weight":0.4,
            "resistance":0.9,"strong":0.7,"sarcopenia":1.0,"grip":0.8,
            "deadlift":0.9,"squat":0.9,"bench":0.8,"pushup":0.8,"pullup":0.8,
            "tone":0.6,"toned":0.6,"bulk":0.6
        ]
        case .hydration: return [
            "water":1.0,"hydrate":1.0,"hydration":1.0,"drink":0.8,"thirst":0.9,
            "dehydrat":1.0,"fluid":0.7,"ml":0.4
        ]
        case .aging: return [
            "aging":1.0,"older":0.8,"old":0.6,"young":0.5,"biological":0.7,"cellular":0.6,
            "telomere":0.9,"age":0.6
        ]
        case .bloodSugar: return [
            "glucose":1.0,"sugar":0.9,"a1c":1.0,"insulin":0.8,"blood":0.3,"hypoglyc":1.0,
            "hyperglyc":1.0
        ]
        case .cholesterol: return [
            "cholesterol":1.0,"ldl":1.0,"hdl":1.0,"triglyceride":1.0,"lipid":0.9,
            "statin":0.8
        ]
        case .smoking: return [
            "smoke":1.0,"smoking":1.0,"smok":1.0,
            "cigarette":1.0,"nicotine":1.0,"tobacco":1.0,
            "vape":0.9,"vaping":0.9,"vap":0.9
        ]
        case .alcohol: return [
            "alcohol":1.0,"drinking":0.7,"beer":0.9,"wine":0.9,"liquor":0.9,
            "drunk":0.8,"hangover":0.9,"sober":0.7,"sobriety":0.7
        ]
        case .medication: return [
            "medication":1.0,"medicine":1.0,"drug":0.8,"pill":0.8,"prescription":1.0,
            "dose":0.8,"dosage":0.9,"interact":0.8,
            "statin":0.7,"metformin":0.9,"aspirin":0.7,"ibuprofen":0.7,
            "supplement":0.6,"vitamin":0.5,"med":0.7,
            "side":0.4,"effect":0.4
        ]
        case .pain: return [
            "pain":1.0,"hurt":0.9,"ache":0.9,"sore":0.8,"cramp":0.8,"sharp":0.5,
            "throb":0.7,"stiff":0.7,"tender":0.6,"inflammation":0.7,"inflam":0.7,
            "joint":0.7,"back":0.5,"knee":0.6,"shoulder":0.5,"headache":0.9,
            "migraine":1.0,"migraines":1.0
        ]
        case .mentalHealth: return [
            "depression":1.0,"depressed":1.0,"depress":1.0,
            "anxiety":0.9,"anxious":0.9,"anxiou":0.9,
            "therapy":0.9,"therapist":0.9,"counseling":0.9,"mental":0.7,
            "sad":0.7,"hopeless":0.8,"lonely":0.7,"isolation":0.7,
            "motivation":0.6,"unmotivated":0.7,"fog":0.6,
            "focus":0.5,"concentrate":0.5,"adhd":0.8,"ocd":0.8
        ]
        }
    }
}

// =====================================================================
// MARK: - Finding (structured clinical observation)
// =====================================================================

struct Finding {
    enum Severity: Int { case normal = 0, notable = 1, concerning = 2, severe = 3 }
    let concept: HealthConcept
    let severity: Severity
    let headline: String
    let evidence: String?
    let mechanism: String?
    let lever: String?
}

// =====================================================================
// MARK: - Inference Engine (applies clinical rules to real user data)
// =====================================================================

@MainActor
struct InferenceEngine {
    let profile: UserProfile
    let metrics: [HealthMetric]
    let meals: [Meal]

    private func latest(_ type: MetricType) -> Double? {
        metrics.filter { $0.type == type }
               .sorted { $0.recordedAt > $1.recordedAt }
               .first?.value
    }

    func snapshotSummary() -> String {
        var parts: [String] = []
        parts.append("BMI \(String(format: "%.1f", profile.bmi)) (\(profile.bmiCategory.rawValue.lowercased()))")
        parts.append("sleep \(String(format: "%.1f", profile.sleepHoursPerNight))h/night")
        if let steps = latest(.steps) { parts.append("\(Int(steps)) steps recently") }
        if let rhr = latest(.restingHeartRate) { parts.append("RHR \(Int(rhr))") }
        return parts.joined(separator: ", ") + "."
    }

    func findings(for concept: HealthConcept) -> [Finding] {
        switch concept {
        case .sleep: return sleepFindings()
        case .weight: return weightFindings()
        case .cardiovascular: return cardioFindings()
        case .bloodPressure: return bpFindings()
        case .activity: return activityFindings()
        case .nutrition: return nutritionFindings()
        case .metabolism, .bloodSugar: return metabolicFindings()
        case .longevity: return longevityFindings()
        case .stress: return stressFindings()
        case .strength: return strengthFindings()
        case .hydration: return hydrationFindings()
        case .aging: return agingFindings()
        case .cholesterol: return cholesterolFindings()
        case .smoking: return smokingFindings()
        case .alcohol: return alcoholFindings()
        case .medication: return medicationFindings()
        case .pain: return painFindings()
        case .mentalHealth: return mentalHealthFindings()
        }
    }

    // MARK: Sleep

    private func sleepFindings() -> [Finding] {
        let h = profile.sleepHoursPerNight
        var out: [Finding] = []

        if h < 6 {
            out.append(Finding(
                concept: .sleep, severity: .severe,
                headline: "You're running on \(String(format: "%.1f", h)) hours of sleep per night. That's in the severe deprivation range.",
                evidence: "Adults averaging under 6 hours show a 20-32% higher incidence of hypertension and a 48% higher risk of cardiovascular disease versus 7-8 hour sleepers.",
                mechanism: "Short sleep drives sympathetic overactivity, elevated cortisol, and impaired glucose tolerance, all of which compound over years.",
                lever: "The single biggest lever here is protecting a fixed wake time (even on weekends) and dropping caffeine after 2pm."))
        } else if h < 7 {
            out.append(Finding(
                concept: .sleep, severity: .concerning,
                headline: "Your \(String(format: "%.1f", h))-hour average is below the 7-9 hour band linked to the best health outcomes.",
                evidence: nil,
                mechanism: "Even a one-hour deficit over weeks measurably reduces insulin sensitivity and raises inflammatory markers like CRP.",
                lever: "Pushing bedtime 30 minutes earlier would be the cleanest intervention."))
        } else if h <= 9 {
            out.append(Finding(
                concept: .sleep, severity: .normal,
                headline: "Your \(String(format: "%.1f", h))-hour nightly average sits in the optimal band for adult metabolic and cognitive health.",
                evidence: nil,
                mechanism: "7-9 hours is where REM consolidation, memory encoding, and growth hormone pulses all stay intact.",
                lever: "Consistency is worth as much as duration. Keep bed and wake times within a 30-minute window."))
        } else {
            out.append(Finding(
                concept: .sleep, severity: .notable,
                headline: "You're averaging \(String(format: "%.1f", h)) hours, above the typical optimal window.",
                evidence: nil,
                mechanism: "Habitual oversleep past 9 hours has been associated with elevated all-cause mortality in cohort studies, though the relationship is often mediated by underlying depression or sleep fragmentation.",
                lever: "If you still feel unrested, the issue is likely sleep quality, not quantity."))
        }

        if h < 7, profile.bmi >= 25 {
            out.append(Finding(
                concept: .sleep, severity: .concerning,
                headline: "Your sleep deficit is almost certainly amplifying your weight trajectory.",
                evidence: "Each hour of sleep lost is associated with roughly a 0.35 kg/m\u{00B2} rise in BMI over a decade.",
                mechanism: "Short sleep suppresses leptin and elevates ghrelin, pushing appetite for calorie-dense foods the next day.",
                lever: nil))
        }
        return out
    }

    // MARK: Weight

    private func weightFindings() -> [Finding] {
        var out: [Finding] = []
        let bmi = profile.bmi
        let cat = profile.bmiCategory

        let headlineBase = "Your BMI is \(String(format: "%.1f", bmi)), putting you in the \(cat.rawValue.lowercased()) range."

        switch cat {
        case .underweight:
            out.append(Finding(
                concept: .weight, severity: .notable,
                headline: headlineBase,
                evidence: nil,
                mechanism: "BMI under 18.5 correlates with reduced muscle mass, lower bone density, and impaired immune response. These risks compound with age.",
                lever: "Prioritize protein (1.6-2.0 g/kg) and resistance training rather than just more calories."))
        case .normal:
            out.append(Finding(
                concept: .weight, severity: .normal,
                headline: headlineBase,
                evidence: nil,
                mechanism: "A BMI of 18.5-24.9 is associated with the lowest all-cause mortality for most adults, though BMI alone misses body composition.",
                lever: "Focus on maintaining lean mass. It becomes harder to defend after age 40."))
        case .overweight:
            out.append(Finding(
                concept: .weight, severity: .concerning,
                headline: headlineBase,
                evidence: "Overweight status raises relative risk for type 2 diabetes roughly 2-fold and cardiovascular events 1.3-fold compared to normal BMI.",
                mechanism: "Excess visceral adiposity drives chronic low-grade inflammation and insulin resistance, both upstream of most chronic disease.",
                lever: "A 5-10% reduction in body weight is where clinically significant metabolic improvements start."))
        case .obese:
            out.append(Finding(
                concept: .weight, severity: .severe,
                headline: headlineBase,
                evidence: "Obesity (BMI 30+) is associated with a 6-14 year reduction in life expectancy depending on class and age of onset.",
                mechanism: "Sustained adiposity drives hypertension, dyslipidemia, insulin resistance, and systemic inflammation in a reinforcing loop.",
                lever: "Even modest loss (5% of body weight) meaningfully lowers blood pressure, A1C, and liver fat."))
        }
        return out
    }

    // MARK: Cardiovascular

    private func cardioFindings() -> [Finding] {
        var out: [Finding] = []
        if let rhr = latest(.restingHeartRate) {
            if rhr < 55 {
                out.append(Finding(
                    concept: .cardiovascular, severity: .normal,
                    headline: "Your resting heart rate of \(Int(rhr)) bpm is in athletic territory.",
                    evidence: nil,
                    mechanism: "Low RHR reflects high parasympathetic tone and efficient stroke volume, typical of trained endurance athletes.",
                    lever: nil))
            } else if rhr < 70 {
                out.append(Finding(
                    concept: .cardiovascular, severity: .normal,
                    headline: "Resting heart rate of \(Int(rhr)) bpm is in the healthy range.",
                    evidence: nil,
                    mechanism: "RHR under 70 generally indicates good cardiovascular fitness.",
                    lever: "Aerobic training is the single most effective way to push it lower."))
            } else if rhr < 85 {
                out.append(Finding(
                    concept: .cardiovascular, severity: .notable,
                    headline: "Your resting heart rate of \(Int(rhr)) bpm is on the higher side of normal.",
                    evidence: "Each 10-bpm rise in RHR is associated with a roughly 10-20% increase in cardiovascular mortality.",
                    mechanism: "A higher RHR usually reflects lower aerobic capacity or elevated sympathetic tone from stress or poor sleep.",
                    lever: "Three 30-minute zone-2 sessions per week will typically drop RHR by 5-10 bpm over 8 weeks."))
            } else {
                out.append(Finding(
                    concept: .cardiovascular, severity: .concerning,
                    headline: "Your resting heart rate of \(Int(rhr)) bpm is elevated.",
                    evidence: nil,
                    mechanism: "Sustained RHR above 85 is an independent risk factor for CV events, often reflecting deconditioning, dehydration, anemia, or hyperthyroidism.",
                    lever: "Worth a basic CBC and TSH check alongside a gradual aerobic program."))
            }
        }

        if profile.smokingStatus == .current {
            out.append(Finding(
                concept: .cardiovascular, severity: .severe,
                headline: "Smoking is by far the dominant modifiable cardiovascular risk in your profile.",
                evidence: "Current smoking roughly doubles CHD risk and quadruples stroke risk versus never-smokers.",
                mechanism: "Nicotine constricts coronary arteries, carbon monoxide impairs oxygen delivery, and oxidative damage accelerates atherosclerosis.",
                lever: "Quitting reclaims about half of the excess CV risk within one year."))
        }
        return out
    }

    // MARK: Blood Pressure

    private func bpFindings() -> [Finding] {
        var out: [Finding] = []
        let sys = latest(.bloodPressureSystolic)
        let dia = latest(.bloodPressureDiastolic)
        guard let sys else {
            out.append(Finding(
                concept: .bloodPressure, severity: .notable,
                headline: "I don't have any blood pressure readings for you yet.",
                evidence: nil,
                mechanism: "BP is probably the most predictive modifiable metric for cardiovascular events. Worth logging.",
                lever: "Home readings twice weekly give a far better picture than sporadic clinic measurements."))
            return out
        }

        guard let d = dia else {
            let label: (String, Finding.Severity, String)
            if sys >= 180 {
                label = ("crisis-range systolic", .severe,
                         "A systolic at or above 180 warrants same-day medical attention. Log a diastolic reading for the full picture.")
            } else if sys >= 140 {
                label = ("stage 2 range", .severe,
                         "Stage 2 hypertension systolic. Combined lifestyle and pharmacologic treatment is typically indicated.")
            } else if sys >= 130 {
                label = ("stage 1 range", .concerning,
                         "Stage 1 hypertension systolic. DASH diet, sodium restriction, and regular aerobic activity can each move BP independently.")
            } else if sys >= 120 {
                label = ("elevated systolic", .notable,
                         "Elevated (but not hypertensive) systolic. Log diastolic readings to track the full BP picture.")
            } else {
                label = ("normal systolic", .normal,
                         "Normal systolic BP, a strong protective factor.")
            }
            out.append(Finding(
                concept: .bloodPressure, severity: label.1,
                headline: "Your most recent systolic BP is \(Int(sys)) mmHg (\(label.0)). No diastolic reading logged yet.",
                evidence: label.2,
                mechanism: "BP reflects systemic vascular load; chronic elevation damages arterial endothelium and left ventricle.",
                lever: label.1 == .normal ? nil : "Sodium under 2300 mg/day, regular aerobic work, and weight reduction each move BP independently."))
            return out
        }

        let label: (String, Finding.Severity, String)

        if sys >= 180 || d >= 120 {
            label = ("crisis", .severe,
                     "A reading at or above 180/120 is a hypertensive crisis. If sustained, this warrants same-day medical attention.")
        } else if sys >= 140 || d >= 90 {
            label = ("stage 2 hypertension", .severe,
                     "Stage 2 hypertension roughly triples cardiovascular event risk compared to normal BP. Combined lifestyle and pharmacologic treatment is typically indicated.")
        } else if sys >= 130 || d >= 80 {
            label = ("stage 1 hypertension", .concerning,
                     "Stage 1 hypertension roughly doubles CV event risk. 5-10 mmHg reductions from DASH diet, sodium restriction, and regular aerobic activity are achievable.")
        } else if sys >= 120 {
            label = ("elevated", .notable,
                     "Elevated (but not hypertensive) BP is a signal to act early. Lifestyle interventions here can prevent progression.")
        } else {
            label = ("normal", .normal,
                     "Normal BP, a strong protective factor. Keep cardiovascular conditioning up to maintain it.")
        }

        out.append(Finding(
            concept: .bloodPressure, severity: label.1,
            headline: "Your most recent BP is \(Int(sys))/\(Int(d)) (\(label.0)).",
            evidence: label.2,
            mechanism: "BP reflects systemic vascular load; chronic elevation damages arterial endothelium and left ventricle.",
            lever: label.1 == .normal ? nil : "Sodium under 2300 mg/day, regular aerobic work, and weight reduction each move BP independently."))

        return out
    }

    // MARK: Activity

    private func activityFindings() -> [Finding] {
        var out: [Finding] = []
        if let steps = latest(.steps) {
            if steps >= 10_000 {
                out.append(Finding(concept: .activity, severity: .normal,
                    headline: "Your \(Int(steps)) recent steps are well above the longevity sweet spot.",
                    evidence: "Mortality benefit from steps plateaus around 8,000-10,000 for adults under 60 and around 6,000-8,000 for older adults.",
                    mechanism: "Daily ambulation is one of the strongest independent predictors of all-cause mortality reduction.",
                    lever: nil))
            } else if steps >= 7_000 {
                out.append(Finding(concept: .activity, severity: .normal,
                    headline: "At around \(Int(steps)) steps you're in the evidence-supported protective range.",
                    evidence: "Each additional 1,000 steps up to roughly 10,000 correlates with a 6-15% lower all-cause mortality.",
                    mechanism: nil,
                    lever: "Small tweak: add a 15-minute post-meal walk. The glucose-flattening effect is disproportionate."))
            } else if steps >= 4_000 {
                out.append(Finding(concept: .activity, severity: .notable,
                    headline: "You're logging \(Int(steps)) steps, below the zone where mortality risk drops most sharply.",
                    evidence: "The largest relative gain in longevity comes from moving from roughly 4,000 to 7,000 steps, not from 8,000 to 12,000.",
                    mechanism: nil,
                    lever: "Even adding one 30-minute walk daily would move you past that threshold."))
            } else {
                out.append(Finding(concept: .activity, severity: .concerning,
                    headline: "At \(Int(steps)) steps recently, you're in a sedentary range.",
                    evidence: "Under 4,000 steps/day is associated with a measurable increase in all-cause mortality independent of formal exercise.",
                    mechanism: "Long sedentary time impairs lipid metabolism and insulin signaling, even if you exercise briefly.",
                    lever: "Habit stacking short walks after meals is usually the most sustainable starting point."))
            }
        }

        if profile.activityLevel == .sedentary {
            out.append(Finding(concept: .activity, severity: .concerning,
                headline: "Your self-reported activity level is sedentary, which is one of the strongest modifiable levers in your profile.",
                evidence: nil, mechanism: nil,
                lever: "The biggest jump in benefit is from 'nothing' to 'anything consistent'. A brisk 20-minute walk, 4x/week, moves the needle."))
        }
        return out
    }

    // MARK: Nutrition

    private func nutritionFindings() -> [Finding] {
        var out: [Finding] = []
        let today = meals.filter { Calendar.current.isDateInToday($0.loggedAt) }
        guard !today.isEmpty else {
            out.append(Finding(concept: .nutrition, severity: .notable,
                headline: "You haven't logged any meals today yet.",
                evidence: nil, mechanism: nil,
                lever: "Logging just once a day builds a usable nutrition signal. I can reason about macros, fiber, and timing once the data's there."))
            return out
        }

        let cal = today.reduce(0.0) { $0 + $1.totalCalories }
        let prot = today.reduce(0.0) { $0 + $1.totalProtein }
        let carb = today.reduce(0.0) { $0 + $1.totalCarbs }
        let fat  = today.reduce(0.0) { $0 + $1.totalFat }
        let fib  = today.reduce(0.0) { $0 + $1.totalFiber }
        let proteinTarget = profile.weightKg * 1.2

        out.append(Finding(concept: .nutrition, severity: .normal,
            headline: "Today so far: \(Int(cal)) kcal, \(Int(prot))g protein, \(Int(carb))g carbs, \(Int(fat))g fat.",
            evidence: nil, mechanism: nil, lever: nil))

        if prot < proteinTarget * 0.7 {
            out.append(Finding(concept: .nutrition, severity: .concerning,
                headline: "Protein is running light. You're at \(Int(prot))g against a target of roughly \(Int(proteinTarget))g.",
                evidence: "Adults who hit 1.2+ g/kg of protein preserve significantly more lean mass, especially past age 50.",
                mechanism: "Low protein blunts muscle protein synthesis and drives sarcopenia over time.",
                lever: "An extra 25-40g at breakfast is the easiest fix. Most people load protein at dinner when it's least useful."))
        } else if prot >= proteinTarget {
            out.append(Finding(concept: .nutrition, severity: .normal,
                headline: "Protein intake looks solid at \(Int(prot))g.",
                evidence: nil, mechanism: nil, lever: nil))
        }

        if fib < 20 {
            out.append(Finding(concept: .nutrition, severity: .notable,
                headline: "Fiber at \(Int(fib))g is below the 25-35g range linked to best cardiometabolic outcomes.",
                evidence: "Each 10g/day of fiber associates with a 10-15% reduction in cardiovascular mortality.",
                mechanism: "Fiber feeds gut microbes that produce short-chain fatty acids, lowering systemic inflammation and LDL.",
                lever: "Beans, berries, and oats cost almost nothing but move this number fast."))
        }

        return out
    }

    // MARK: Metabolism / Blood Sugar

    private func metabolicFindings() -> [Finding] {
        var out: [Finding] = []
        if let glu = latest(.bloodGlucose) {
            if glu >= 126 {
                out.append(Finding(concept: .metabolism, severity: .severe,
                    headline: "Fasting glucose of \(Int(glu)) mg/dL meets the ADA threshold for diabetes if fasted.",
                    evidence: nil,
                    mechanism: "Chronic hyperglycemia damages capillaries and nerve tissue, which is why diabetes concentrates complications in the eyes, kidneys, and feet.",
                    lever: "Confirm with a second fasted reading or an A1C and bring it to a physician."))
            } else if glu >= 100 {
                out.append(Finding(concept: .metabolism, severity: .concerning,
                    headline: "Fasting glucose of \(Int(glu)) mg/dL is in the prediabetic range.",
                    evidence: "Roughly 70% of prediabetics progress to type 2 diabetes within a decade without intervention.",
                    mechanism: "Insulin resistance precedes overt hyperglycemia by years. This is the window where lifestyle change is most effective.",
                    lever: "The Diabetes Prevention Program showed roughly 58% risk reduction from 7% body weight loss plus 150 min/week of activity."))
            } else {
                out.append(Finding(concept: .metabolism, severity: .normal,
                    headline: "Glucose of \(Int(glu)) mg/dL is in the healthy fasting range.",
                    evidence: nil, mechanism: nil, lever: nil))
            }
        }
        if profile.bmi >= 30 {
            out.append(Finding(concept: .metabolism, severity: .concerning,
                headline: "Your BMI in the obese range substantially amplifies metabolic risk even if glucose is currently normal.",
                evidence: nil,
                mechanism: "Visceral fat drives hepatic insulin resistance, usually the first domino before blood sugar starts rising.",
                lever: nil))
        }
        return out
    }

    // MARK: Longevity

    private func longevityFindings() -> [Finding] {
        var levers: [String] = []
        if profile.smokingStatus == .current { levers.append("quitting smoking (adds roughly 10 years)") }
        if profile.vapes && profile.smokingStatus == .never { levers.append("quitting vaping (adds 3-5 years via reduced vascular inflammation)") }
        if profile.bmi >= 30 { levers.append("reducing BMI below 30 (adds 3-5 years)") }
        if profile.activityLevel == .sedentary { levers.append("moving from sedentary to active (adds 3-4 years)") }
        if profile.sleepHoursPerNight < 7 { levers.append("getting 7+ hours of sleep (adds 2-3 years)") }
        if profile.alcoholFrequency == .daily || profile.alcoholBingeFrequency == .weekly { levers.append("reducing alcohol (adds 1-2 years)") }
        if profile.vegetableServingsPerDay < 3 { levers.append("eating 5+ servings of vegetables daily (adds 1-2 years via reduced CVD risk)") }
        if profile.processedFoodFrequency == .mostly || profile.processedFoodFrequency == .often { levers.append("cutting ultra-processed foods to less than daily (adds 1-3 years via metabolic improvement)") }

        if levers.isEmpty {
            return [Finding(concept: .longevity, severity: .normal,
                headline: "Your major longevity levers (smoking, weight, activity, sleep, alcohol) are all in protective ranges.",
                evidence: "The AHA's Life's Essential 8 framework identifies these as the dominant modifiable drivers of lifespan.",
                mechanism: nil,
                lever: "Marginal gains from here come from strength, stress management, and cardiometabolic monitoring.")]
        }

        return [Finding(concept: .longevity, severity: .notable,
            headline: "The highest-leverage moves for your projected lifespan: \(levers.joined(separator: "; ")).",
            evidence: "These levers come from large prospective cohorts: CARDIA, Framingham, and the UK Biobank primarily.",
            mechanism: "Each acts through a distinct pathway (vascular, metabolic, inflammatory), so the effects stack rather than overlap.",
            lever: nil)]
    }

    // MARK: Stress

    private func stressFindings() -> [Finding] {
        var out: [Finding] = []
        let poorSleep = profile.sleepHoursPerNight < 7
        let highRHR = (latest(.restingHeartRate) ?? 0) >= 80

        if poorSleep && highRHR {
            out.append(Finding(concept: .stress, severity: .concerning,
                headline: "Short sleep combined with an elevated resting heart rate is a classic sympathetic-dominance signature.",
                evidence: nil,
                mechanism: "Chronic stress keeps the sympathetic nervous system elevated, which compresses sleep depth and raises daytime heart rate, each reinforcing the other.",
                lever: "Two interventions with the most evidence: 10 minutes of daily mindfulness and consistent bed/wake timing."))
        } else if poorSleep {
            out.append(Finding(concept: .stress, severity: .notable,
                headline: "Your short sleep could be both a symptom of stress and a cause of it.",
                evidence: nil,
                mechanism: "Sleep deprivation raises cortisol and lowers emotional regulation threshold, making stressors feel larger than they are.",
                lever: "Before adding anything new, fixing sleep often resolves much of the perceived stress."))
        } else if highRHR {
            out.append(Finding(concept: .stress, severity: .notable,
                headline: "Your elevated resting heart rate may reflect chronic sympathetic activation from stress.",
                evidence: nil,
                mechanism: "Sustained elevated RHR without a fitness explanation often points to stress, dehydration, or poor recovery.",
                lever: "Track HRV if available. It's a more sensitive stress marker than RHR alone."))
        } else {
            out.append(Finding(concept: .stress, severity: .normal,
                headline: "I don't see strong physiological stress markers in your data.",
                evidence: nil,
                mechanism: "Stress is most visible in elevated RHR, poor HRV, and sleep fragmentation. None dominate your profile right now.",
                lever: "If you're subjectively stressed, HRV tracking will catch it earlier than most other metrics."))
        }
        return out
    }

    // MARK: Strength / Hydration / Aging / Cholesterol / Smoking / Alcohol

    private func strengthFindings() -> [Finding] {
        var out: [Finding] = []
        out.append(Finding(concept: .strength, severity: .notable,
            headline: "I don't track resistance training directly yet. In your profile, strength work is probably the single most under-weighted lever.",
            evidence: "Grip strength correlates with all-cause mortality roughly as strongly as smoking status.",
            mechanism: "Muscle acts as a metabolic organ, clearing glucose and secreting myokines that lower systemic inflammation.",
            lever: "Two 30-minute full-body sessions per week is the minimum effective dose."))

        if profile.age >= 50 {
            out.append(Finding(concept: .strength, severity: .concerning,
                headline: "After 50, muscle mass declines roughly 1-2% per year without resistance training.",
                evidence: "Sarcopenia is an independent predictor of falls, fractures, and loss of independence.",
                mechanism: nil,
                lever: "Compound lifts (squat, deadlift, row, press) give the most return per minute of training time."))
        }
        return out
    }

    private func hydrationFindings() -> [Finding] {
        let target = profile.weightKg * 30
        if let water = latest(.waterIntake) {
            if water < target * 0.7 {
                return [Finding(concept: .hydration, severity: .notable,
                    headline: "Recent water intake of \(Int(water)) ml is below the \(Int(target)) ml rough target for your body weight.",
                    evidence: "Mild dehydration measurably raises RHR, reduces cognitive performance, and impairs thermoregulation.",
                    mechanism: nil, lever: nil)]
            }
            return [Finding(concept: .hydration, severity: .normal,
                headline: "Hydration at \(Int(water)) ml looks adequate for your body weight.",
                evidence: nil, mechanism: nil, lever: nil)]
        }
        return [Finding(concept: .hydration, severity: .notable,
            headline: "I don't have recent water intake logged.",
            evidence: nil, mechanism: nil,
            lever: "Logging water gets sparse signal; body weight (kg) x 30 ml is a reasonable daily target.")]
    }

    private func agingFindings() -> [Finding] {
        var out: [Finding] = []
        out.append(Finding(concept: .aging, severity: .normal,
            headline: "Biological aging isn't a single number. The dominant modifiable drivers in your profile are sleep, cardiometabolic health, and muscle mass.",
            evidence: nil,
            mechanism: "Aging at the cellular level is largely about cumulative oxidative damage, inflammation, and mitochondrial dysfunction, all downstream of the same levers.",
            lever: nil))

        if profile.age >= 40 {
            out.append(Finding(concept: .aging, severity: .notable,
                headline: "After 40, the rate of sarcopenia, bone density loss, and metabolic decline accelerates unless actively countered.",
                evidence: nil,
                mechanism: "Growth hormone and testosterone decline naturally, but resistance training and adequate protein significantly blunt the trajectory.",
                lever: "The three highest-ROI interventions for healthy aging: resistance training, sleep consistency, and adequate protein."))
        }
        return out
    }

    private func cholesterolFindings() -> [Finding] {
        if let ldl = latest(.cholesterolLDL) {
            if ldl >= 160 {
                return [Finding(concept: .cholesterol, severity: .severe,
                    headline: "LDL of \(Int(ldl)) mg/dL is high.",
                    evidence: "Per AHA/ACC guidelines, LDL above 160 in adults with other risk factors typically warrants both lifestyle and pharmacologic intervention.",
                    mechanism: "LDL particles that cross the endothelium and oxidize are what build atherosclerotic plaque.",
                    lever: "Soluble fiber, reduced saturated fat, and weight reduction are the most evidence-supported non-drug moves.")]
            } else if ldl >= 130 {
                return [Finding(concept: .cholesterol, severity: .concerning,
                    headline: "LDL of \(Int(ldl)) mg/dL is borderline-high.",
                    evidence: nil, mechanism: nil,
                    lever: "Swap refined carbs for fiber, and replace saturated fat with mono/polyunsaturated sources.")]
            } else {
                return [Finding(concept: .cholesterol, severity: .normal,
                    headline: "LDL of \(Int(ldl)) mg/dL is in a healthy range.",
                    evidence: nil, mechanism: nil, lever: nil)]
            }
        }
        return [Finding(concept: .cholesterol, severity: .notable,
            headline: "No recent cholesterol panel in your data.",
            evidence: nil, mechanism: nil,
            lever: "Upload a blood test in the You tab and I'll incorporate the full lipid panel.")]
    }

    private func smokingFindings() -> [Finding] {
        switch profile.smokingStatus {
        case .current:
            return [Finding(concept: .smoking, severity: .severe,
                headline: "Active smoking is the highest-impact single change available to your profile.",
                evidence: "Smoking cessation before age 40 recovers roughly 9-10 years of life expectancy.",
                mechanism: "Nicotine acutely raises BP and HR; combustion products cause endothelial damage, oxidative stress, and carcinogenesis.",
                lever: "Pharmacologic support (varenicline, NRT) roughly doubles quit success rates compared to willpower alone.")]
        case .former:
            return [Finding(concept: .smoking, severity: .normal,
                headline: "Former smoker. The risk decay is real. Around 15 years post-quit, CV risk approaches never-smoker baseline.",
                evidence: nil, mechanism: nil, lever: nil)]
        case .never:
            return [Finding(concept: .smoking, severity: .normal,
                headline: "Never smoking is worth more than almost any other single choice in your profile.",
                evidence: nil, mechanism: nil, lever: nil)]
        }
    }

    private func alcoholFindings() -> [Finding] {
        switch profile.alcoholFrequency {
        case .never, .rarely:
            return [Finding(concept: .alcohol, severity: .normal,
                headline: "Low alcohol intake. Protective, especially for cancer risk.",
                evidence: "Recent meta-analyses suggest no safe lower threshold for alcohol-related cancer risk.",
                mechanism: nil, lever: nil)]
        case .monthly, .weekly, .several:
            return [Finding(concept: .alcohol, severity: .notable,
                headline: "Moderate alcohol intake carries some cardiovascular 'U-shape' benefit in older literature, but newer mendelian randomization studies suggest the benefit is largely confounded.",
                evidence: nil, mechanism: nil,
                lever: "Keeping it to fewer than 7 drinks/week limits the dose-dependent risk for breast, colon, and liver cancer.")]
        case .daily:
            return [Finding(concept: .alcohol, severity: .concerning,
                headline: "Daily alcohol is associated with disproportionately elevated risk, especially for liver disease, hypertension, and several cancers.",
                evidence: nil,
                mechanism: "Daily exposure gives the liver no recovery window, and ethanol is a class 1 carcinogen.",
                lever: "Two alcohol-free days per week measurably lowers liver enzyme levels.")]
        }
    }

    // MARK: Medication

    private func medicationFindings() -> [Finding] {
        if profile.medications.isEmpty {
            return [Finding(concept: .medication, severity: .normal,
                headline: "No medications listed in your profile.",
                evidence: nil, mechanism: nil,
                lever: "If you take any regular medications, adding them to your profile helps me flag relevant interactions with your metrics.")]
        }

        var out: [Finding] = []
        let meds = profile.medications.map { $0.lowercased() }

        out.append(Finding(concept: .medication, severity: .normal,
            headline: "You have \(profile.medications.count) medication(s) listed: \(profile.medications.joined(separator: ", ")).",
            evidence: nil, mechanism: nil,
            lever: "I can't replace pharmacist advice, but I can flag when your metrics (BP, glucose, heart rate) move in directions that your medications should be addressing."))

        if meds.contains(where: { $0.contains("statin") }) {
            out.append(Finding(concept: .medication, severity: .notable,
                headline: "On a statin, your LDL target is typically under 100 mg/dL (under 70 if high-risk). Upload a lipid panel and I'll check.",
                evidence: nil, mechanism: nil, lever: nil))
        }

        if meds.contains(where: { $0.contains("metformin") }) {
            out.append(Finding(concept: .medication, severity: .notable,
                headline: "Metformin works best alongside diet and activity changes. Log meals and steps so I can track how your glucose responds to the full picture.",
                evidence: nil, mechanism: nil, lever: nil))
        }

        return out
    }

    // MARK: Pain

    private func painFindings() -> [Finding] {
        [Finding(concept: .pain, severity: .notable,
            headline: "I can't diagnose or treat pain directly. What I can do is look at how your activity, sleep, and stress data might relate to what you're experiencing.",
            evidence: "Chronic pain and poor sleep have a bidirectional relationship: each makes the other worse.",
            mechanism: "Inflammation, deconditioning, and central sensitization are common threads in persistent pain syndromes.",
            lever: "If this is new or worsening, it's worth a clinical evaluation. For chronic pain, consistent low-intensity movement often helps more than rest.")]
    }

    // MARK: Mental Health

    private func mentalHealthFindings() -> [Finding] {
        var out: [Finding] = []

        out.append(Finding(concept: .mentalHealth, severity: .notable,
            headline: "Mental health is deeply connected to the physical metrics I track. Sleep, activity, and nutrition all have strong evidence for mood regulation.",
            evidence: "Exercise has effect sizes comparable to SSRIs for mild-to-moderate depression in meta-analyses.",
            mechanism: "Physical activity increases BDNF, regulates cortisol, and improves sleep architecture, all of which feed back into mood.",
            lever: "I'm not a therapist, but I can help you stay on top of the physical levers that support mental health."))

        if profile.sleepHoursPerNight < 7 {
            out.append(Finding(concept: .mentalHealth, severity: .concerning,
                headline: "Your short sleep is almost certainly affecting your mental state. Sleep deprivation reliably worsens mood, anxiety, and emotional regulation.",
                evidence: nil, mechanism: nil,
                lever: "Fixing sleep is often the single highest-ROI intervention for mental health."))
        }

        if profile.activityLevel == .sedentary {
            out.append(Finding(concept: .mentalHealth, severity: .notable,
                headline: "Sedentary behavior is independently associated with higher rates of depression and anxiety.",
                evidence: nil, mechanism: nil,
                lever: "Even a 20-minute walk has measurable acute effects on mood. The bar is low and the return is high."))
        }

        return out
    }
}

// =====================================================================
// MARK: - Response Composer (intent-aware, tone-adapted prose)
// =====================================================================

@MainActor
enum ResponseComposer {

    // Varied openers grouped by intent
    private static let infoOpeners = [
        "Looking at your data, ",
        "Based on what's logged, ",
        "From your profile, ",
        "Here's what I'm seeing: ",
        "Running through your numbers, ",
        "Pulling up your data, ",
        "From what I have, ",
    ]

    private static let worryOpeners = [
        "I hear you. Let me look at what the data actually says. ",
        "Let's look at this together. ",
        "I understand the concern. Here's what your numbers show: ",
        "Let me ground this in your actual data. ",
    ]

    private static let actionOpeners = [
        "Here's what I'd focus on: ",
        "The most actionable thing in your data right now: ",
        "Let me prioritize what matters most for you. ",
        "Here's where the biggest return is: ",
    ]

    private static let ventOpeners = [
        "That sounds rough. Let me see what the data says and whether there's something concrete to work with. ",
        "I hear you. Let's look at what we can actually move. ",
        "That's frustrating. Here's what I'm seeing in your numbers: ",
    ]

    private static let progressOpeners = [
        "Let me check your trajectory. ",
        "Looking at how things have moved: ",
        "Here's where you stand relative to before: ",
    ]

    private static let bridges = [
        " On top of that, ",
        " Related to that, ",
        " Worth connecting: ",
        " The follow-on is that ",
        " Also worth noting: ",
        " Another angle: ",
        " ",
    ]

    private static let closers = [
        " Happy to dig into any of these further.",
        " Ask about any of these if you want the mechanism in more depth.",
        " Let me know which of these you want to unpack.",
        " Want me to go deeper on any of this?",
        "",
    ]

    static func compose(
        findings: [Finding],
        concepts: [HealthConcept],
        profile: UserProfile,
        query: String,
        intent: UserIntent,
        isFollowUp: Bool,
        context: ConversationContext
    ) -> String {
        let rawFirst = profile.name.components(separatedBy: " ").first ?? profile.name
        let firstName = rawFirst.isEmpty ? "there" : rawFirst
        let ordered = findings.sorted { $0.severity.rawValue > $1.severity.rawValue }

        var parts: [String] = []

        // Intent-aware opener
        if isFollowUp {
            // Vary follow-up openers based on what was asked
            let followUpOpeners = [
                "Going deeper on that, \(firstName): ",
                "Expanding on that: ",
                "To break that down further: ",
                "Here's the longer story: ",
                "Zooming in: ",
            ]
            parts.append(pickDeterministic(followUpOpeners, seed: query.count + context.turnCount))
        } else {
            let openers: [String]
            switch intent {
            case .expressing_worry: openers = worryOpeners
            case .seeking_action: openers = actionOpeners
            case .venting: openers = ventOpeners
            case .checking_progress: openers = progressOpeners
            default: openers = infoOpeners
            }
            let opener = pickDeterministic(openers, seed: query.count + context.turnCount)
            // Personalize based on conversation depth
            if context.turnCount == 0 || query.count.isMultiple(of: 3) {
                parts.append("\(firstName), \(opener.prefix(1).lowercased() + opener.dropFirst())")
            } else {
                parts.append(opener)
            }
        }

        // Primary finding
        if let first = ordered.first {
            parts.append(first.headline)

            // For worry intent, lead with reassurance or honest concern
            if intent == .expressing_worry {
                if first.severity == .normal {
                    parts.append(" Your numbers look reassuring here.")
                }
                if let mech = first.mechanism {
                    parts.append(" " + mech)
                }
            } else {
                if let mech = first.mechanism {
                    parts.append(" " + mech)
                } else if let ev = first.evidence {
                    parts.append(" " + ev)
                }
            }

            // Include actionable lever - always for action-seekers; for worry, only
            // when the finding is concerning or worse (don't leave them without guidance)
            if let lever = first.lever {
                if intent == .expressing_worry {
                    if first.severity.rawValue >= Finding.Severity.concerning.rawValue {
                        parts.append(" " + lever)
                    }
                } else {
                    parts.append(" " + lever)
                }
            }
        }

        // Secondary findings
        for (i, finding) in ordered.dropFirst().prefix(2).enumerated() {
            let bridge = pickDeterministic(bridges, seed: query.count + i * 7 + context.turnCount)
            parts.append(bridge + finding.headline)
            if let mech = finding.mechanism ?? finding.evidence {
                parts.append(" " + mech)
            }
            if let lever = finding.lever {
                parts.append(" " + lever)
            }
        }

        // Closer - skip on follow-ups (they already had a chance to ask)
        if ordered.count > 1, !isFollowUp {
            parts.append(pickDeterministic(closers, seed: query.count + context.turnCount + 13))
        }

        return parts.joined()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func pickDeterministic<T>(_ options: [T], seed: Int) -> T {
        options[abs(seed) % options.count]
    }
}

// =====================================================================
// MARK: - Small Talk (expanded)
// =====================================================================

@MainActor
enum SmallTalk {
    static func handle(tokens: [String], rawQuery: String, profile: UserProfile, context: ConversationContext) -> String? {
        let rawFirst = profile.name.components(separatedBy: " ").first ?? profile.name
        let firstName = rawFirst.isEmpty ? "there" : rawFirst
        let set = Set(tokens)
        let lower = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Greetings
        if !set.intersection(["hi","hello","hey","yo","sup"]).isEmpty {
            if context.turnCount == 0 {
                return "Hey \(firstName). What do you want to look at today? Sleep, activity, nutrition, cardiovascular, longevity? Or just ask me anything about your data."
            } else {
                return "Still here, \(firstName). What else do you want to dig into?"
            }
        }

        // Thanks
        if !set.intersection(["thank","thanks","thx"]).isEmpty {
            let responses = [
                "Anytime.",
                "You got it.",
                "Happy to help. Let me know if anything else comes up.",
            ]
            return responses[abs(context.turnCount) % responses.count]
        }

        // Identity
        let asksIdentity = (lower.contains("who are you") || lower.contains("what are you") ||
                            lower.contains("what is pearl") || lower.contains("who is pearl") ||
                            (lower.contains("about") && lower.contains("pearl")))
        if asksIdentity {
            return "I'm Pearl, the reasoning layer inside AptoSwasthy. I run entirely on your device: no cloud, no external model. I read your health data and apply clinical rules to give you specific, personal answers. Nothing I say leaves your phone."
        }

        // Capability questions
        if lower.contains("what can you do") || lower.contains("what do you know") ||
           lower.contains("help me with") || lower == "help" {
            return "I can reason about sleep, weight, cardiovascular health, blood pressure, activity, nutrition, metabolism, stress, longevity, cholesterol, smoking, alcohol, and mental health. I work from your actual data, so the more you log, the more specific I can be. Just ask me anything."
        }

        // How am I doing (general)
        if lower.contains("how am i doing") || lower.contains("how's my health") ||
           lower.contains("give me a summary") || lower.contains("overall health") {
            let engine = InferenceEngine(profile: profile, metrics: context.lastMetrics ?? [], meals: [])
            return "\(firstName), here's a quick snapshot: \(engine.snapshotSummary()) Ask me about any specific area and I'll go deeper."
        }

        // Compliment / positive feedback
        if lower.contains("you're good") || lower.contains("that's helpful") ||
           lower.contains("nice") || lower.contains("cool") || lower.contains("awesome") ||
           lower.contains("great") || lower.contains("impressive") {
            return "Glad it's useful. What else do you want to look at?"
        }

        // Confusion
        if lower == "what" || lower == "what?" || lower == "huh" || lower == "huh?" {
            if let lastTopic = context.lastConcepts.first {
                return "We were looking at \(lastTopic.humanName). Want me to explain that differently, or move on to something else?"
            }
            return "Ask me about any aspect of your health: sleep, weight, heart, nutrition, activity, stress, longevity. I'll pull from your actual data."
        }

        return nil
    }
}

// =====================================================================
// MARK: - Conversation Context (deeper multi-turn memory)
// =====================================================================

final class ConversationContext {
    private(set) var lastConcepts: [HealthConcept] = []
    private(set) var lastFindings: [Finding] = []
    private(set) var lastIntent: UserIntent = .general
    private(set) var turnCount: Int = 0
    private(set) var history: [(query: String, concepts: [HealthConcept], intent: UserIntent)] = []
    var lastMetrics: [HealthMetric]?

    func reset() {
        lastConcepts = []
        lastFindings = []
        lastIntent = .general
        turnCount = 0
        history = []
    }

    func record(concepts: [HealthConcept], findings: [Finding], intent: UserIntent = .general) {
        lastConcepts = concepts
        lastFindings = findings
        lastIntent = intent
        turnCount += 1
    }

    func remember(query: String, response: String) {
        history.append((query: query, concepts: lastConcepts, intent: lastIntent))
        // Keep last 10 turns to prevent unbounded growth
        if history.count > 10 {
            history.removeFirst()
        }
    }

    // Check if a concept was discussed recently
    func recentlyDiscussed(_ concept: HealthConcept) -> Bool {
        history.suffix(3).contains { $0.concepts.contains(concept) }
    }

    // Get the dominant topic of the conversation so far
    var dominantTopic: HealthConcept? {
        var counts: [HealthConcept: Int] = [:]
        for turn in history {
            for concept in turn.concepts {
                counts[concept, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
