import SwiftUI

struct YouTabView: View {
    @State private var vm = YouViewModel()
    @State private var showSettings = false
    @State private var showOnboarding = false
    @State private var showPersonalEdit = false
    @State private var showBloodTestImport = false
    @State private var selectedStat: StatKind? = nil
    @State private var isLoading = true

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
                .ignoresSafeArea()

            if isLoading {
                PearlLoadingView(message: "Building your profile…")
            } else if let p = vm.profile {
                profileContent(p)
            } else {
                emptyState
            }
        }
        .navigationBarHidden(true)
        .task {
            isLoading = true
            await Task.yield()
            vm.load()
            isLoading = false
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(profile: $vm.profile)
        }
        .sheet(isPresented: $showPersonalEdit, onDismiss: { vm.load() }) {
            if let p = vm.profile {
                PersonalDetailsEditView(profile: p)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: { vm.load() }) {
            OnboardingContainerView()
        }
        .sheet(item: $selectedStat) { kind in
            if let p = vm.profile {
                StatDetailView(kind: kind, profile: p)
            }
        }
        .sheet(isPresented: $showBloodTestImport) {
            BloodTestImportView()
        }
    }

    // MARK: - Character-portrait layout

    @ViewBuilder
    private func profileContent(_ p: UserProfile) -> some View {
        let muscle = BodyShapeMapper.estimatedMuscleMassPercent(for: p)

        VStack(spacing: 0) {
            // Header - name + settings
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name.isEmpty ? "Your Profile" : p.name)
                        .font(.pearlTitle)
                        .foregroundColor(.primaryText)
                        .shadow(color: .black.opacity(0.35), radius: 6)
                    Text("\(p.age) · \(p.biologicalSex.rawValue)")
                        .font(.pearlFootnote)
                        .foregroundColor(.tertiaryText)
                }
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.primaryText)
                        .frame(width: 40, height: 40)
                        .liquidGlass(cornerRadius: 14)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // Avatar takes all available space above the metrics card, so the
            // figure literally stands above the floating stats.
            BodyModelView(profile: p,
                          muscleMassPercent: muscle,
                          fillsScreen: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 10) {
                UnifiedStatsCard(
                    stats: [
                        StatItem(kind: .height,
                                 label: "Height",
                                 value: p.unitPreference == .imperial
                                    ? p.heightFeetString
                                    : "\(Int(p.heightCm)) cm"),
                        StatItem(kind: .weight,
                                 label: "Weight",
                                 value: p.unitPreference == .imperial
                                    ? "\(Int(p.weightLbs)) lb"
                                    : "\(Int(p.weightKg)) kg"),
                        StatItem(kind: .bmi,
                                 label: "BMI",
                                 value: String(format: "%.1f", p.bmi)),
                        StatItem(kind: .muscle,
                                 label: "Muscle",
                                 value: "\(Int(muscle))%"),
                        StatItem(kind: .fitness,
                                 label: "Fitness",
                                 value: vm.fitnessScore > 0 ? "\(Int(vm.fitnessScore))" : "-"),
                        StatItem(kind: .bodyFat,
                                 label: "Body fat",
                                 value: vm.bodyFatEstimate(profile: p))
                    ],
                    bmiCategory: p.bmiCategory.rawValue,
                    onSelect: { selectedStat = $0 }
                )

                Button { showBloodTestImport = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cross.vial.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LinearGradient(
                                colors: [.pearlGreen, .pearlMint],
                                startPoint: .leading, endPoint: .trailing))
                        Text("Import Blood Test")
                            .font(.pearlSubheadline.weight(.semibold))
                            .foregroundColor(.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.quaternaryText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .liquidGlass(cornerRadius: 14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(LinearGradient(
                    colors: [.pearlGreen, .pearlMint],
                    startPoint: .topLeading, endPoint: .bottomTrailing))

            VStack(spacing: 6) {
                Text("Set up your profile")
                    .font(.pearlHeadline)
                    .foregroundColor(.primaryText)
                Text("Complete onboarding so Pearl can reason about your health data.")
                    .font(.pearlSubheadline)
                    .foregroundColor(.tertiaryText)
                    .multilineTextAlignment(.center)
            }

            Button {
                showOnboarding = true
            } label: {
                Text("Get Started")
                    .font(.pearlHeadline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(colors: [.pearlGreen, .pearlMint],
                                       startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.top, 4)
        }
        .padding(28)
        .glassBackground(cornerRadius: 20)
        .padding(.horizontal, 20)
    }
}

// MARK: - Unified stats card

private struct StatItem {
    let kind: StatKind
    let label: String
    let value: String
}

private struct UnifiedStatsCard: View {
    let stats: [StatItem]
    let bmiCategory: String
    let onSelect: (StatKind) -> Void

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                      spacing: 10) {
                ForEach(stats.indices, id: \.self) { i in
                    Button {
                        onSelect(stats[i].kind)
                    } label: {
                        statCell(stats[i])
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().background(Color.white.opacity(0.08))
            Text(bmiCategory.uppercased() + " RANGE")
                .font(.pearlCaption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(LinearGradient(
                    colors: [.pearlGreen, .pearlMint],
                    startPoint: .leading, endPoint: .trailing))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 18)
    }

    private func statCell(_ s: StatItem) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: s.kind.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: [.pearlGreen, .pearlMint],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(s.label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(.quaternaryText)
            }
            Text(s.value)
                .font(.pearlSubheadline.weight(.semibold))
                .foregroundColor(.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
