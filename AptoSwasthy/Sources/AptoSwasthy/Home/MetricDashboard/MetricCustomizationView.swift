import SwiftUI

struct MetricCustomizationView: View {
    var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTypes: Set<MetricType> = []

    init(vm: HomeViewModel) {
        self.vm = vm
        _selectedTypes = State(initialValue: Set(vm.visibleCards.map { $0.type }))
    }

    private let minCount = 2
    private let maxCount = 10

    private var canSave: Bool {
        selectedTypes.count >= minCount && selectedTypes.count <= maxCount
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.pearlSubheadline)
                        .foregroundColor(.tertiaryText)

                    Spacer()

                    Text("Metrics")
                        .font(.pearlHeadline)
                        .foregroundColor(.primaryText)

                    Spacer()

                    Button("Done") { save() }
                        .font(.pearlHeadline)
                        .foregroundColor(canSave ? .pearlGreen : .quaternaryText)
                        .disabled(!canSave)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)

                VStack(spacing: 4) {
                    Text("Choose 2–10 metrics for your home screen.")
                        .font(.pearlCaption)
                        .foregroundColor(.tertiaryText)
                    Text("\(selectedTypes.count) selected")
                        .font(.pearlCaption2.weight(.semibold))
                        .foregroundColor(selectedTypes.count >= maxCount ? .riskHigh : .pearlGreen)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(MetricType.allCases) { type in
                            let selected = selectedTypes.contains(type)
                            let atMax = selectedTypes.count >= maxCount
                            MetricToggleRow(
                                type: type,
                                isSelected: selected,
                                isDisabled: !selected && atMax
                            ) {
                                if selected {
                                    if selectedTypes.count > minCount { selectedTypes.remove(type) }
                                } else if !atMax {
                                    selectedTypes.insert(type)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        vm.visibleCards = MetricType.allCases
            .filter { selectedTypes.contains($0) }
            .map { MetricCardConfig(id: UUID(), type: $0, isVisible: true) }
        vm.saveMetricPreferences()
        dismiss()
    }
}

private struct MetricToggleRow: View {
    let type: MetricType
    let isSelected: Bool
    var isDisabled: Bool = false
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.pearlGreen.opacity(0.2) : Color.glassBackground)
                        .frame(width: 40, height: 40)
                    Image(systemName: type.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(
                            isSelected
                            ? LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.tertiaryText, Color.tertiaryText], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.rawValue)
                        .font(.pearlSubheadline)
                        .foregroundColor(isSelected ? .primaryText : .tertiaryText)
                    Text(type.defaultUnit)
                        .font(.pearlCaption2)
                        .foregroundColor(.quaternaryText)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .pearlGreen : .quaternaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.pearlGreen.opacity(0.08) : Color.glassBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.pearlGreen.opacity(0.3) : Color.glassBorder,
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isDisabled ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
