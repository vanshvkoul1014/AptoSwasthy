import SwiftUI

struct MetricDashboardView: View {
    var vm: HomeViewModel
    @Binding var showDetail: MetricType?
    @State private var showCustomize = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Metrics")
                    .font(.pearlTitle3)
                    .foregroundColor(.primaryText)
                Spacer()
                Button {
                    showCustomize = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14, weight: .medium))
                        Text("Edit")
                            .font(.pearlCaption)
                    }
                    .foregroundColor(.pearlGreen)
                }
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(vm.visibleCards.filter(\.isVisible)) { card in
                    MetricCard(
                        type: card.type,
                        value: vm.latestValue(for: card.type),
                        profile: vm.profile
                    )
                    .onTapGesture { showDetail = card.type }
                }
            }
        }
        .sheet(item: $showDetail) { type in
            MetricDetailView(metricType: type, vm: vm)
        }
        .sheet(isPresented: $showCustomize) {
            MetricCustomizationView(vm: vm)
        }
    }
}

struct MetricCard: View {
    let type: MetricType
    let value: Double?
    let profile: UserProfile?

    var formattedValue: String {
        guard let v = value else { return "-" }
        switch type {
        case .steps: return "\(Int(v).formatted())"
        case .weight:
            if profile?.unitPreference == .imperial { return String(format: "%.1f lb", v * 2.20462) }
            return String(format: "%.1f kg", v)
        case .nutritionScore, .recoveryScore, .stressScore: return "\(Int(v))/100"
        case .restingHeartRate, .heartRate: return "\(Int(v)) bpm"
        case .heartRateVariability: return "\(Int(v)) ms"
        case .sleepDuration: return String(format: "%.1f h", v)
        case .bloodPressureSystolic: return "\(Int(v)) mmHg"
        case .oxygenSaturation, .bodyFatPercentage: return String(format: "%.1f%%", v)
        case .vo2Max: return String(format: "%.1f", v)
        case .activeEnergy, .caloriesConsumed: return "\(Int(v)) kcal"
        case .exerciseMinutes: return "\(Int(v)) min"
        case .proteinConsumed, .carbsConsumed, .fatConsumed, .fiberConsumed:
            return "\(Int(v))g"
        case .respiratoryRate: return "\(Int(v)) br/min"
        case .waterIntake: return "\(Int(v)) ml"
        default: return String(format: "%.1f", v)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: type.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 22, height: 22)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.quaternaryText)
            }

            Spacer(minLength: 4)

            Text(formattedValue)
                .font(.pearlTitle2)
                .foregroundColor(.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(type.rawValue)
                .font(.pearlCaption2)
                .foregroundColor(.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 112)
        .background(Color.glassBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.glassBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

