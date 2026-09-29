import SwiftUI

struct RisksView: View {
    @State private var vm = RisksViewModel()
    @State private var showAll = false

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            ScrollView {
                LazyVStack(spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Risk Profile")
                            .font(.pearlLargeTitle)
                            .foregroundColor(.primaryText)
                        Text(vm.overallSummary)
                            .font(.pearlSubheadline)
                            .foregroundColor(.tertiaryText)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    if vm.isLoading {
                        PearlLoadingView(message: "Calculating your risks…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        // Elevated risks
                        let elevated = vm.risks.filter { $0.tier != .low }
                        let normal   = vm.risks.filter { $0.tier == .low }

                        if elevated.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .topLeading, endPoint: .bottomTrailing))
                                Text(vm.allClearMessage)
                                    .font(.pearlBody)
                                    .foregroundColor(.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(5)
                            }
                            .glassCard()
                            .padding(.horizontal, 20)
                        } else {
                            ForEach(elevated) { risk in
                                RiskCard(risk: risk)
                                    .padding(.horizontal, 20)
                            }
                        }

                        // Show all toggle
                        if !normal.isEmpty {
                            Button {
                                withAnimation { showAll.toggle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(showAll ? "Show elevated only" : "Show all conditions (\(normal.count) low risk)")
                                        .font(.pearlSubheadline)
                                        .foregroundColor(.tertiaryText)
                                    Image(systemName: showAll ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.quaternaryText)
                                }
                                .padding(.vertical, 8)
                            }
                            .padding(.horizontal, 20)

                            if showAll {
                                ForEach(normal) { risk in
                                    RiskCard(risk: risk)
                                        .padding(.horizontal, 20)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                        }

                        // Disclaimer
                        Text("Pearl is not a doctor. These assessments are for informational purposes only. Please consult a healthcare provider for diagnosis or treatment.")
                            .font(.pearlCaption)
                            .foregroundColor(.quaternaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .padding(.top, 8)

                        Spacer(minLength: 32)
                    }
                }
            }
            .refreshable { vm.load() }
        }
        .navigationBarHidden(true)
        .onAppear { vm.load() }
    }
}
