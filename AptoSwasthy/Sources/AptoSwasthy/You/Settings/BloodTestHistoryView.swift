import SwiftUI
import Charts

struct BloodTestHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tests: [BloodTest] = []
    @State private var selectedPanel: BloodTest? = nil
    @State private var trendingBiomarker: String? = nil

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("Blood Test History").font(.pearlTitle2).foregroundColor(.primaryText)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundColor(.quaternaryText)
                    }
                }
                .padding(20)

                if tests.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !uniqueBiomarkerNames.isEmpty {
                                Text("Trends")
                                    .font(.pearlHeadline).foregroundColor(.primaryText)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(uniqueBiomarkerNames, id: \.self) { name in
                                            Button {
                                                trendingBiomarker = name
                                            } label: {
                                                Text(name)
                                                    .font(.pearlCaption)
                                                    .foregroundColor(.primaryText)
                                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                                    .glassBackground(cornerRadius: 10)
                                            }
                                        }
                                    }
                                }
                            }

                            Text("Panels")
                                .font(.pearlHeadline).foregroundColor(.primaryText)
                                .padding(.top, 8)

                            ForEach(tests, id: \.id) { test in
                                Button { selectedPanel = test } label: {
                                    PanelRow(test: test)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .bloodTestImported)) { _ in load() }
        .sheet(item: $selectedPanel) { panel in
            BloodPanelDetailView(test: panel) { name in
                selectedPanel = nil
                trendingBiomarker = name
            }
        }
        .sheet(item: Binding(
            get: { trendingBiomarker.map { NameBox(value: $0) } },
            set: { trendingBiomarker = $0?.value }
        )) { box in
            BiomarkerTrendView(biomarkerName: box.value, tests: tests)
        }
        .presentationDetents([.large])
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 54, weight: .light))
                .foregroundColor(.tertiaryText)
            Text("No blood tests imported yet")
                .font(.pearlHeadline).foregroundColor(.primaryText)
            Text("Once you import a panel, you'll see each biomarker's history here.")
                .font(.pearlCaption).foregroundColor(.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var uniqueBiomarkerNames: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for test in tests {
            for b in test.biomarkers where !seen.contains(b.name) {
                seen.insert(b.name)
                ordered.append(b.name)
            }
        }
        return ordered
    }

    private func load() {
        tests = PersistenceService.shared.fetchLatestBloodTests()
    }
}

private struct NameBox: Identifiable {
    let value: String
    var id: String { value }
}

private struct PanelRow: View {
    let test: BloodTest

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.richtext.fill")
                .font(.system(size: 20))
                .foregroundColor(.pearlGreen)
                .frame(width: 44, height: 44)
                .glassBackground(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(test.labName ?? "Unknown lab")
                    .font(.pearlHeadline).foregroundColor(.primaryText)
                Text(formattedDate).font(.pearlCaption).foregroundColor(.tertiaryText)
                Text("\(test.biomarkers.count) biomarkers • \(abnormalCount) out of range")
                    .font(.pearlCaption2).foregroundColor(.quaternaryText)
            }

            Spacer()

            Image(systemName: "chevron.right").foregroundColor(.quaternaryText)
        }
        .padding(14)
        .glassBackground(cornerRadius: 16)
    }

    private var formattedDate: String {
        let df = DateFormatter()
        df.dateStyle = .long
        return df.string(from: test.testDate ?? test.importedAt)
    }

    private var abnormalCount: Int {
        test.biomarkers.filter(\.isAbnormal).count
    }
}

struct BloodPanelDetailView: View {
    let test: BloodTest
    let onSelectBiomarker: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(test.labName ?? "Unknown lab")
                            .font(.pearlTitle2).foregroundColor(.primaryText)
                        Text(formattedDate).font(.pearlCaption).foregroundColor(.tertiaryText)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundColor(.quaternaryText)
                    }
                }
                .padding(20)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(test.biomarkers, id: \.name) { marker in
                            Button { onSelectBiomarker(marker.name) } label: {
                                BiomarkerRow(marker: marker)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var formattedDate: String {
        let df = DateFormatter()
        df.dateStyle = .long
        return df.string(from: test.testDate ?? test.importedAt)
    }
}

struct BiomarkerTrendView: View {
    let biomarkerName: String
    let tests: [BloodTest]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(biomarkerName).font(.pearlTitle2).foregroundColor(.primaryText)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundColor(.quaternaryText)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 20)

                if points.count < 2 {
                    insufficientData
                } else {
                    chart
                        .frame(height: 240)
                        .padding(.horizontal, 20)

                    summaryCard
                        .padding(.horizontal, 20)
                }

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(points.reversed(), id: \.date) { p in
                            TrendRow(point: p)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var points: [BiomarkerPoint] {
        tests.compactMap { test -> BiomarkerPoint? in
            guard let marker = test.biomarkers.first(where: { $0.name == biomarkerName }) else { return nil }
            return BiomarkerPoint(
                date: test.testDate ?? test.importedAt,
                value: marker.value,
                unit: marker.unit,
                isAbnormal: marker.isAbnormal
            )
        }.sorted { $0.date < $1.date }
    }

    private var chart: some View {
        Chart(points, id: \.date) { p in
            LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .foregroundStyle(p.isAbnormal ? Color.riskHigh : Color.pearlGreen)
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
        if let first = points.first, let last = points.last {
            let delta = last.value - first.value
            let pct = first.value != 0 ? (delta / first.value) * 100 : 0
            let sign = delta >= 0 ? "+" : ""
            let direction: String = {
                if abs(pct) < 1 { return "unchanged" }
                return delta > 0 ? "up" : "down"
            }()
            let improving = isImproving(first: first.value, last: last.value)
            let tint: Color = {
                if direction == "unchanged" { return .tertiaryText }
                return improving ? .riskLow : .riskHigh
            }()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Across \(points.count) panels").font(.pearlCaption).foregroundColor(.tertiaryText)
                    Text("\(sign)\(String(format: "%.1f", delta)) \(last.unit)")
                        .font(.pearlTitle3).foregroundColor(tint)
                    Text("\(sign)\(String(format: "%.1f", pct))% since first reading")
                        .font(.pearlCaption2).foregroundColor(.quaternaryText)
                }
                Spacer()
                Text(direction.uppercased())
                    .font(.pearlCaption).foregroundColor(tint)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(14)
            .glassBackground(cornerRadius: 14)
        }
    }

    /// Whether a delta represents improvement depends on the biomarker. LDL
    /// going down is good; HDL going down is bad. Falls back to "neutral" tint
    /// when we don't know the preferred direction.
    private func isImproving(first: Double, last: Double) -> Bool {
        let lower = biomarkerName.lowercased()
        let wantsDown: Set<String> = ["ldl", "triglycerides", "glucose", "hba1c", "total cholesterol"]
        let wantsUp: Set<String> = ["hdl", "vitamin d", "vitamin b12"]
        if wantsDown.contains(where: { lower.contains($0) }) { return last < first }
        if wantsUp.contains(where: { lower.contains($0) }) { return last > first }
        return false
    }

    private var insufficientData: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.tertiaryText)
            Text("Only one panel measured \(biomarkerName) so far.")
                .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                .multilineTextAlignment(.center)
            Text("Import another panel to see how it's moving.")
                .font(.pearlCaption).foregroundColor(.quaternaryText)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct BiomarkerPoint {
    let date: Date
    let value: Double
    let unit: String
    let isAbnormal: Bool
}

private struct TrendRow: View {
    let point: BiomarkerPoint

    var body: some View {
        HStack {
            Text(dateString).font(.pearlCaption).foregroundColor(.tertiaryText)
            Spacer()
            Text("\(String(format: "%.1f", point.value)) \(point.unit)")
                .font(.pearlSubheadline)
                .foregroundColor(point.isAbnormal ? .riskHigh : .primaryText)
            if point.isAbnormal {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundColor(.riskHigh)
            }
        }
        .padding(12)
        .glassBackground(cornerRadius: 10)
    }

    private var dateString: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: point.date)
    }
}

extension Notification.Name {
    static let bloodTestImported = Notification.Name("bloodTestImported")
    /// Posted after the user's profile is saved (from onboarding, personal
    /// details edit, or any cloud merge) so ViewModels can reload derived
    /// state and Pearl can re-prime its reasoning context.
    static let profileUpdated = Notification.Name("profileUpdated")
}
