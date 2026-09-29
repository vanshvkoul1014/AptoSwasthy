import SwiftUI
import Charts

struct ChartPoint: Identifiable {
    // Using the date itself as the ID lets the Chart diff properly across
    // time-range changes (a fresh fetch produces the same-date points again,
    // so Swift Charts sees them as the same series and animates cleanly
    // instead of re-keying on random UUIDs each render).
    var id: Date { date }
    let date: Date
    let value: Double
}

struct MetricDetailView: View {
    let metricType: MetricType
    var vm: HomeViewModel

    @State private var timeRange: TimeRange = .month
    @State private var pearlReportText: String = ""
    @State private var allPoints: [ChartPoint] = []
    @State private var hasAnyData: Bool = false
    @State private var isLoading: Bool = true
    @Environment(\.dismiss) private var dismiss

    enum TimeRange: String, CaseIterable {
        case week = "1W"
        case twoWeeks = "2W"
        case month = "1M"
        case sixMonths = "6M"
        case year = "1Y"
        case allTime = "All"

        var days: Int? {
            switch self {
            case .week: return 7
            case .twoWeeks: return 14
            case .month: return 30
            case .sixMonths: return 182
            case .year: return 365
            case .allTime: return nil
            }
        }
    }

    private var isScoreType: Bool {
        metricType == .nutritionScore || metricType == .recoveryScore || metricType == .stressScore
    }

    /// Filter the cached series by the current range. No I/O here so the
    /// picker tap feels instant - the underlying fetch happens once per
    /// metric type in `loadSeries()` and gets re-sliced locally.
    private var filteredData: [ChartPoint] {
        guard let days = timeRange.days else { return allPoints }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return allPoints }
        return allPoints.filter { $0.date >= cutoff }
    }

    private var latestPoint: ChartPoint? { filteredData.last ?? allPoints.last }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: metricType.icon)
                                    .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing))
                                Text(metricType.rawValue)
                                    .font(.pearlTitle2).foregroundColor(.primaryText)
                            }
                            if let latest = latestPoint {
                                Text(formatValue(latest.value))
                                    .font(.pearlNumber)
                                    .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
                            }
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.quaternaryText)
                        }
                    }

                    // Time range picker
                    Picker("Time Range", selection: $timeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Chart
                    if isLoading {
                        VStack(spacing: 8) {
                            ProgressView().tint(.pearlGreen)
                            Text("Loading…")
                                .font(.pearlCaption)
                                .foregroundColor(.quaternaryText)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .glassCard()
                    } else if filteredData.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 28))
                                .foregroundColor(.quaternaryText)
                            Text(hasAnyData ? "No data in this range" : "No data yet")
                                .font(.pearlSubheadline)
                                .foregroundColor(.tertiaryText)
                            Text(hasAnyData ? "Try a longer time range." : emptyHint)
                                .font(.pearlCaption)
                                .foregroundColor(.quaternaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .glassCard()
                    } else {
                        Chart {
                            ForEach(filteredData) { point in
                                LineMark(
                                    x: .value("Date", point.date),
                                    y: .value(metricType.rawValue, point.value)
                                )
                                .foregroundStyle(Color.pearlGreen)
                                .interpolationMethod(filteredData.count > 60 ? .linear : .catmullRom)

                                AreaMark(
                                    x: .value("Date", point.date),
                                    y: .value(metricType.rawValue, point.value)
                                )
                                .foregroundStyle(LinearGradient(
                                    colors: [Color.pearlGreen.opacity(0.3), Color.clear],
                                    startPoint: .top, endPoint: .bottom
                                ))
                                .interpolationMethod(filteredData.count > 60 ? .linear : .catmullRom)
                            }
                        }
                        .frame(height: 220)
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.glassBorder)
                                AxisValueLabel().foregroundStyle(Color.tertiaryText)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.glassBorder)
                                AxisValueLabel().foregroundStyle(Color.tertiaryText)
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: timeRange)
                        .padding()
                        .glassBackground(cornerRadius: 20)
                    }

                    // Pearl report
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.pearlGreen)
                            Text("Pearl's take").font(.pearlHeadline).foregroundColor(.primaryText)
                        }
                        Text(pearlReportText)
                            .font(.pearlBody)
                            .foregroundColor(.secondaryText)
                            .lineSpacing(5)
                    }
                    .glassCard()

                    Spacer(minLength: 60)
                }
                .padding(20)
            }
        }
        .presentationDetents([.large])
        .task {
            await loadSeries()
            let engine = PearlConversation()
            pearlReportText = engine.generatePublicReport(for: metricType, metrics: vm.metrics, profile: vm.profile)
        }
    }

    /// Load the full series once (up to 5 years of rows for this metric type)
    /// and store in @State. Picker changes slice this in-memory, no re-query.
    @MainActor
    private func loadSeries() async {
        isLoading = true
        defer { isLoading = false }
        if isScoreType {
            // Score types have no persisted rows; derive the series from the
            // source metrics up to the widest range so range changes can
            // slice in-memory.
            let points = vm.scoreSeries(for: metricType, days: 365 * 5)
            allPoints = points
            hasAnyData = !points.isEmpty
            return
        }
        // PersistenceService.fetchMetrics handles the type filter safely
        // (client-side) so we can request a generous window directly.
        let matching = PersistenceService.shared
            .fetchMetrics(type: metricType, limit: 20000)
            .sorted { $0.recordedAt < $1.recordedAt }
        allPoints = matching.map { ChartPoint(date: $0.recordedAt, value: $0.value) }
        hasAnyData = !allPoints.isEmpty
    }

    private var emptyHint: String {
        switch metricType {
        case .nutritionScore: return "Log your meals and this chart will populate."
        case .recoveryScore, .stressScore: return "Connect Apple Health for sleep, HRV, and heart rate. Scores will populate as data syncs."
        default: return "Connect Apple Health or add a manual entry to see data here."
        }
    }

    private func formatValue(_ v: Double) -> String {
        switch metricType {
        case .steps: return "\(Int(v).formatted())"
        case .weight:
            if vm.profile?.unitPreference == .imperial { return String(format: "%.1f lb", v * 2.20462) }
            return String(format: "%.1f kg", v)
        case .restingHeartRate, .heartRate: return "\(Int(v)) bpm"
        case .sleepDuration: return String(format: "%.1f h", v)
        case .nutritionScore, .recoveryScore, .stressScore: return "\(Int(v))/100"
        default: return String(format: "%.1f %@", v, metricType.defaultUnit)
        }
    }
}

extension PearlConversation {
    func generatePublicReport(for type: MetricType, metrics: [HealthMetric], profile: UserProfile?) -> String {
        // Score types don't have persisted HealthMetric rows; generate a
        // structural explanation of the inputs instead.
        switch type {
        case .stressScore:
            return stressReport(metrics: metrics, profile: profile)
        case .recoveryScore:
            return recoveryReport(metrics: metrics, profile: profile)
        case .nutritionScore:
            return "Nutrition score blends caloric balance vs your TDEE, protein adequacy (0.8–1.6 g/kg), fiber vs target, fat share of calories, and meal variety. Tap the score card above the chart for the full breakdown."
        default:
            break
        }

        let relevant = metrics.filter { $0.type == type }.sorted { $0.recordedAt < $1.recordedAt }
        guard !relevant.isEmpty else {
            return "No data yet for \(type.rawValue). Connect Apple Health or log manually and I'll generate a full report."
        }

        guard let latest = relevant.last?.value, let oldest = relevant.first?.value else {
            return "No data yet for \(type.rawValue)."
        }
        let trend = latest > oldest ? "up" : latest < oldest ? "down" : "stable"

        switch type {
        case .steps:
            return "Your step count is trending \(trend). \(latest >= 8000 ? "You're hitting the 8,000-step threshold associated with significant longevity benefit." : "Aim for 8,000+ steps daily. Even 1,000 extra steps reduces all-cause mortality risk.")"
        case .restingHeartRate:
            return "Resting heart rate of \(Int(latest)) bpm. \(latest < 60 ? "Excellent. This reflects strong cardiovascular efficiency." : latest < 80 ? "This is in a healthy range." : "Slightly elevated. Regular aerobic exercise is the most effective way to lower RHR over time.")"
        case .weight:
            return "Weight is trending \(trend). \(trend == "down" && profile != nil ? "Progress toward a healthier BMI reduces risk for cardiovascular disease, diabetes, and several cancers." : "")"
        case .sleepDuration:
            return "Sleep duration trending \(trend). \(latest < 7 ? "Under 7 hours is associated with increased risk for metabolic and cardiovascular conditions. Prioritizing sleep is one of the highest-ROI health behaviors." : "You're in the optimal 7–9 hour range. Consistent sleep timing matters as much as duration.")"
        case .bloodPressureSystolic:
            return "Systolic BP of \(Int(latest)) mmHg. \(latest < 120 ? "Optimal." : latest < 130 ? "Elevated, worth monitoring." : "This is in the hypertensive range. Diet, exercise, and stress reduction can each move this number meaningfully.")"
        default:
            return "Your \(type.rawValue) is currently \(String(format: "%.1f", latest)) \(type.defaultUnit). Trend: \(trend)."
        }
    }

    private func stressReport(metrics: [HealthMetric], profile: UserProfile?) -> String {
        let rhr = latest(.restingHeartRate, metrics)
        let hrv = latest(.heartRateVariability, metrics)
        let sleep = latest(.sleepDuration, metrics)
        let steps = latest(.steps, metrics)

        var lines = ["Stress blends four autonomic signals, each pulled straight from your recent data:"]
        lines.append("• HRV (35%): \(hrv.map { "\(Int($0)) ms" } ?? "no reading yet"), the most sensitive stress marker.")
        lines.append("• Resting HR (30%): \(rhr.map { "\(Int($0)) bpm" } ?? "no reading yet"). Elevations above baseline signal strain.")
        lines.append("• Sleep (25%): \(sleep.map { String(format: "%.1f h", $0) } ?? "no reading yet"). Deficit drives sympathetic tone within days.")
        lines.append("• Activity (10%): \(steps.map { "\(Int($0)) steps" } ?? "no reading yet"). Sustained low movement adds physiological stress.")
        lines.append("")
        lines.append("Lower is better. Gaps above just mean that component falls back to neutral in the calculation.")
        return lines.joined(separator: "\n")
    }

    private func recoveryReport(metrics: [HealthMetric], profile: UserProfile?) -> String {
        let rhr = latest(.restingHeartRate, metrics)
        let hrv = latest(.heartRateVariability, metrics)
        let sleep = latest(.sleepDuration, metrics)

        var lines = ["Recovery reflects how ready your body is for load today. Three inputs drive it:"]
        lines.append("• HRV: \(hrv.map { "\(Int($0)) ms" } ?? "no reading yet"), the most direct recovery marker.")
        lines.append("• Resting HR: \(rhr.map { "\(Int($0)) bpm" } ?? "no reading yet"). Lower than baseline is a green light.")
        lines.append("• Sleep: \(sleep.map { String(format: "%.1f h", $0) } ?? "no reading yet"), the single biggest modifiable factor.")
        lines.append("")
        lines.append("Higher is better. Consistency across days matters more than any one reading.")
        return lines.joined(separator: "\n")
    }

    private func latest(_ type: MetricType, _ metrics: [HealthMetric]) -> Double? {
        metrics.filter { $0.type == type }.sorted { $0.recordedAt > $1.recordedAt }.first?.value
    }
}
