import Foundation
import Observation

@MainActor
@Observable
final class YouViewModel {
    var profile: UserProfile? = nil
    var fitnessScore: Double = 0
    var metrics: [HealthMetric] = []

    private let persistence = PersistenceService.shared
    @ObservationIgnored nonisolated(unsafe) private var profileUpdateObserver: NSObjectProtocol?

    init() {
        profileUpdateObserver = NotificationCenter.default.addObserver(
            forName: .profileUpdated, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.load() }
        }
    }

    deinit {
        if let token = profileUpdateObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func load() {
        let p = persistence.fetchProfile()
        let m = persistence.fetchMetrics()
        self.profile = p
        self.metrics = m
        self.fitnessScore = computeFitnessScore(profile: p, metrics: m)
    }

    func save() {
        guard profile != nil else { return }
        persistence.save()
    }

    func bodyFatEstimate(profile: UserProfile) -> String {
        String(format: "~%.0f%%", bodyFatPercent(profile: profile))
    }

    /// Body fat % using a logged HealthKit value if available, otherwise the
    /// Deurenberg BMI-based estimate. Always returns a clamped value (5..60).
    func bodyFatPercent(profile: UserProfile) -> Double {
        if let logged = metrics
            .filter({ $0.type == .bodyFatPercentage })
            .sorted(by: { $0.recordedAt > $1.recordedAt })
            .first?.value {
            // HealthKit stores fraction (0..1) sometimes, percent (0..100) other times
            let pct = logged <= 1.0 ? logged * 100.0 : logged
            return max(5, min(pct, 60))
        }
        let age = Double(profile.age)
        let bmi = profile.bmi
        let sexFactor: Double = profile.biologicalSex == .male ? 1.0 : 0.0
        let bf = (1.20 * bmi) + (0.23 * age) - (10.8 * sexFactor) - 5.4
        return max(5, min(bf, 60))
    }

    private func computeFitnessScore(profile: UserProfile?, metrics: [HealthMetric]) -> Double {
        guard let profile else { return 0 }
        var score = 50.0

        // VO2 max
        if let vo2 = metrics.filter({ $0.type == .vo2Max }).sorted(by: { $0.recordedAt > $1.recordedAt }).first?.value {
            score += min((vo2 - 30) / 30 * 20, 20)
        }

        // Resting HR
        if let rhr = metrics.filter({ $0.type == .restingHeartRate }).sorted(by: { $0.recordedAt > $1.recordedAt }).first?.value {
            score += rhr < 60 ? 15 : rhr < 70 ? 10 : rhr < 80 ? 5 : 0
        }

        // Activity level
        switch profile.activityLevel {
        case .sedentary: score -= 10
        case .lightlyActive: score += 0
        case .moderatelyActive: score += 10
        case .veryActive: score += 15
        case .extremelyActive: score += 18
        }

        // BMI
        switch profile.bmiCategory {
        case .normal: score += 5
        case .underweight: score -= 5
        case .overweight: score -= 5
        case .obese: score -= 15
        }

        return max(0, min(100, score))
    }
}
