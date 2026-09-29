import Foundation

// Stress score (0–100, higher = more physiological stress). Inverse-leaning
// counterpart to PearlRecovery - they share inputs but weight RHR/HRV more
// heavily because those are the most direct autonomic stress signals.
//   • RHR elevation above personal baseline
//   • HRV depression below personal baseline
//   • Sleep deficit vs 7.5h target
//   • Sustained step deficit (sedentary stress)
// Components missing real data fall back to a neutral 50.
final class PearlStress {

    func score(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        let rhrSub   = rhrStress(profile: profile, metrics: metrics)
        let hrvSub   = hrvStress(profile: profile, metrics: metrics)
        let sleepSub = sleepStress(metrics: metrics)
        let sedSub   = sedentaryStress(metrics: metrics)

        // HRV is the most sensitive autonomic stress marker. RHR is reliable
        // but slower. Sleep deficit drives sympathetic tone within days.
        let weighted = hrvSub * 0.35 + rhrSub * 0.30 + sleepSub * 0.25 + sedSub * 0.10
        return max(0, min(100, weighted))
    }

    // MARK: - Subscores (higher = more stress)

    private func rhrStress(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        guard let current = latest(.restingHeartRate, metrics) else { return 50 }
        let baseline = baselineRHR(profile: profile, metrics: metrics)
        let elevation = current - baseline
        // Below baseline → low stress. +5 bpm → 55. +10 bpm → 80. +15 → 100.
        if elevation <= -3 { return 5 }
        if elevation <= 0  { return 5 + (elevation + 3) / 3.0 * 20 }   // 5–25
        return min(100, 25 + elevation * 5)
    }

    private func hrvStress(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        guard let current = latest(.heartRateVariability, metrics) else { return 50 }
        let baseline = baselineHRV(profile: profile, metrics: metrics)
        guard baseline > 1 else { return 50 }
        let ratio = current / baseline
        // ratio 1.2+ → 5; 1.0 → 25; 0.8 → 55; 0.5 → 100.
        if ratio >= 1.2 { return 5 }
        if ratio >= 1.0 { return 25 - (ratio - 1.0) * 100 }   // 5–25
        return min(100, 25 + (1.0 - ratio) * 150)
    }

    private func sleepStress(metrics: [HealthMetric]) -> Double {
        guard let hours = latest(.sleepDuration, metrics) else { return 50 }
        let deficit = 7.5 - hours
        // Sleep > 7h → low stress. 6h → 40. 5h → 65. 4h → 90.
        if deficit <= -0.5 { return 10 }                      // oversleeping is mildly elevated
        if deficit <= 0.5  { return 15 }
        return min(100, 15 + (deficit - 0.5) * 25)
    }

    private func sedentaryStress(metrics: [HealthMetric]) -> Double {
        let stepHistory = metrics
            .filter { $0.type == .steps }
            .sorted { $0.recordedAt > $1.recordedAt }
        guard stepHistory.count >= 3 else { return 30 }

        let recent = stepHistory.prefix(3).map(\.value)
        let avg = recent.reduce(0, +) / Double(recent.count)
        // <2k steps/day for 3 days → strong sedentary signal. >7k → minimal.
        if avg >= 7000 { return 10 }
        if avg >= 4000 { return 20 + (7000 - avg) / 3000 * 25 }   // 20–45
        return min(100, 45 + (4000 - avg) / 2000 * 30)
    }

    // MARK: - Baselines (mirror PearlRecovery so both engines stay in sync)

    private func baselineRHR(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        let recent = metrics
            .filter { $0.type == .restingHeartRate }
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(30)
            .map(\.value)
        if recent.count >= 5 { return median(recent) }
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
