import Foundation

// =====================================================================
//  PearlTrendAnalysis - time-series reasoning over the user's metrics.
//
//  Pearl's conversation engine reasons over *current* values. This module
//  adds the temporal axis: is a metric rising or falling, how fast, and
//  whether the direction is good or bad for that particular metric.
//
//  Core output is a Trend struct which the brain can weave into replies
//  like "your RHR dropped 6 bpm over the last three weeks - that's the
//  kind of change that tracks with meaningful aerobic adaptation."
// =====================================================================

struct Trend {
    enum Direction { case improving, declining, flat, insufficient }

    let metric: MetricType
    let direction: Direction
    let delta: Double          // absolute change (latest - baseline)
    let percentChange: Double  // percent (0..1)
    let baselineValue: Double
    let latestValue: Double
    let windowDays: Int
    let sampleCount: Int

    var isMeaningful: Bool {
        direction != .flat && direction != .insufficient && abs(percentChange) >= 0.03
    }

    func humanPhrase() -> String {
        let unit = metric.defaultUnit
        let absDelta = abs(delta)
        let pct = Int(abs(percentChange) * 100)
        let directionWord: String
        switch direction {
        case .improving: directionWord = "in a healthier direction"
        case .declining: directionWord = "in the wrong direction"
        case .flat:       directionWord = "essentially flat"
        case .insufficient: directionWord = "hard to judge (not enough samples yet)"
        }
        if direction == .insufficient {
            return "Your \(metric.rawValue) trend is \(directionWord)."
        }
        if direction == .flat {
            return "Your \(metric.rawValue) has held steady at about \(formatted(latestValue)) \(unit) over the last \(windowDays) days."
        }
        return "Your \(metric.rawValue) has moved \(directionWord): \(formatted(baselineValue)) → \(formatted(latestValue)) \(unit) (\(pct)% change, \(formatted(absDelta)) \(unit)) across \(sampleCount) readings over \(windowDays) days."
    }

    private func formatted(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

@MainActor
enum PearlTrendAnalysis {

    // For each metric, indicate whether *higher* is generally healthier.
    private static let higherIsBetter: [MetricType: Bool] = [
        .steps: true,
        .vo2Max: true,
        .cholesterolHDL: true,
        .oxygenSaturation: true,
        .waterIntake: true,
        .sleepDuration: true,
        .nutritionScore: true,
        .fitnessScore: true,
        // Lower is better
        .restingHeartRate: false,
        .weight: false,
        .bloodPressureSystolic: false,
        .bloodPressureDiastolic: false,
        .bloodGlucose: false,
        .cholesterolTotal: false,
        .cholesterolLDL: false,
        .triglycerides: false,
        .bodyFatPercentage: false,
        .heartRate: false,
    ]

    static func analyze(metric: MetricType, samples: [HealthMetric], windowDays: Int = 30) -> Trend {
        let cutoff = Date().addingTimeInterval(TimeInterval(-windowDays * 86_400))
        let matching: [HealthMetric] = samples.filter { $0.type == metric && $0.recordedAt >= cutoff }
        let filtered: [HealthMetric] = matching.sorted { $0.recordedAt < $1.recordedAt }

        guard filtered.count >= 3 else {
            return Trend(metric: metric, direction: .insufficient,
                         delta: 0, percentChange: 0,
                         baselineValue: filtered.first?.value ?? 0,
                         latestValue: filtered.last?.value ?? 0,
                         windowDays: windowDays, sampleCount: filtered.count)
        }

        // Baseline = median of the earliest third, latest = median of the most recent third.
        let n = filtered.count
        let firstThird = Array(filtered.prefix(max(1, n / 3))).map(\.value).sorted()
        let lastThird  = Array(filtered.suffix(max(1, n / 3))).map(\.value).sorted()
        let baseline = firstThird[firstThird.count / 2]
        let latest   = lastThird[lastThird.count / 2]
        let delta = latest - baseline
        let pct = baseline == 0 ? 0 : delta / baseline

        let direction: Trend.Direction
        if abs(pct) < 0.03 {
            direction = .flat
        } else {
            let rising = delta > 0
            let higherBetter = higherIsBetter[metric] ?? true
            direction = (rising == higherBetter) ? .improving : .declining
        }

        return Trend(metric: metric, direction: direction,
                     delta: delta, percentChange: pct,
                     baselineValue: baseline, latestValue: latest,
                     windowDays: windowDays, sampleCount: n)
    }

    // Return every metric with a meaningful move over the window, most
    // significant first.
    static func meaningfulTrends(metrics: [HealthMetric], windowDays: Int = 30) -> [Trend] {
        let types = Set(metrics.map(\.type))
        return types
            .map { analyze(metric: $0, samples: metrics, windowDays: windowDays) }
            .filter(\.isMeaningful)
            .sorted { abs($0.percentChange) > abs($1.percentChange) }
    }

    // Quick summary paragraph - used when the user asks "how am I doing?"
    // or "any progress?"
    static func summaryNarrative(metrics: [HealthMetric], windowDays: Int = 30) -> String? {
        let trends = meaningfulTrends(metrics: metrics, windowDays: windowDays)
        guard !trends.isEmpty else { return nil }
        let improving = trends.filter { $0.direction == .improving }.prefix(3)
        let declining = trends.filter { $0.direction == .declining }.prefix(3)

        var parts: [String] = []
        if !improving.isEmpty {
            parts.append("Moving in a good direction: " + improving.map { bulletPhrase($0) }.joined(separator: "; ") + ".")
        }
        if !declining.isEmpty {
            parts.append("Worth attention: " + declining.map { bulletPhrase($0) }.joined(separator: "; ") + ".")
        }
        return parts.joined(separator: " ")
    }

    private static func bulletPhrase(_ t: Trend) -> String {
        let pct = Int(abs(t.percentChange) * 100)
        // Arrow shows actual movement direction (↑ = value went up, ↓ = value went down),
        // not an abstract "better/worse" flag - so it's accurate for both higher-is-better
        // and lower-is-better metrics.
        let arrow = t.delta > 0 ? "↑" : "↓"
        let sentiment = t.direction == .improving ? "good direction" : "needs attention"
        return "\(t.metric.rawValue.lowercased()) \(arrow)\(pct)% (\(sentiment))"
    }
}
