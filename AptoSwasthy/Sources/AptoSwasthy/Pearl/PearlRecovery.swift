import Foundation

// Recovery score (0–100). Combines four physiological signals:
//   • Sleep duration vs 7.5h target
//   • RHR deviation from personal 30-day baseline (elevated → poor recovery)
//   • HRV deviation from personal 30-day baseline (depressed → poor recovery)
//   • Recent training load (last 3 days steps vs 14-day median)
// Each subscore is 0–100; the overall score is a weighted average. Components
// missing real data fall back to a neutral 50 so the result degrades gracefully
// instead of returning misleading extremes.
final class PearlRecovery {

    func score(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        let sleepSub = sleepSubscore(metrics: metrics)
        let rhrSub   = rhrSubscore(profile: profile, metrics: metrics)
        let hrvSub   = hrvSubscore(profile: profile, metrics: metrics)
        let loadSub  = loadSubscore(metrics: metrics)

        // Weights: sleep dominates, HRV is the most sensitive autonomic signal,
        // RHR is reliable but slower-moving, training load is contextual.
        let weighted = sleepSub * 0.35 + hrvSub * 0.30 + rhrSub * 0.20 + loadSub * 0.15
        return max(0, min(100, weighted))
    }

    // MARK: - Subscores

    private func sleepSubscore(metrics: [HealthMetric]) -> Double {
        guard let hours = latest(.sleepDuration, metrics) else { return 50 }
        // Bell-curve around 7.5h; <5h or >10h drops sharply.
        let delta = abs(hours - 7.5)
        if delta <= 0.5 { return 100 }
        if delta <= 1.5 { return 100 - (delta - 0.5) * 20 }   // 80 at ±1.5h
        return max(0, 80 - (delta - 1.5) * 25)
    }

    private func rhrSubscore(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        guard let current = latest(.restingHeartRate, metrics) else { return 50 }
        let baseline = baselineRHR(profile: profile, metrics: metrics)
        let elevation = current - baseline
        // 0 elevation → 100; +5 bpm → 70; +10 bpm → 40; below baseline boosts.
        if elevation <= -3 { return 100 }
        if elevation <= 0  { return 90 - elevation * 3 }      // 90–99
        return max(0, 100 - elevation * 6)
    }

    private func hrvSubscore(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        guard let current = latest(.heartRateVariability, metrics) else { return 50 }
        let baseline = baselineHRV(profile: profile, metrics: metrics)
        guard baseline > 1 else { return 50 }
        let ratio = current / baseline
        // ratio 1.0 → 80; 1.2+ → 100; 0.8 → 50; 0.5 → 10.
        if ratio >= 1.2 { return 100 }
        if ratio >= 1.0 { return 80 + (ratio - 1.0) * 100 }   // 80–100
        return max(0, 80 - (1.0 - ratio) * 175)
    }

    private func loadSubscore(metrics: [HealthMetric]) -> Double {
        let stepHistory = metrics
            .filter { $0.type == .steps }
            .sorted { $0.recordedAt > $1.recordedAt }
        guard stepHistory.count >= 4 else { return 70 }   // not enough history → mild positive

        let recent = stepHistory.prefix(3).map(\.value)
        let baseline = stepHistory.prefix(14).map(\.value)
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let baseAvg = baseline.reduce(0, +) / Double(baseline.count)
        guard baseAvg > 100 else { return 70 }

        let ratio = recentAvg / baseAvg
        // Moderate load (0.7–1.2× baseline) → 100. Heavy overload → drops.
        if ratio <= 0.4 { return 70 }                     // detraining penalty
        if ratio <= 1.2 { return 100 }
        return max(40, 100 - (ratio - 1.2) * 80)
    }

    // MARK: - Baselines

    private func baselineRHR(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        let recent = metrics
            .filter { $0.type == .restingHeartRate }
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(30)
            .map(\.value)
        if recent.count >= 5 { return median(recent) }
        // Age/sex defaults from population norms.
        let base: Double = profile.biologicalSex == .female ? 67 : 64
        return base + max(0, Double(profile.age - 40)) * 0.1
    }

    private func baselineHRV(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        let recent = metrics
            .filter { $0.type == .heartRateVariability }
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(30)
            .map(\.value)
        if recent.count >= 5 { return median(recent) }
        // Population SDNN baselines (ms) drop ~0.5/yr after age 30.
        let base: Double = profile.biologicalSex == .female ? 48 : 50
        return max(20, base - max(0, Double(profile.age - 30)) * 0.5)
    }

    // MARK: - Helpers

    private func latest(_ type: MetricType, _ metrics: [HealthMetric]) -> Double? {
        metrics
            .filter { $0.type == type }
            .sorted { $0.recordedAt > $1.recordedAt }
            .first?.value
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}
