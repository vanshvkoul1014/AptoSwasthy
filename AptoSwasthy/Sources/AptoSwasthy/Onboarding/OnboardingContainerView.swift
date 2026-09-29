import SwiftUI

struct OnboardingContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    @State private var vm = OnboardingViewModel()

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                // Header
                HStack {
                    if vm.currentStep > 0 {
                        Button { vm.back() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.tertiaryText)
                                .frame(width: 44, height: 44)
                        }
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }

                    Spacer()

                    // Step dots
                    HStack(spacing: 6) {
                        ForEach(0..<vm.totalSteps, id: \.self) { i in
                            Circle()
                                .fill(i == vm.currentStep ? Color.pearlGreen : Color.quaternaryText)
                                .frame(width: i == vm.currentStep ? 8 : 5,
                                       height: i == vm.currentStep ? 8 : 5)
                                .animation(.spring(response: 0.3), value: vm.currentStep)
                        }
                    }

                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Step content
                TabView(selection: $vm.currentStep) {
                    ForEach(0..<vm.totalSteps, id: \.self) { step in
                        stepView(for: step)
                            .tag(step)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: vm.currentStep)

                // Next button
                VStack(spacing: 16) {
                    Button {
                        if vm.currentStep == vm.totalSteps - 1 {
                            vm.saveProfile()
                        } else {
                            vm.advance()
                        }
                    } label: {
                        Text(vm.currentStep == vm.totalSteps - 1 ? "Get Started" : "Continue")
                            .font(.pearlHeadline)
                            .foregroundColor(vm.canAdvance ? .white : .quaternaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                vm.canAdvance
                                    ? LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [Color.glassBorder, Color.glassBorder], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(!vm.canAdvance)
                    .padding(.horizontal, 32)

                    if !vm.canAdvance {
                        Text("Pearl needs this to work for you")
                            .font(.pearlFootnote)
                            .foregroundColor(.quaternaryText)
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, 20)
                .animation(.easeInOut, value: vm.canAdvance)
            }
        }
        .keyboardDismissable()
        .onChange(of: vm.isComplete) { _, complete in
            if complete {
                auth.isAuthenticated = true
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func stepView(for step: Int) -> some View {
        OnboardingStepWrapper(title: vm.stepTitle, subtitle: vm.stepSubtitle) {
            switch step {
            case 0:  NameStepView(name: $vm.name)
            case 1:  DOBStepView(dateOfBirth: $vm.dateOfBirth)
            case 2:  BiologicalSexStepView(biologicalSex: $vm.biologicalSex)
            case 3:  EthnicityStepView(ethnicity: $vm.ethnicity)
            case 4:  HeightWeightStepView(heightCm: $vm.heightCm, weightKg: $vm.weightKg, unitPreference: $vm.unitPreference)
            case 5:  ActivityLevelStepView(activityLevel: $vm.activityLevel, minutesPerSession: $vm.activityMinutesPerSession)
            case 6:  ExerciseTypesStepView(selected: $vm.selectedExerciseTypes)
            case 7:
                VStack(spacing: 24) {
                    SleepScheduleStepView(bedtime: $vm.sleepBedtime, wakeTime: $vm.sleepWakeTime, hours: $vm.sleepHours)
                    SleepQualityRow(quality: $vm.sleepQuality)
                }
            case 8:  HealthConditionsStepView(selected: $vm.selectedConditions)
            case 9:  MedicationsStepView(selected: $vm.selectedMedications)
            case 10: FamilyHistoryStepView(selected: $vm.selectedFamilyHistory)
            case 11: SmokingStepView(
                smoking: $vm.smokingStatus,
                packYears: $vm.smokingPackYears,
                yearsSmoking: $vm.yearsSmoking,
                yearsSinceQuit: $vm.yearsSinceQuitSmoking,
                cigarettesPerDay: $vm.cigarettesPerDay,
                vapes: $vm.vapes,
                secondhand: $vm.secondhandSmokeExposure,
                cannabis: $vm.cannabisUseFrequency)
            case 12: AlcoholStepView(
                alcohol: $vm.alcoholFrequency,
                drinksPerWeek: $vm.alcoholDrinksPerWeek,
                bingeFrequency: $vm.alcoholBingeFrequency,
                alcoholFreeDays: $vm.alcoholFreeDaysPerWeek,
                beverageTypes: $vm.alcoholBeverageTypes)
            case 13: EatingHabitsStepView(
                dietType: $vm.dietType,
                mealsPerDay: $vm.mealsPerDay,
                fastFoodPerWeek: $vm.fastFoodPerWeek,
                waterGlassesPerDay: $vm.waterGlassesPerDay,
                caffeineCupsPerDay: $vm.caffeineCupsPerDay,
                addedSugarServingsPerDay: $vm.addedSugarServingsPerDay,
                vegetableServings: $vm.vegetableServingsPerDay,
                fruitServings: $vm.fruitServingsPerDay,
                homeCookedPerWeek: $vm.homeCookedMealsPerWeek,
                lateNightPerWeek: $vm.lateNightEatingTimesPerWeek,
                eatingWindowHours: $vm.eatingWindowHours,
                processedFoodFrequency: $vm.processedFoodFrequency,
                emotionalEating: $vm.emotionalEatingFrequency,
                proteinSources: $vm.proteinSources)
            case 14: StressScreenTimeStepView(stressLevel: $vm.stressLevel, screenTimeHours: $vm.screenTimeHoursPerDay)
            case 15: BiographyStepView(note: $vm.biographyNote)
            case 16: HealthGoalsStepView(selected: $vm.selectedGoals)
            default: EmptyView()
            }
        }
    }
}

struct OnboardingStepWrapper<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.pearlTitle)
                    .foregroundColor(.primaryText)

                Text(subtitle)
                    .font(.pearlSubheadline)
                    .foregroundColor(.tertiaryText)
                    .padding(.bottom, 8)

                content
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
        }
    }
}
