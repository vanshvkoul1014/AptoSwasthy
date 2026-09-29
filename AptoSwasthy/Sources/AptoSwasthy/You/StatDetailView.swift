import SwiftUI
import Charts

enum StatKind: String, Identifiable {
    case height, weight, bmi, muscle, fitness, bodyFat
    var id: String { rawValue }

    var title: String {
        switch self {
        case .height: return "Height"
        case .weight: return "Weight"
        case .bmi: return "BMI"
        case .muscle: return "Muscle Mass"
        case .fitness: return "Fitness Score"
        case .bodyFat: return "Body Fat"
        }
    }

    var icon: String {
        switch self {
        case .height: return "ruler"
        case .weight: return "scalemass"
        case .bmi: return "figure"
        case .muscle: return "figure.strengthtraining.traditional"
        case .fitness: return "heart.fill"
        case .bodyFat: return "drop.fill"
        }
    }
}

struct StatDetailView: View {
    let kind: StatKind
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @State private var range: StatRange = .month

    enum StatRange: String, CaseIterable {
        case month = "1M", sixMonths = "6M", year = "1Y", allTime = "All"
        var days: Int? {
            switch self {
            case .month: return 30
            case .sixMonths: return 182
            case .year: return 365
            case .allTime: return nil
            }
        }
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if chartPoints.count >= 2 {
                        rangePicker
                        chart
                            .frame(height: 240)
                        summaryCard
                    } else {
                        emptyOrStaticCard
                    }
                    explanation
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: kind.icon)
                        .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(kind.title).font(.pearlTitle2).foregroundColor(.primaryText)
                }
                Text(currentValueString)
                    .font(.pearlNumber)
                    .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundColor(.quaternaryText)
            }
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 8) {
            ForEach(StatRange.allCases, id: \.self) { r in
                Button {
                    range = r
                } label: {
                    Text(r.rawValue)
                        .font(.pearlCaption.weight(range == r ? .semibold : .regular))
                        .foregroundColor(range == r ? .primaryText : .tertiaryText)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(range == r ? Color.pearlGreen.opacity(0.18) : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chart: some View {
        Chart(chartPoints, id: \.date) { p in
            LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
                .interpolationMethod(.monotone)
            AreaMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .foregroundStyle(
                    LinearGradient(colors: [.pearlGreen.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .foregroundStyle(.pearlGreen)
                .symbolSize(24)
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel().foregroundStyle(Color.tertiaryText)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.05))
                AxisValueLabel().foregroundStyle(Color.tertiaryText)
            }
        }
    }

    @ViewBuilder
    private var summaryCard: some View {
        if let first = chartPoints.first, let last = chartPoints.last {
        let delta = last.value - first.value
        let pct = first.value != 0 ? (delta / first.value) * 100 : 0
        let sign = delta >= 0 ? "+" : ""
        let tint: Color = isImprovement(delta: delta) ? .riskLow : (abs(pct) < 1 ? .tertiaryText : .riskHigh)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Over the selected range").font(.pearlCaption).foregroundColor(.tertiaryText)
                Text("\(sign)\(String(format: "%.1f", delta)) \(unit)")
                    .font(.pearlTitle3).foregroundColor(tint)
                Text("\(sign)\(String(format: "%.1f", pct))% since start")
                    .font(.pearlCaption2).foregroundColor(.quaternaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(chartPoints.count) readings")
                    .font(.pearlCaption).foregroundColor(.tertiaryText)
            }
        }
        .padding(14)
        .glassBackground(cornerRadius: 14)
        } // end if let first, last
    }

    private var emptyOrStaticCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.tertiaryText)
            Text(emptyMessage)
                .font(.pearlSubheadline)
                .foregroundColor(.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .glassBackground(cornerRadius: 16)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How this is calculated").font(.pearlHeadline).foregroundColor(.primaryText)
            Text(explanationText)
                .font(.pearlCaption)
                .foregroundColor(.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassBackground(cornerRadius: 14)
    }

    // MARK: - Data

    private var allWeights: [(Date, Double)] {
        PersistenceService.shared.fetchMetrics(type: .weight, limit: 5000)
            .sorted { $0.recordedAt < $1.recordedAt }
            .map { ($0.recordedAt, $0.value) }
    }

    private var allBodyFats: [(Date, Double)] {
        PersistenceService.shared.fetchMetrics(type: .bodyFatPercentage, limit: 5000)
            .sorted { $0.recordedAt < $1.recordedAt }
            .map {
                let v = $0.value <= 1 ? $0.value * 100 : $0.value
                return ($0.recordedAt, v)
            }
    }

    private var chartPoints: [ChartPoint] {
        let cutoff: Date? = range.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
        let raw: [(Date, Double)] = {
            switch kind {
            case .weight:
                return profile.unitPreference == .imperial
                    ? allWeights.map { ($0.0, $0.1 * 2.20462) }
                    : allWeights
            case .bmi:
                let h = profile.heightCm / 100
                return allWeights.map { ($0.0, $0.1 / (h * h)) }
            case .bodyFat:
                return allBodyFats
            case .height, .muscle, .fitness:
                return []
            }
        }()
        let filtered = cutoff.map { c in raw.filter { $0.0 >= c } } ?? raw
        return filtered.map { ChartPoint(date: $0.0, value: $0.1) }
    }

    private var currentValueString: String {
        switch kind {
        case .height:
            return profile.unitPreference == .imperial ? profile.heightFeetString : "\(Int(profile.heightCm)) cm"
        case .weight:
            return profile.unitPreference == .imperial ? "\(Int(profile.weightLbs)) lb" : "\(Int(profile.weightKg)) kg"
        case .bmi:
            return String(format: "%.1f", profile.bmi)
        case .muscle:
            return "\(Int(BodyShapeMapper.estimatedMuscleMassPercent(for: profile)))%"
        case .fitness:
            let allMetrics = PersistenceService.shared.fetchMetrics(limit: 500)
            let score = computeFitnessScore(profile: profile, metrics: allMetrics)
            return score > 0 ? "\(Int(score))" : "-"
        case .bodyFat:
            if let last = chartPoints.last { return String(format: "%.0f%%", last.value) }
            let allMetrics = PersistenceService.shared.fetchMetrics(limit: 500)
            return String(format: "~%.0f%%", estimateBodyFat(profile: profile, metrics: allMetrics))
        }
    }

    private var unit: String {
        switch kind {
        case .weight: return profile.unitPreference == .imperial ? "lb" : "kg"
        case .bmi: return ""
        case .bodyFat: return "%"
        default: return ""
        }
    }

    private var emptyMessage: String {
        switch kind {
        case .height:
            return "Height is static. Update it in Personal Details if it's wrong."
        case .weight:
            return "Log your weight (Home tab or Apple Health) and a trend will appear here."
        case .bmi:
            return "BMI charts automatically once you have weight readings logged."
        case .muscle:
            return "Muscle mass is estimated from activity, age, sex, and BMI. It updates as those values change."
        case .fitness:
            return "Fitness score is a composite of VO2 max, resting heart rate, activity level, and BMI. Log any of those to see a score."
        case .bodyFat:
            return "Log body fat directly (smart scale / HealthKit) or the estimate will move with your weight."
        }
    }

    private var explanationText: String {
        switch kind {
        case .height:
            return "Height is entered during onboarding and doesn't change automatically."
        case .weight:
            return "Pulled from every weight reading logged manually or via Apple Health. The line smooths between points; individual dots are the actual readings."
        case .bmi:
            return "BMI = weight (kg) / height² (m). Height is fixed from your profile, so the curve tracks weight directly."
        case .muscle:
            return "Estimated from a baseline (sex-typical) then adjusted for activity level, age (lean mass drifts ~1.5% per decade after 30), and BMI. Logging a body fat reading gives a better estimate."
        case .fitness:
            return "Weighted composite: VO2 max, resting heart rate, self-reported activity, and BMI category. Sub-scores each contribute points to a 0–100 scale."
        case .bodyFat:
            return "Uses directly logged body fat readings when available. Without a reading, falls back to the Deurenberg formula: 1.20×BMI + 0.23×age − 10.8×sex − 5.4."
        }
    }

    private func computeFitnessScore(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        var score = 50.0
        if let vo2 = metrics.filter({ $0.type == .vo2Max }).sorted(by: { $0.recordedAt > $1.recordedAt }).first?.value { score += min((vo2 - 30) / 30 * 20, 20) }
        if let rhr = metrics.filter({ $0.type == .restingHeartRate }).sorted(by: { $0.recordedAt > $1.recordedAt }).first?.value { score += rhr < 60 ? 15 : rhr < 70 ? 10 : rhr < 80 ? 5 : 0 }
        switch profile.activityLevel { case .sedentary: score -= 10; case .lightlyActive: score += 0; case .moderatelyActive: score += 10; case .veryActive: score += 15; case .extremelyActive: score += 18 }
        switch profile.bmiCategory { case .normal: score += 5; case .underweight: score -= 5; case .overweight: score -= 5; case .obese: score -= 15 }
        return max(0, min(100, score))
    }

    private func estimateBodyFat(profile: UserProfile, metrics: [HealthMetric]) -> Double {
        if let logged = metrics.filter({ $0.type == .bodyFatPercentage }).sorted(by: { $0.recordedAt > $1.recordedAt }).first?.value {
            let pct = logged <= 1.0 ? logged * 100.0 : logged
            return max(5, min(pct, 60))
        }
        let bf = (1.20 * profile.bmi) + (0.23 * Double(profile.age)) - (10.8 * (profile.biologicalSex == .male ? 1 : 0)) - 5.4
        return max(5, min(bf, 60))
    }

    private func isImprovement(delta: Double) -> Bool {
        switch kind {
        case .weight, .bmi, .bodyFat:
            return delta < 0 && profile.bmi > 24.9
        case .fitness, .muscle:
            return delta > 0
        case .height:
            return false
        }
    }
}

