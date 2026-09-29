import Foundation
import HealthKit

@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    // Persisted across launches so we know to auto-sync without re-prompting.
    @Published var isAuthorized: Bool = UserDefaults.standard.bool(forKey: "hkAuthorized")
    @Published var isBackfilling: Bool = false
    /// 0.0 → 1.0 while a historical backfill is in progress. 0 when idle.
    /// Used by ConnectedAppsView to render a progress ring on the sync button.
    @Published var backfillProgress: Double = 0
    /// Prevents concurrent `syncToLocal` calls from racing on upsert logic.
    private var isSyncing = false

    private let readTypes: Set<HKObjectType> = {
        let ids: [HKQuantityTypeIdentifier] = [
            .stepCount, .heartRate, .restingHeartRate, .bodyMass,
            .bloodPressureSystolic, .bloodPressureDiastolic,
            .bloodGlucose, .dietaryEnergyConsumed, .dietaryProtein,
            .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFiber,
            .oxygenSaturation, .bodyFatPercentage, .vo2Max,
            .dietaryWater, .heartRateVariabilitySDNN,
            .activeEnergyBurned, .appleExerciseTime, .respiratoryRate
        ]
        var types = Set(ids.compactMap { HKQuantityType.quantityType(forIdentifier: $0) as HKObjectType? })
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        return types
    }()

    private let writeTypes: Set<HKSampleType> = {
        let ids: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed, .dietaryProtein,
            .dietaryCarbohydrates, .dietaryFatTotal, .dietaryWater
        ]
        return Set(ids.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
    }()

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            // Optimistic: if the auth call returned without throwing, treat the
            // user as authorized and proceed. HealthKit intentionally hides
            // read-denials, so the heuristic of "has data" was excluding new
            // HealthKit users who granted everything but had no step/heart
            // samples yet. If they truly denied, syncs simply return no data
            // and the user can verify in iOS Settings → Health.
            isAuthorized = true
            UserDefaults.standard.set(true, forKey: "hkAuthorized")

            // Remember the connection in the cloud-synced profile so the
            // reconnect prompt fires on a new device.
            PersistenceService.shared.markAppConnected("Apple Health")
            if let profile = PersistenceService.shared.fetchProfile() {
                let dto = ProfileDTO(from: profile)
                Task.detached {
                    try? await ProfileAPIService.shared.putProfile(dto)
                }
            }

            await syncToLocal()
            // First-time auth: pull up to 5 years of history so Pearl can
            // reason about long-term trends immediately. A new flag key
            // (v2) ensures users who already had the 90-day backfill also
            // get the full history on the next launch.
            if !UserDefaults.standard.bool(forKey: "hkHistoricalBackfillDone_v2") {
                Task { [weak self] in
                    guard let self else { return }
                    self.isBackfilling = true
                    self.backfillProgress = 0
                    await self.backfillHistorical(days: 1825)
                    await self.backfillSleepHistorical(days: 1825)
                    self.backfillProgress = 1.0
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    self.isBackfilling = false
                    self.backfillProgress = 0
                    UserDefaults.standard.set(true, forKey: "hkHistoricalBackfillDone_v2")
                }
            }
            registerBackgroundDelivery()
        } catch {
#if DEBUG
            print("HealthKit auth error: \(error)")
#endif
        }
    }

    /// Call on app launch - syncs if the user already granted access.
    /// Also attempts a sync if any write type is authorized, which catches
    /// users who granted permission via iOS Settings outside the app's flow.
    func syncIfAuthorized() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if isAuthorized {
            await syncToLocal()
            return
        }
        // Probe write-type auth status - if granted, the user authorized us
        // (possibly via iOS Settings). Mark as authorized and sync.
        for writeType in writeTypes {
            if store.authorizationStatus(for: writeType) == .sharingAuthorized {
                isAuthorized = true
                UserDefaults.standard.set(true, forKey: "hkAuthorized")
                await syncToLocal()
                registerBackgroundDelivery()
                return
            }
        }
    }

    func syncToLocal() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let persistence = PersistenceService.shared

        // Instantaneous metrics - last sample is what we want (BP reading,
        // current heart rate, latest weigh-in). `displayScale` converts the
        // HealthKit-native unit value to the value we actually show in the UI:
        // percentage quantities come back as a fraction in [0, 1] but the UI
        // labels `%`, so we scale to 0–100 at sync time.
        let latestPairs: [(HKQuantityTypeIdentifier, MetricType, HKUnit, Double)] = [
            (.heartRate,              .heartRate,              HKUnit(from: "count/min"),     1),
            (.restingHeartRate,       .restingHeartRate,       HKUnit(from: "count/min"),     1),
            (.bodyMass,               .weight,                 .gramUnit(with: .kilo),        1),
            (.bloodPressureSystolic,  .bloodPressureSystolic,  .millimeterOfMercury(),        1),
            (.bloodPressureDiastolic, .bloodPressureDiastolic, .millimeterOfMercury(),        1),
            (.oxygenSaturation,       .oxygenSaturation,       .percent(),                  100),
            (.bodyFatPercentage,      .bodyFatPercentage,      .percent(),                  100),
            (.vo2Max,                 .vo2Max,                 HKUnit(from: "ml/kg·min"),     1),
            (.bloodGlucose,           .bloodGlucose,           HKUnit(from: "mg/dL"),         1),
            (.heartRateVariabilitySDNN, .heartRateVariability, HKUnit.secondUnit(with: .milli), 1),
            (.respiratoryRate,        .respiratoryRate,        HKUnit(from: "count/min"),     1)
        ]

        for (hkId, metricType, unit, displayScale) in latestPairs {
            if let sample = await fetchLatest(identifier: hkId, unit: unit) {
                let existing = persistence.fetchMetrics(type: metricType, limit: 1).first
                if existing?.recordedAt != sample.date {
                    persistence.insert(HealthMetric(
                        type: metricType,
                        value: sample.value * displayScale,
                        unit: metricType.defaultUnit,
                        recordedAt: sample.date,
                        source: "Apple Health"
                    ))
                }
            }
        }

        // Cumulative metrics - these accumulate throughout the day (steps,
        // active calories, water, food intake). `fetchLatest` would only
        // capture a single sample (e.g. one drink, one snack), missing the
        // rest of the day. Sum from midnight instead and upsert today's row.
        let cumulativePairs: [(HKQuantityTypeIdentifier, MetricType, HKUnit)] = [
            (.stepCount,              .steps,             .count()),
            (.activeEnergyBurned,     .activeEnergy,      .kilocalorie()),
            (.appleExerciseTime,      .exerciseMinutes,   .minute()),
            (.dietaryWater,           .waterIntake,       .literUnit(with: .milli)),
            (.dietaryEnergyConsumed,  .caloriesConsumed,  .kilocalorie()),
            (.dietaryProtein,         .proteinConsumed,   .gram()),
            (.dietaryCarbohydrates,   .carbsConsumed,     .gram()),
            (.dietaryFatTotal,        .fatConsumed,       .gram()),
            (.dietaryFiber,           .fiberConsumed,     .gram())
        ]

        let startOfDay = Calendar.current.startOfDay(for: Date())
        for (hkId, metricType, unit) in cumulativePairs {
            if let total = await todayTotal(identifier: hkId, unit: unit) {
                upsertDailyMetric(type: metricType, value: total, day: startOfDay,
                                  persistence: persistence)
            }
        }

        // Sleep - HKCategoryType, needs duration summed from nightly samples.
        await syncSleep(persistence: persistence)
    }

    /// For cumulative metrics that update throughout the day, replace today's
    /// row in place (instead of inserting another duplicate every sync). The
    /// recordedAt is anchored to startOfDay so successive syncs hit the same
    /// row and the value reflects the latest running total.
    private func upsertDailyMetric(type: MetricType, value: Double, day: Date,
                                   persistence: PersistenceService) {
        let recent = persistence.fetchMetrics(type: type, limit: 1).first
        if let existing = recent, Calendar.current.isDate(existing.recordedAt, inSameDayAs: day) {
            existing.value = value
            existing.recordedAt = day
            persistence.save()
        } else {
            persistence.insert(HealthMetric(
                type: type,
                value: value,
                unit: type.defaultUnit,
                recordedAt: day,
                source: "Apple Health"
            ))
        }
    }

    // MARK: - Sleep

    private func syncSleep(persistence: PersistenceService) async {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        // Look back 2 days to capture the most recent completed night.
        guard let start = Calendar.current.date(byAdding: .day, value: -2, to: Date()) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, result, _ in
                continuation.resume(returning: (result as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        // Sum asleep stages for the most-recent night (midnight boundary).
        let asleepValues: Set<Int> = {
            if #available(iOS 16, *) {
                return [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
            } else {
                return [HKCategoryValueSleepAnalysis.asleep.rawValue]
            }
        }()

        let asleepSamples = samples.filter { asleepValues.contains($0.value) }
        guard !asleepSamples.isEmpty else { return }

        // Group by the wake-day so a single night of sleep that crosses midnight
        // (e.g. 23:00 → 07:00) ends up in one bucket, not two. `endDate` is the
        // moment the user woke; its startOfDay is the "morning of" key.
        var nightlyHours: [Date: Double] = [:]
        for sample in asleepSamples {
            let night = Calendar.current.startOfDay(for: sample.endDate)
            let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
            nightlyHours[night, default: 0] += hours
        }

        // Persist the most recent night if not already stored.
        if let (night, hours) = nightlyHours.max(by: { $0.key < $1.key }) {
            let existing = persistence.fetchMetrics(type: .sleepDuration, limit: 1).first
            if existing?.recordedAt != night {
                persistence.insert(HealthMetric(
                    type: .sleepDuration,
                    value: hours,
                    unit: MetricType.sleepDuration.defaultUnit,
                    recordedAt: night,
                    source: "Apple Health"
                ))
            }
        }
    }

    // MARK: - Background Delivery

    /// Keep observer queries alive for the life of the app. Without a running
    /// `HKObserverQuery`, iOS will never wake us on background data changes -
    /// `enableBackgroundDelivery` alone is insufficient.
    private var observerQueries: [HKObserverQuery] = []

    private func registerBackgroundDelivery() {
        // Tear down any prior observers (defensive - `requestAuthorization`
        // can be called more than once across a session).
        for q in observerQueries { store.stop(q) }
        observerQueries.removeAll()

        let bgIds: [HKQuantityTypeIdentifier] = [.stepCount, .restingHeartRate]
        for id in bgIds {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, error in
#if DEBUG
                if let error { print("Background delivery error for \(id): \(error)") }
#endif
            }
            let observer = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
#if DEBUG
                if let error { print("Observer error for \(id): \(error)") }
#endif
                // HKObserverQueryCompletionHandler isn't declared @Sendable, so
                // Swift flags sending it into the @MainActor Task. HealthKit
                // guarantees the completion handler is safe to invoke from any
                // thread, so wrap it in an @unchecked Sendable box.
                let box = SendableCompletion(handler: completion)
                Task { @MainActor in
                    await self?.syncToLocal()
                    box.handler()
                }
            }
            store.execute(observer)
            observerQueries.append(observer)
        }
    }

    /// Heuristic auth detection. HealthKit never surfaces read-denials through
    /// `requestAuthorization`; the only signals we get are (a) our write-types'
    /// sharing status and (b) whether a read query actually returns a sample.
    /// Either one is enough to confirm at least partial access.
    private func hasAnyAuthorizedData() async -> Bool {
        for writeType in writeTypes {
            if store.authorizationStatus(for: writeType) == .sharingAuthorized { return true }
        }
        // Probe a read-only type that most users have data for. If we get a
        // sample back the user granted read access to at least one category.
        if await fetchLatest(identifier: .stepCount, unit: .count()) != nil { return true }
        if await fetchLatest(identifier: .heartRate, unit: HKUnit(from: "count/min")) != nil { return true }
        return false
    }

    // MARK: - Helpers

    private func fetchLatest(identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> (value: Double, date: Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: nil,
                limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.startDate))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }

    /// Sum of all samples recorded since midnight for a cumulative quantity
    /// (steps, water, active energy, etc.). Returns nil if HealthKit is
    /// unavailable or the query fails.
    func todayTotal(identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: identifier)
        else { return nil }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Pull historical HealthKit samples for slow-changing metrics so Pearl
    /// can reason about trends from day one. Runs after first authorization.
    /// Reads per-sample data (weight, RHR, VO2 max, body fat, HRV) and daily
    /// cumulative totals (steps, active energy, exercise minutes, water,
    /// dietary macros).
    func backfillHistorical(days: Int) async {
        let persistence = PersistenceService.shared

        // Instantaneous metrics - each sample becomes one HealthMetric row.
        let instantaneous: [(HKQuantityTypeIdentifier, MetricType, HKUnit, Double)] = [
            (.bodyMass,                 .weight,               .gramUnit(with: .kilo),        1),
            (.restingHeartRate,         .restingHeartRate,     HKUnit(from: "count/min"),     1),
            (.vo2Max,                   .vo2Max,               HKUnit(from: "ml/kg·min"),     1),
            (.bodyFatPercentage,        .bodyFatPercentage,    .percent(),                  100),
            (.heartRateVariabilitySDNN, .heartRateVariability, .secondUnit(with: .milli),     1),
            (.bloodGlucose,             .bloodGlucose,         HKUnit(from: "mg/dL"),         1),
            (.oxygenSaturation,         .oxygenSaturation,     .percent(),                  100)
        ]

        // Cumulative metrics - one total per day.
        let cumulative: [(HKQuantityTypeIdentifier, MetricType, HKUnit)] = [
            (.stepCount,             .steps,            .count()),
            (.activeEnergyBurned,    .activeEnergy,     .kilocalorie()),
            (.appleExerciseTime,     .exerciseMinutes,  .minute()),
            (.dietaryWater,          .waterIntake,      .literUnit(with: .milli)),
            (.dietaryEnergyConsumed, .caloriesConsumed, .kilocalorie()),
            (.dietaryProtein,        .proteinConsumed,  .gram()),
            (.dietaryCarbohydrates,  .carbsConsumed,    .gram()),
            (.dietaryFatTotal,       .fatConsumed,      .gram()),
            (.dietaryFiber,          .fiberConsumed,    .gram())
        ]

        // Progress is reported across each metric-type "step" (~95% of the
        // total), leaving the final 5% for the sleep-history sweep that runs
        // after this method.
        let totalSteps = Double(instantaneous.count + cumulative.count)
        var completedSteps = 0.0

        // Stage rows per type, commit once per type - avoids the WAL
        // checkpoint storm a per-row save() would cause when backfilling
        // thousands of samples.
        for (hkId, metricType, unit, scale) in instantaneous {
            let samples = await fetchDailySamples(identifier: hkId, unit: unit, days: days)
            if !samples.isEmpty {
                let existing = Set(persistence.fetchMetrics(type: metricType, limit: 5000).map(\.recordedAt))
                var staged = 0
                for s in samples where !existing.contains(s.date) {
                    persistence.stage(HealthMetric(
                        type: metricType,
                        value: s.value * scale,
                        unit: metricType.defaultUnit,
                        recordedAt: s.date,
                        source: "Apple Health"
                    ))
                    staged += 1
                }
                if staged > 0 { persistence.save() }
            }
            completedSteps += 1
            backfillProgress = min(0.95, completedSteps / totalSteps * 0.95)
        }

        let cal = Calendar.current
        for (hkId, metricType, unit) in cumulative {
            let totals = await fetchDailyTotals(identifier: hkId, unit: unit, days: days)
            if !totals.isEmpty {
                let existing = Set(persistence.fetchMetrics(type: metricType, limit: 5000)
                    .map { cal.startOfDay(for: $0.recordedAt) })
                var staged = 0
                for t in totals where !existing.contains(t.day) && t.value > 0 {
                    persistence.stage(HealthMetric(
                        type: metricType,
                        value: t.value,
                        unit: metricType.defaultUnit,
                        recordedAt: t.day,
                        source: "Apple Health"
                    ))
                    staged += 1
                }
                if staged > 0 { persistence.save() }
            }
            completedSteps += 1
            backfillProgress = min(0.95, completedSteps / totalSteps * 0.95)
        }
    }

    // MARK: - Public full-history trigger

    /// User-initiated full backfill. Resets the done flag so it reruns even if
    /// a previous backfill completed, then pulls 5 years of all metric types.
    func triggerFullHistoricalBackfill() {
        guard isAuthorized, !isBackfilling else { return }
        UserDefaults.standard.set(false, forKey: "hkHistoricalBackfillDone_v2")
        Task { [weak self] in
            guard let self else { return }
            self.isBackfilling = true
            self.backfillProgress = 0
            await self.backfillHistorical(days: 1825)
            await self.backfillSleepHistorical(days: 1825)
            self.backfillProgress = 1.0
            // Hold the complete ring on screen for a beat so the user sees it.
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.isBackfilling = false
            self.backfillProgress = 0
            UserDefaults.standard.set(true, forKey: "hkHistoricalBackfillDone_v2")
        }
    }

    // MARK: - Sleep historical backfill

    /// Pull up to `days` of nightly sleep totals and persist one row per night.
    func backfillSleepHistorical(days: Int) async {
        let persistence = PersistenceService.shared
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, result, _ in
                continuation.resume(returning: (result as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleepValues: Set<Int> = {
            if #available(iOS 16, *) {
                return [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
            } else {
                return [HKCategoryValueSleepAnalysis.asleep.rawValue]
            }
        }()

        var nightlyHours: [Date: Double] = [:]
        for sample in samples where asleepValues.contains(sample.value) {
            let night = Calendar.current.startOfDay(for: sample.endDate)
            nightlyHours[night, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
        }

        let existing = Set(persistence.fetchMetrics(type: .sleepDuration, limit: 5000)
            .map { Calendar.current.startOfDay(for: $0.recordedAt) })

        var staged = 0
        for (night, hours) in nightlyHours where !existing.contains(night) && hours > 0 {
            persistence.stage(HealthMetric(
                type: .sleepDuration,
                value: hours,
                unit: MetricType.sleepDuration.defaultUnit,
                recordedAt: night,
                source: "Apple Health"
            ))
            staged += 1
        }
        if staged > 0 { persistence.save() }
        backfillProgress = 1.0
    }

    /// Compute per-day totals for cumulative quantity types (steps, calories,
    /// etc.) using HKStatisticsCollectionQuery with a 1-day interval.
    private func fetchDailyTotals(identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [(day: Date, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return [] }
        let anchor = Calendar.current.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                var out: [(Date, Double)] = []
                results?.enumerateStatistics(from: anchor, to: end) { stats, _ in
                    if let sum = stats.sumQuantity()?.doubleValue(for: unit) {
                        out.append((stats.startDate, sum))
                    }
                }
                continuation.resume(returning: out.map { (day: $0.0, value: $0.1) })
            }
            store.execute(query)
        }
    }

    func fetchDailySamples(identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [(date: Date, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                let results = (samples as? [HKQuantitySample])?.map {
                    (date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                } ?? []
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }
}

/// Thin @unchecked-Sendable wrapper around HealthKit's observer-completion
/// closure so it can cross into a @MainActor Task without tripping Swift 6
/// data-race diagnostics. Safe because HealthKit documents the handler as
/// thread-safe and we invoke it exactly once per observer fire.
private struct SendableCompletion: @unchecked Sendable {
    let handler: HKObserverQueryCompletionHandler
}
