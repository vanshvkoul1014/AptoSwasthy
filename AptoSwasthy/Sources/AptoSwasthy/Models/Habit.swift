import Foundation
import SwiftData

@Model
final class Habit {
    var id: UUID
    var name: String
    var habitDescription: String
    var cadence: HabitCadence
    var targetDays: [Int]
    var isActive: Bool
    var isRetired: Bool
    var startDate: Date
    var retiredDate: Date?
    var completions: [Date]
    var formationDays: Int
    var category: HabitCategory
    var pearlRationale: String
    var checkInScheduled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        habitDescription: String,
        cadence: HabitCadence = .daily,
        targetDays: [Int] = [],
        isActive: Bool = true,
        isRetired: Bool = false,
        startDate: Date = Date(),
        retiredDate: Date? = nil,
        completions: [Date] = [],
        formationDays: Int = 66,
        category: HabitCategory,
        pearlRationale: String = "",
        checkInScheduled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.habitDescription = habitDescription
        self.cadence = cadence
        self.targetDays = targetDays
        self.isActive = isActive
        self.isRetired = isRetired
        self.startDate = startDate
        self.retiredDate = retiredDate
        self.completions = completions
        self.formationDays = formationDays
        self.category = category
        self.pearlRationale = pearlRationale
        self.checkInScheduled = checkInScheduled
    }

    var daysSinceStart: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
    }

    /// Clamped to [0, 1]. Guards against a future-dated startDate (clock
    /// skew or a corrupted record) that would otherwise produce a negative
    /// bar width and trigger "Invalid frame dimension" warnings.
    var formationProgress: Double {
        guard formationDays > 0 else { return 1.0 }
        let raw = Double(daysSinceStart) / Double(formationDays)
        return min(max(raw, 0), 1.0)
    }

    var isReadyToRetire: Bool {
        formationProgress >= 1.0
    }

    var isCompletedToday: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return completions.contains { Calendar.current.startOfDay(for: $0) == today }
    }

    func markComplete() {
        if !isCompletedToday {
            completions.append(Date())
            // SwiftData auto-saves when the context is saved by the caller.
            // Explicit save handled at call sites (HomeViewModel, HabitDashboard).
        }
    }

    /// If the habit name encodes a measurable daily target (e.g. "Walk 8,000 steps",
    /// "Drink 8 glasses of water", "7–9 hours of sleep"), returns the metric to
    /// read and the threshold to consider the habit completed. Returns nil for
    /// habits that can't be auto-evaluated from metric data (meditation, logging,
    /// medication adherence, etc.).
    var autoCompletionTarget: (MetricType, Double)? {
        let n = name.lowercased()

        // Walk / steps - extract the first contiguous digit run then check for
        // a trailing "k" multiplier ("10k steps" → 10000, "8,000 steps" → 8000).
        if n.contains("step") {
            let target = Self.extractFirstNumber(from: n) ?? 8000
            return (.steps, max(target, 1000))
        }

        // Water - "8 glasses" ≈ 2000 ml. Accept "water" or "glasses".
        if n.contains("water") || n.contains("glass") {
            return (.waterIntake, 2000)
        }

        // Sleep - "7–9 hours of sleep" / "7 hours". Use 7 as the lower bound.
        if n.contains("sleep") && n.contains("hour") {
            return (.sleepDuration, 7)
        }

        return nil
    }

    /// Extract the first number from a lowercased string, handling comma
    /// separators ("8,000") and "k" suffix ("10k" → 10000).
    private static func extractFirstNumber(from text: String) -> Double? {
        // Strip commas so "8,000" becomes "8000"
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        // Match a digit run optionally followed by 'k'
        let pattern = try? NSRegularExpression(pattern: #"(\d+)(k)?"#)
        guard let match = pattern?.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let numRange = Range(match.range(at: 1), in: cleaned),
              let value = Double(cleaned[numRange])
        else { return nil }
        let hasK = match.range(at: 2).location != NSNotFound
        return hasK ? value * 1000 : value
    }
}

enum HabitCadence: String, Codable, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
}

enum HabitCategory: String, Codable, CaseIterable {
    case activity = "Activity"
    case nutrition = "Nutrition"
    case sleep = "Sleep"
    case mindfulness = "Mindfulness"
    case hydration = "Hydration"
    case medical = "Medical"
    case social = "Social"
}
