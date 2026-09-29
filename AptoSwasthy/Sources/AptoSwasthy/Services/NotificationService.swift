import Foundation
import UserNotifications

final class NotificationService: @unchecked Sendable {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func scheduleHabitReminder(habit: Habit, at time: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Pearl"
        content.body = "Time for '\(habit.name)'. Small steps compound into big changes."
        content.sound = .default

        let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "habit-\(habit.id.uuidString)",
            content: content,
            trigger: trigger
        )
        // Remove any existing reminder for this habit before adding a new one
        // so we never end up with duplicate notifications for the same habit.
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        center.add(request)
    }

    func cancelHabitReminder(habit: Habit) {
        center.removePendingNotificationRequests(withIdentifiers: ["habit-\(habit.id.uuidString)"])
    }

    func scheduleMetricAlert(type: MetricType, message: String, after delay: TimeInterval = 1) {
        let content = UNMutableNotificationContent()
        content.title = "Pearl noticed something"
        content.body = message
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let request = UNNotificationRequest(
            identifier: "metric-\(type.rawValue)",
            content: content,
            trigger: trigger
        )
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        center.add(request)
    }

    func sendRiskAlert(condition: RiskCondition, tier: RiskTier) {
        guard tier == .high else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your \(condition.rawValue) risk changed"
        content.body = "Pearl updated your risk assessment after reviewing your new data. Tap to see what's driving it and what you can do."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(
            identifier: "risk-\(condition.rawValue)",
            content: content,
            trigger: trigger
        )
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        center.add(request)
    }

    func sendEncouragement(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Pearl"
        content.body = message
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "encourage-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - Re-engagement (72-hour inactivity hook)

    private let reEngagementId = "pearl-reengage-72h"

    /// Schedule a personalized nudge for 72 hours from now. Cancel on next foreground.
    func scheduleReEngagementNotification() {
        let message = UserDefaults.standard.string(forKey: "pearl_reengage_message")
            ?? "Pearl has new insights about your health data. Tap to see what changed."
        let content = UNMutableNotificationContent()
        content.title = "Pearl"
        content.body  = message
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 72 * 3600, repeats: false)
        let request = UNNotificationRequest(identifier: reEngagementId, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [reEngagementId])
        center.add(request)
    }

    func cancelReEngagementNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [reEngagementId])
    }

    func checkAndAlertMetrics(profile: UserProfile, metrics: [HealthMetric]) {
        // Weight: >5% shift in 7 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentWeights = metrics.filter { $0.type == .weight }
            .filter { $0.recordedAt >= cutoff }
            .sorted { $0.recordedAt < $1.recordedAt }

        if recentWeights.count >= 2,
           let first = recentWeights.first?.value,
           let last = recentWeights.last?.value,
           first > 0,
           abs((last - first) / first) > 0.05 {
            let direction = last > first ? "increased" : "decreased"
            scheduleMetricAlert(type: .weight, message: "Your weight has \(direction) by more than 5% this week. Pearl has updated your models.")
        }

        // Resting heart rate: 20% above 3-day baseline
        let rhrMetrics = metrics.filter { $0.type == .restingHeartRate }
        if let recentCutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()),
           let baselineCutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) {
            let recent3 = rhrMetrics.filter { $0.recordedAt >= recentCutoff }
            let baseline3 = rhrMetrics.filter { $0.recordedAt >= baselineCutoff && $0.recordedAt < recentCutoff }
            if !recent3.isEmpty && !baseline3.isEmpty {
                let avgRecent = recent3.map(\.value).reduce(0, +) / Double(recent3.count)
                let avgBaseline = baseline3.map(\.value).reduce(0, +) / Double(baseline3.count)
                if avgRecent > avgBaseline * 1.2 {
                    scheduleMetricAlert(type: .restingHeartRate, message: "Your resting heart rate has been elevated for 3 consecutive days. This can be a sign of stress, illness, or overtraining. Pearl recommends rest and monitoring.")
                }
            }
        }

        // Sleep: <6 hours for 4 consecutive days
        let sleepCutoff = Calendar.current.date(byAdding: .day, value: -4, to: Date()) ?? Date()
        let recentSleep = metrics.filter { $0.type == .sleepDuration }
            .filter { $0.recordedAt >= sleepCutoff }
        if recentSleep.count >= 4 && recentSleep.allSatisfy({ $0.value < 6 }) {
            scheduleMetricAlert(type: .sleepDuration, message: "You've slept under 6 hours for 4 nights in a row. Sleep deprivation compounds quickly. Pearl has updated your risk models accordingly.")
        }
    }
}
