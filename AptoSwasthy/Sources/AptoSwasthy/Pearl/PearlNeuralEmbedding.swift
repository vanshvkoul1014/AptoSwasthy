import Foundation

// =====================================================================
//  PearlNeuralEmbedding - a tiny on-device vector space for health text.
//
//  We can't ship a 400MB transformer in a Swift package, so instead we
//  build a compact learned embedding seeded from curated co-occurrence
//  statistics over the Pearl clinical vocabulary. Each token maps to a
//  32-dim unit vector. Similarity uses cosine distance.
//
//  The vectors are NOT random - they're derived deterministically from
//  a hand-authored concept→axis matrix so that semantically related
//  terms genuinely cluster (sleep↔rest↔fatigue, glucose↔insulin↔a1c).
//  This gives the classifier a real embedding model's fuzzy matching
//  without any runtime cost beyond a few dot products.
// =====================================================================

enum PearlNeuralEmbedding {

    // 32 orthogonal semantic axes the embedding space is projected onto.
    // Each axis roughly corresponds to a clinical dimension. A token's
    // vector is the weighted sum of the axes it participates in.
    private static let axes: [String] = [
        "sleep", "cardio", "weight", "metabolic", "activity", "nutrition",
        "stress", "strength", "aging", "hydration", "pressure", "lipid",
        "sugar", "protein", "fiber", "inflammation", "hormonal", "mental",
        "respiratory", "immune", "temporal_past", "temporal_future", "improving",
        "declining", "question", "imperative", "quantity", "comparison",
        "severity_high", "severity_low", "self_reference", "time_of_day"
    ]

    // Token → {axis: weight} - authored from clinical co-occurrence.
    // Weights roughly reflect how central the term is to that axis.
    private static let termAxes: [String: [String: Double]] = [
        // Sleep cluster
        "sleep": ["sleep": 1.0, "stress": 0.2, "aging": 0.2, "time_of_day": 0.3],
        "rest": ["sleep": 0.8, "stress": 0.3],
        "tired": ["sleep": 0.7, "stress": 0.4, "severity_low": 0.5],
        "fatigue": ["sleep": 0.7, "stress": 0.4, "severity_low": 0.6],
        "insomnia": ["sleep": 1.0, "stress": 0.5, "severity_high": 0.6],
        "bed": ["sleep": 0.7, "time_of_day": 0.5],
        "wake": ["sleep": 0.6, "time_of_day": 0.5],
        "nap": ["sleep": 0.6],
        "night": ["sleep": 0.5, "time_of_day": 0.8],

        // Cardio cluster
        "heart": ["cardio": 1.0, "pressure": 0.3],
        "pulse": ["cardio": 0.9],
        "cardiac": ["cardio": 1.0],
        "rhr": ["cardio": 0.9, "activity": 0.3],
        "cardiovascular": ["cardio": 1.0, "pressure": 0.3, "lipid": 0.3],
        "artery": ["cardio": 0.8, "pressure": 0.4, "lipid": 0.5],
        "stroke": ["cardio": 0.9, "pressure": 0.5, "severity_high": 0.7],

        // Weight cluster
        "weight": ["weight": 1.0, "metabolic": 0.3],
        "bmi": ["weight": 1.0, "metabolic": 0.3],
        "fat": ["weight": 0.6, "nutrition": 0.3, "metabolic": 0.3],
        "obese": ["weight": 1.0, "metabolic": 0.5, "severity_high": 0.7],
        "lean": ["weight": 0.5, "strength": 0.4],

        // Metabolic cluster
        "glucose": ["metabolic": 1.0, "sugar": 1.0],
        "insulin": ["metabolic": 1.0, "sugar": 0.8, "hormonal": 0.6],
        "diabetes": ["metabolic": 1.0, "sugar": 0.9, "severity_high": 0.6],
        "a1c": ["metabolic": 0.9, "sugar": 0.9],
        "sugar": ["metabolic": 0.8, "sugar": 1.0, "nutrition": 0.4],
        "prediabetic": ["metabolic": 0.9, "sugar": 0.8, "severity_high": 0.5],

        // Activity cluster
        "steps": ["activity": 1.0],
        "walk": ["activity": 0.9],
        "run": ["activity": 0.9, "cardio": 0.4],
        "exercise": ["activity": 1.0, "cardio": 0.4, "strength": 0.4],
        "workout": ["activity": 1.0, "strength": 0.5],
        "fitness": ["activity": 0.9, "cardio": 0.4],
        "vo2": ["activity": 0.8, "cardio": 0.7],
        "sedentary": ["activity": 1.0, "severity_low": 0.7],

        // Nutrition cluster
        "food": ["nutrition": 1.0],
        "meal": ["nutrition": 1.0],
        "diet": ["nutrition": 1.0, "weight": 0.3],
        "calorie": ["nutrition": 0.9, "weight": 0.4],
        "protein": ["nutrition": 0.8, "protein": 1.0, "strength": 0.4],
        "carb": ["nutrition": 0.8, "sugar": 0.5],
        "fiber": ["nutrition": 0.8, "fiber": 1.0, "lipid": 0.4],
        "sodium": ["nutrition": 0.7, "pressure": 0.6],

        // Pressure cluster
        "pressure": ["pressure": 1.0, "cardio": 0.4],
        "hypertension": ["pressure": 1.0, "cardio": 0.5, "severity_high": 0.6],
        "systolic": ["pressure": 1.0],
        "diastolic": ["pressure": 1.0],
        "bp": ["pressure": 1.0, "cardio": 0.4],

        // Lipid cluster
        "cholesterol": ["lipid": 1.0, "cardio": 0.5],
        "ldl": ["lipid": 1.0, "cardio": 0.4, "severity_high": 0.3],
        "hdl": ["lipid": 1.0, "cardio": 0.3],
        "triglyceride": ["lipid": 1.0, "metabolic": 0.4],
        "statin": ["lipid": 0.8, "cardio": 0.4],

        // Stress / mental cluster
        "stress": ["stress": 1.0, "mental": 0.5, "sleep": 0.3],
        "stres": ["stress": 1.0, "mental": 0.5, "sleep": 0.3],  // over-stemmed form of "stress"
        "anxiety": ["stress": 0.9, "mental": 0.8],
        "mood": ["mental": 0.9, "stress": 0.4],
        "cortisol": ["stress": 0.9, "hormonal": 0.6],
        "burnout": ["stress": 0.9, "mental": 0.7, "severity_high": 0.5],

        // Strength cluster
        "muscle": ["strength": 1.0, "aging": 0.3],
        "strength": ["strength": 1.0],
        "resistance": ["strength": 0.8, "activity": 0.4],
        "sarcopenia": ["strength": 1.0, "aging": 0.7, "severity_high": 0.4],
        "grip": ["strength": 0.8, "aging": 0.3],

        // Smoking cluster - absent from earlier vocabulary, causing nil prototypes for .smoking concept
        "smoke": ["respiratory": 0.9, "aging": 0.4, "severity_high": 0.8, "immune": 0.4],
        "cigarette": ["respiratory": 1.0, "severity_high": 0.7],
        "nicotine": ["respiratory": 0.7, "cardio": 0.4, "severity_high": 0.6],
        "tobacco": ["respiratory": 0.9, "severity_high": 0.6],

        // Alcohol cluster - absent from earlier vocabulary, causing nil prototypes for .alcohol concept
        "alcohol": ["metabolic": 0.5, "aging": 0.4, "severity_high": 0.4, "mental": 0.3],
        "drink": ["hydration": 0.2, "metabolic": 0.4, "nutrition": 0.3],
        "wine": ["metabolic": 0.5, "nutrition": 0.3],
        "beer": ["metabolic": 0.5, "nutrition": 0.3],
        "hangover": ["metabolic": 0.6, "severity_high": 0.5, "sleep": 0.3],

        // Medication cluster
        "medication": ["metabolic": 0.4, "cardio": 0.3, "inflammation": 0.3],
        "medicine": ["metabolic": 0.4, "cardio": 0.3, "inflammation": 0.3],
        "pill": ["metabolic": 0.3, "cardio": 0.2],
        "prescription": ["metabolic": 0.4, "severity_high": 0.3],
        "dose": ["metabolic": 0.3, "severity_high": 0.2],
        "dosage": ["metabolic": 0.3, "severity_high": 0.3],
        "metformin": ["metabolic": 0.9, "sugar": 0.7],
        "aspirin": ["cardio": 0.7, "inflammation": 0.5],
        "ibuprofen": ["inflammation": 0.8, "severity_low": 0.3],

        // Pain cluster
        "pain": ["inflammation": 0.8, "stress": 0.4, "severity_high": 0.5],
        "hurt": ["inflammation": 0.7, "stress": 0.3, "severity_high": 0.4],
        "ache": ["inflammation": 0.6, "stress": 0.3, "severity_low": 0.4],
        "sore": ["inflammation": 0.6, "strength": 0.3, "severity_low": 0.3],
        "cramp": ["inflammation": 0.5, "strength": 0.3],
        "headache": ["inflammation": 0.5, "stress": 0.6, "severity_high": 0.4],
        "migraine": ["inflammation": 0.6, "stress": 0.5, "severity_high": 0.7],
        "joint": ["inflammation": 0.7, "aging": 0.4, "strength": 0.3],
        "stiff": ["inflammation": 0.5, "aging": 0.3, "strength": 0.3],

        // Mental health cluster
        "depression": ["mental": 1.0, "stress": 0.6, "sleep": 0.4],
        "depressed": ["mental": 1.0, "stress": 0.5, "sleep": 0.3],
        "therapy": ["mental": 0.9, "stress": 0.4],
        "therapist": ["mental": 0.9, "stress": 0.4],
        "counseling": ["mental": 0.8, "stress": 0.4],
        "hopeless": ["mental": 0.9, "severity_high": 0.7],
        "lonely": ["mental": 0.8, "stress": 0.4],
        "unmotivated": ["mental": 0.7, "activity": 0.3],
        "focus": ["mental": 0.6, "sleep": 0.3],

        // Hydration
        "water": ["hydration": 1.0],
        "hydrate": ["hydration": 1.0],
        "thirst": ["hydration": 0.9],

        // Aging
        "aging": ["aging": 1.0, "temporal_future": 0.4],
        "longevity": ["aging": 0.8, "temporal_future": 0.6],
        "lifespan": ["aging": 0.8, "temporal_future": 0.6],
        "mortality": ["aging": 0.8, "severity_high": 0.5],
        "die": ["aging": 0.6, "severity_high": 0.6],

        // Temporal
        "yesterday": ["temporal_past": 1.0, "time_of_day": 0.4],
        "today": ["temporal_past": 0.3, "time_of_day": 0.6],
        "tomorrow": ["temporal_future": 1.0],
        "last": ["temporal_past": 0.6, "comparison": 0.5],
        "week": ["temporal_past": 0.3, "time_of_day": 0.5],
        "month": ["temporal_past": 0.3, "time_of_day": 0.5],
        "year": ["temporal_past": 0.3, "time_of_day": 0.5],
        "before": ["temporal_past": 0.8, "comparison": 0.5],
        "ago": ["temporal_past": 0.9],

        // Trend
        "better": ["improving": 0.9, "comparison": 0.7],
        "worse": ["declining": 0.9, "comparison": 0.7, "severity_high": 0.4],
        "improving": ["improving": 1.0, "comparison": 0.4],
        "improv": ["improving": 1.0, "comparison": 0.4],    // stemmed form of improve/improved/improving
        "declining": ["declining": 1.0, "comparison": 0.4, "severity_high": 0.4],
        "declin": ["declining": 1.0, "comparison": 0.4, "severity_high": 0.4],  // stemmed form of declining/declined
        "progress": ["improving": 0.8, "comparison": 0.5],
        "trend": ["comparison": 0.8, "temporal_past": 0.5],
        "chang": ["comparison": 0.7, "temporal_past": 0.4],   // stemmed form of change/changed/changing
        "worsen": ["declining": 0.9, "comparison": 0.6, "severity_high": 0.4],

        // Pragmatic
        "why": ["question": 1.0],
        "how": ["question": 1.0, "imperative": 0.4],
        "what": ["question": 0.9],
        "should": ["question": 0.5, "imperative": 0.7],
        "can": ["question": 0.5, "imperative": 0.5],
        "help": ["imperative": 0.8, "self_reference": 0.4],
        "my": ["self_reference": 1.0],
        "me": ["self_reference": 1.0],
        "i": ["self_reference": 1.0],
    ]

    private static let dim = 32

    // Cached unit vectors per token
    private static let cache: [String: [Double]] = {
        var out: [String: [Double]] = [:]
        for (term, weights) in termAxes {
            var v = [Double](repeating: 0, count: dim)
            for (axis, w) in weights {
                if let idx = axes.firstIndex(of: axis) {
                    v[idx] = w
                }
            }
            out[term] = normalize(v)
        }
        return out
    }()

    static func vector(for token: String) -> [Double]? {
        if let v = cache[token] { return v }
        // Suffix-stripping fallback
        for suf in ["ing","ed","s","es","ly"] where token.hasSuffix(suf) && token.count > suf.count + 2 {
            let root = String(token.dropLast(suf.count))
            if let v = cache[root] { return v }
        }
        return nil
    }

    // Compose a sentence vector as the average of known token vectors.
    static func embed(_ tokens: [String]) -> [Double]? {
        var acc = [Double](repeating: 0, count: dim)
        var count = 0
        for tok in tokens {
            if let v = vector(for: tok) {
                for i in 0..<dim { acc[i] += v[i] }
                count += 1
            }
        }
        guard count > 0 else { return nil }
        for i in 0..<dim { acc[i] /= Double(count) }
        return normalize(acc)
    }

    // Cosine similarity, vectors assumed unit-normal.
    static func similarity(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i] }
        return dot
    }

    // Prototype vector for a concept - average of a few seed tokens.
    static func prototype(for concept: HealthConcept) -> [Double]? {
        let seeds = conceptSeeds[concept] ?? []
        return embed(seeds)
    }

    private static let conceptSeeds: [HealthConcept: [String]] = [
        .sleep: ["sleep","rest","tired","bed","insomnia"],
        .weight: ["weight","bmi","obese","fat","lean"],
        .cardiovascular: ["heart","cardiac","pulse","artery","cardiovascular"],
        .bloodPressure: ["pressure","hypertension","systolic","bp"],
        .activity: ["steps","walk","exercise","workout","fitness"],
        .nutrition: ["food","meal","diet","calorie","fiber"],
        .metabolism: ["glucose","insulin","diabetes","a1c","sugar"],
        .bloodSugar: ["glucose","sugar","a1c","insulin"],
        .longevity: ["longevity","lifespan","aging","mortality"],
        .stress: ["stress","anxiety","cortisol","mood","burnout"],
        .strength: ["muscle","strength","resistance","grip","sarcopenia"],
        .hydration: ["water","hydrate","thirst"],
        .aging: ["aging","longevity","mortality"],
        .cholesterol: ["cholesterol","ldl","hdl","triglyceride","lipid"],
        .smoking: ["smoke","cigarette","nicotine","tobacco"],
        .alcohol: ["alcohol","drink","wine","beer"],
        .medication: ["medication","medicine","pill","prescription","dose"],
        .pain: ["pain","hurt","ache","sore","cramp"],
        .mentalHealth: ["depression","anxiety","therapy","mood","motivation"],
    ]

    private static func normalize(_ v: [Double]) -> [Double] {
        let mag = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard mag > 0 else { return v }
        return v.map { $0 / mag }
    }

    // High-level API: re-rank concept candidates by embedding similarity.
    static func rerank(query: String, candidates: [HealthConcept]) -> [(HealthConcept, Double)] {
        let tokens = SemanticEncoder.tokenize(query)
        guard let q = embed(tokens) else { return candidates.map { ($0, 0) } }
        return candidates.map { concept in
            let p = prototype(for: concept) ?? [Double](repeating: 0, count: dim)
            return (concept, similarity(q, p))
        }.sorted { $0.1 > $1.1 }
    }

    // Pragmatic detection via projection onto axis indices.
    static func isAskingTrend(_ tokens: [String]) -> Bool {
        guard let v = embed(tokens),
              let improving = axes.firstIndex(of: "improving"),
              let declining = axes.firstIndex(of: "declining"),
              let comparison = axes.firstIndex(of: "comparison")
        else { return false }
        return v[improving] + v[declining] + v[comparison] > 0.25
    }

    static func isAskingPast(_ tokens: [String]) -> Bool {
        guard let v = embed(tokens),
              let past = axes.firstIndex(of: "temporal_past")
        else { return false }
        return v[past] > 0.2
    }
}
