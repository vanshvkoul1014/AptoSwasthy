import SwiftUI
import SwiftData

struct HomeView: View {
    @State private var vm = HomeViewModel()
    @ObservedObject private var healthKit = HealthKitService.shared
    @State private var showAddFood = false
    @State private var showMetricDetail: MetricType? = nil
    @State private var showHabitDecline: Habit? = nil
    @State private var showLEDetail = false
    @State private var showReconnectApps = false

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            if vm.isLoading {
                PearlLoadingView(message: "Loading your data…")
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // Life Expectancy Header
                        LifeExpectancyHeaderView(
                            years: vm.lifeExpectancyFormatted,
                            greeting: vm.greeting,
                            profile: vm.profile,
                            weeklyDelta: vm.weeklyLEDelta
                        )
                        .padding(.horizontal, 20)
                        .onTapGesture {
                            showLEDetail = true
                        }

                        // Metric Dashboard
                        MetricDashboardView(vm: vm, showDetail: $showMetricDetail)
                            .padding(.horizontal, 20)

                        // Nutrition Logger
                        NutritionLoggerView(vm: vm, showAddFood: $showAddFood)
                            .padding(.horizontal, 20)

                        // Habit Dashboard
                        HabitDashboardView(vm: vm)
                            .padding(.horizontal, 20)

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 16)
                }
                .refreshable { vm.refresh() }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            vm.load()
            evaluateReconnectPrompt()
        }
        .sheet(isPresented: $showAddFood) {
            FoodSearchView { entry, mealType, loggedAt in
                let meal = Meal(mealType: mealType, loggedAt: loggedAt)
                meal.foodItems = [entry]
                PersistenceService.shared.insert(meal)
                vm.refresh()
            }
        }
        .sheet(isPresented: $showLEDetail) {
            LifeExpectancyDetailView(
                projected: vm.lifeExpectancy,
                base: vm.lifeExpectancyBase,
                factors: vm.lifeExpectancyFactors,
                profile: vm.profile
            )
        }
        .sheet(isPresented: $vm.showFirstSnapshot) {
            FirstSnapshotView(text: vm.firstSnapshotText)
        }
        .sheet(isPresented: $showReconnectApps) {
            ConnectedAppsView()
        }
    }

    /// Show the reconnect sheet once per app launch if the cloud profile
    /// says Apple Health was previously authorized but it isn't on this
    /// device - typical of a fresh install or a new device.
    private func evaluateReconnectPrompt() {
        guard !showReconnectApps else { return }
        let profile = PersistenceService.shared.fetchProfile()
        let wasConnected = profile?.connectedApps.contains("Apple Health") ?? false
        if wasConnected && !healthKit.isAuthorized {
            showReconnectApps = true
        }
    }
}

// MARK: - Life Expectancy Header

struct LifeExpectancyHeaderView: View {
    let years: String
    let greeting: String
    let profile: UserProfile?
    var weeklyDelta: Double? = nil
    @State private var animate = false
    @State private var didHaptic = false

    // Scoped to the gradient fill so it doesn't implicitly animate the
    // number/text layout when they change (prior implementation caused the
    // LE value and greeting to visibly drift across each other).
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color.pearlGreen.opacity(0.25), Color.pearlMint.opacity(0.12)],
            startPoint: animate ? .topLeading : .bottomTrailing,
            endPoint: animate ? .bottomTrailing : .topLeading
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(backgroundGradient)
                .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: animate)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.pearlGreen.opacity(0.3), lineWidth: 1)
                }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.pearlSubheadline)
                        .foregroundColor(.tertiaryText)

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(years)
                            .font(.pearlNumber)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.pearlGreen, .pearlMint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("years")
                            .font(.pearlTitle3)
                            .foregroundColor(.tertiaryText)
                    }

                    HStack(spacing: 8) {
                        Text("Pearl's estimate")
                            .font(.pearlCaption)
                            .foregroundColor(.tertiaryText)

                        if let delta = weeklyDelta, abs(delta) >= 0.05 {
                            HStack(spacing: 3) {
                                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("\(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta)) yrs this week")
                                    .font(.pearlCaption)
                            }
                            .foregroundColor(delta >= 0 ? .riskLow : .pearlCoral)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.quaternaryText)
            }
            .padding(20)
        }
        .onAppear {
            animate = true
            if !didHaptic && years != "-" {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                didHaptic = true
            }
        }
    }
}

// MARK: - First Snapshot Sheet

struct FirstSnapshotView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing))

                Text("Your First Snapshot")
                    .font(.pearlTitle2)
                    .foregroundColor(.primaryText)

                Text(text)
                    .font(.pearlBody)
                    .foregroundColor(.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(6)
                    .padding()
                    .glassBackground(cornerRadius: 20)

                Button {
                    dismiss()
                } label: {
                    Text("Let's go")
                        .font(.pearlHeadline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(28)
        }
        .presentationDetents([.large])
    }
}
