import Foundation
import SwiftData

@MainActor
final class PersistenceService {
    static let shared = PersistenceService()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            UserProfile.self,
            HealthMetric.self,
            Habit.self,
            Meal.self,
            FoodEntry.self,
            DiseaseRisk.self,
            ConversationMessage.self,
            BloodTest.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // Migration failed (usually a non-lightweight schema change). Destroy
            // the existing store and start fresh rather than crash. Health data
            // from Apple Health will re-sync on next launch.
            #if DEBUG
            print("[PersistenceService] Migration failed, resetting store: \(error)")
            #endif
            let fallbackConfig = ModelConfiguration(schema: schema,
                                                    isStoredInMemoryOnly: false,
                                                    allowsSave: true)
            do {
                // Delete the existing store file so SwiftData can create a clean one.
                try? FileManager.default.removeItem(at: fallbackConfig.url)
                container = try ModelContainer(for: schema, configurations: fallbackConfig)
            } catch {
                // Absolute last resort - in-memory only so app stays runnable.
                let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try! ModelContainer(for: schema, configurations: memConfig)
            }
        }
    }

    var context: ModelContext { container.mainContext }

    func fetchProfile() -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        return try? context.fetch(descriptor).first
    }

    func fetchMetrics(type: MetricType? = nil, limit: Int = 100) -> [HealthMetric] {
        // Note: SwiftData's #Predicate returns an empty set when filtering on
        // an enum-typed property on several SDK versions, which makes the
        // type-filtered branch silently lose data. Do the fetch unfiltered,
        // then filter client side. We fetch a generous window so that when a
        // caller requests N rows of a specific type, we don't run out of
        // candidates after other-type rows are filtered out.
        var descriptor = FetchDescriptor<HealthMetric>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        if type == nil {
            descriptor.fetchLimit = limit
            return (try? context.fetch(descriptor)) ?? []
        }
        // Overscan so older rows of the requested type aren't pushed past
        // the limit by unrelated newer rows. Cap at 20k to bound memory.
        descriptor.fetchLimit = min(max(limit * 20, 500), 20000)
        let all = (try? context.fetch(descriptor)) ?? []
        let filtered = all.filter { $0.type == type }
        return Array(filtered.prefix(limit))
    }

    func fetchTodayMeals() -> [Meal] {
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = #Predicate<Meal> { meal in
            meal.loggedAt >= start && meal.loggedAt < end
        }
        let descriptor = FetchDescriptor<Meal>(predicate: predicate, sortBy: [SortDescriptor(\.loggedAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchMeals(from start: Date, to end: Date) -> [Meal] {
        let predicate = #Predicate<Meal> { meal in
            meal.loggedAt >= start && meal.loggedAt < end
        }
        let descriptor = FetchDescriptor<Meal>(predicate: predicate, sortBy: [SortDescriptor(\.loggedAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchActiveHabits() -> [Habit] {
        let predicate = #Predicate<Habit> { habit in
            habit.isActive && !habit.isRetired
        }
        return (try? context.fetch(FetchDescriptor<Habit>(predicate: predicate))) ?? []
    }

    func fetchLatestBloodTests() -> [BloodTest] {
        let descriptor = FetchDescriptor<BloodTest>(
            sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchRisks() -> [DiseaseRisk] {
        (try? context.fetch(FetchDescriptor<DiseaseRisk>())) ?? []
    }

    func fetchConversationHistory() -> [ConversationMessage] {
        let descriptor = FetchDescriptor<ConversationMessage>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func save() {
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("[PersistenceService] save failed: \(error)")
            #endif
        }
    }

    func insert<T: PersistentModel>(_ model: T) {
        context.insert(model)
        save()
    }

    /// Insert without committing to disk. Caller is responsible for calling
    /// save() once the batch is complete. Use this for bulk imports (HealthKit
    /// historical backfill, large CSV imports) where per-row `insert()` would
    /// hammer the WAL with hundreds of checkpoints.
    func stage<T: PersistentModel>(_ model: T) {
        context.insert(model)
    }

    func delete<T: PersistentModel>(_ model: T) {
        context.delete(model)
        save()
    }

    func clearRisks() {
        let existing = fetchRisks()
        existing.forEach { context.delete($0) }
        save()
    }

    /// Wipes all persisted user data - called on logout to prevent data leakage
    /// if a different user signs in on the same device.
    func deleteAllUserData() {
        try? context.delete(model: UserProfile.self)
        try? context.delete(model: HealthMetric.self)
        try? context.delete(model: Habit.self)
        try? context.delete(model: Meal.self)
        try? context.delete(model: FoodEntry.self)
        try? context.delete(model: DiseaseRisk.self)
        try? context.delete(model: ConversationMessage.self)
        try? context.delete(model: BloodTest.self)
        save()
        UserDefaults.standard.removeObject(forKey: "hkHistoricalBackfillDone")
        UserDefaults.standard.removeObject(forKey: "firstSnapshotShown")
    }

    // MARK: - Cloud merge helpers

    /// Overwrite the local profile with fields from a cloud DTO, or insert a
    /// new one if no local profile exists. Preserves on-device-only flags
    /// (faceIDEnabled is a per-device preference, not a cloud field).
    @discardableResult
    func upsertProfile(from dto: ProfileDTO) -> UserProfile {
        if let existing = fetchProfile() {
            existing.name = dto.name
            existing.dateOfBirth = dto.dateOfBirth
            existing.biologicalSex = BiologicalSex(rawValue: dto.biologicalSex) ?? existing.biologicalSex
            existing.ethnicity = Ethnicity(rawValue: dto.ethnicity) ?? existing.ethnicity
            existing.heightCm = dto.heightCm
            existing.weightKg = dto.weightKg
            existing.activityLevel = ActivityLevel(rawValue: dto.activityLevel) ?? existing.activityLevel
            existing.activityMinutesPerSession = dto.activityMinutesPerSession
            existing.sleepBedtime = dto.sleepBedtime
            existing.sleepWakeTime = dto.sleepWakeTime
            existing.sleepHoursPerNight = dto.sleepHoursPerNight
            existing.healthConditions = dto.healthConditions
            existing.medications = dto.medications
            existing.familyHistory = dto.familyHistory
            existing.smokingStatus = SmokingStatus(rawValue: dto.smokingStatus) ?? existing.smokingStatus
            existing.alcoholFrequency = AlcoholFrequency(rawValue: dto.alcoholFrequency) ?? existing.alcoholFrequency
            existing.healthGoals = dto.healthGoals.compactMap { HealthGoal(rawValue: $0) }
            existing.unitPreference = UnitSystem(rawValue: dto.unitPreference) ?? existing.unitPreference
            existing.onboardingComplete = dto.onboardingComplete
            existing.connectedApps = dto.connectedApps
            save()
            return existing
        } else {
            let fresh = dto.toUserProfile()
            insert(fresh)
            return fresh
        }
    }

    /// Add an app to the profile's connectedApps list (no-op if already present).
    /// Saves locally - caller is responsible for pushing to cloud if desired.
    func markAppConnected(_ appName: String) {
        guard let profile = fetchProfile() else { return }
        if !profile.connectedApps.contains(appName) {
            profile.connectedApps.append(appName)
            save()
        }
    }
}
