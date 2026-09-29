import Foundation
import Observation

@MainActor
@Observable
final class RisksViewModel {
    var risks: [DiseaseRisk] = []
    var isLoading = false
    var profile: UserProfile? = nil

    private let persistence = PersistenceService.shared
    private let pearl = Pearl.shared
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
        isLoading = true
        let fetchedProfile = persistence.fetchProfile()
        let fetchedMetrics = persistence.fetchMetrics()
        let bloodTests = persistence.fetchLatestBloodTests()

        guard let fetchedProfile else { isLoading = false; return }

        let computed = pearl.assessRisks(profile: fetchedProfile, metrics: fetchedMetrics, bloodTests: bloodTests)

        self.profile = fetchedProfile
        let sorted = computed.sorted { tierOrder($0.tier) > tierOrder($1.tier) }
        self.risks = sorted

        // Only re-persist if the risk tiers or driving factors actually changed
        // to avoid unnecessary SwiftData writes on every tab visit.
        let stored = persistence.fetchRisks()
        let storedMap = Dictionary(uniqueKeysWithValues: stored.map { ($0.condition, $0.tier) })
        let hasChanges = computed.contains { risk in storedMap[risk.condition] != risk.tier }
        if hasChanges || stored.count != computed.count {
            persistence.clearRisks()
            computed.forEach { persistence.insert($0) }
        }
        isLoading = false
    }

    var overallSummary: String {
        let highCount = risks.filter { $0.tier == .high }.count
        let modCount  = risks.filter { $0.tier == .moderate }.count
        if highCount == 0 && modCount == 0 {
            return "No elevated risks detected. Keep doing what you're doing."
        } else if highCount > 0 {
            return "\(highCount) area\(highCount > 1 ? "s" : "") worth discussing with your doctor. Pearl recommends focusing there first."
        } else {
            return "\(modCount) area\(modCount > 1 ? "s" : "") with moderate risk. Small changes can move these numbers."
        }
    }

    var allClearMessage: String {
        "No elevated risks right now. Pearl will update this automatically as your data changes. New blood test results, weight changes, and activity all factor in."
    }

    private func tierOrder(_ tier: RiskTier) -> Int {
        switch tier {
        case .high: return 2
        case .moderate: return 1
        case .low: return 0
        }
    }
}
