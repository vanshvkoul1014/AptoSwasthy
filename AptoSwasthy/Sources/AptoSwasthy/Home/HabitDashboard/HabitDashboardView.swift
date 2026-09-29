import SwiftUI

struct HabitDashboardView: View {
    var vm: HomeViewModel
    @State private var declineHabit: Habit? = nil
    @State private var retireHabit: Habit? = nil
    @State private var showRetireConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Habits")
                .font(.pearlTitle3).foregroundColor(.primaryText)

            if vm.habits.isEmpty {
                Text("Pearl is building your first habits based on your profile...")
                    .font(.pearlSubheadline)
                    .foregroundColor(.quaternaryText)
                    .padding(.vertical, 12)
            } else {
                ForEach(vm.habits) { habit in
                    HabitCard(habit: habit,
                              onComplete: { markComplete(habit) },
                              onDecline:  { declineHabit = habit },
                              onRetire:   { retireHabit = habit; showRetireConfirm = true }
                    )
                }
            }
        }
        .padding(16)
        .glassBackground(cornerRadius: 22)
        .sheet(item: $declineHabit) { habit in
            HabitDeclineView(habit: habit) { accepted, alternative in
                handleDecline(habit: habit, accepted: accepted, alternative: alternative)
            }
        }
        .alert(
            PearlHabitIntelligence().retirementPrompt(habit: retireHabit ?? vm.habits.first ?? Habit(name: "", habitDescription: "", category: .activity)),
            isPresented: $showRetireConfirm
        ) {
            Button("Yes, retire it") {
                if let h = retireHabit { retireHabit(h) }
            }
            Button("Not yet", role: .cancel) {}
        }
    }

    private func markComplete(_ habit: Habit) {
        habit.markComplete()
        PersistenceService.shared.save()
        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func retireHabit(_ habit: Habit) {
        habit.isRetired = true
        habit.isActive = false
        habit.retiredDate = Date()
        NotificationService.shared.cancelHabitReminder(habit: habit)
        PersistenceService.shared.save()
        vm.habits.removeAll { $0.id == habit.id }

        // Seed a replacement habit so the user always has something to work on.
        guard let profile = vm.profile else { return }
        let persistence = PersistenceService.shared
        let newHabits = PearlHabitIntelligence().selectHabits(
            for: profile,
            existing: vm.habits,
            currentMetrics: vm.metrics
        )
        if let replacement = newHabits.first {
            persistence.insert(replacement)
            vm.habits.append(replacement)
            let reminderTime = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: Date()) ?? Date()
            NotificationService.shared.scheduleHabitReminder(habit: replacement, at: reminderTime)
        }
    }

    private func handleDecline(habit: Habit, accepted: Bool, alternative: Habit?) {
        if !accepted {
            habit.isActive = false
            PersistenceService.shared.save()
            vm.habits.removeAll { $0.id == habit.id }
            if let alt = alternative {
                PersistenceService.shared.insert(alt)
                vm.habits.append(alt)
            }
        }
    }
}

struct HabitCard: View {
    @State var habit: Habit
    let onComplete: () -> Void
    let onDecline: () -> Void
    let onRetire: () -> Void
    @State private var showRationale = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Complete dot
                Button(action: onComplete) {
                    ZStack {
                        Circle()
                            .stroke(habit.isCompletedToday ? Color.pearlGreen : Color.glassBorder, lineWidth: 2)
                            .frame(width: 30, height: 30)
                        if habit.isCompletedToday {
                            Circle()
                                .fill(Color.pearlGreen)
                                .frame(width: 18, height: 18)
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(habit.name)
                            .font(.pearlHeadline)
                            .foregroundColor(.primaryText)
                        Spacer()
                        Text(habit.cadence.rawValue)
                            .font(.pearlCaption2)
                            .foregroundColor(.quaternaryText)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .glassBackground(cornerRadius: 8)
                    }

                    Text(habit.habitDescription)
                        .font(.pearlCaption)
                        .foregroundColor(.tertiaryText)
                        .lineLimit(showRationale ? nil : 2)
                }
            }

            // Formation arc
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.glassBackground)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * habit.formationProgress, height: 4)
                        .animation(.easeInOut(duration: 0.6), value: habit.formationProgress)
                }
            }
            .frame(height: 4)

            HStack {
                Text("Day \(habit.daysSinceStart) of \(habit.formationDays)")
                    .font(.pearlCaption2)
                    .foregroundColor(.quaternaryText)
                Spacer()
                if habit.isReadyToRetire {
                    Button(action: onRetire) {
                        Text("Mark as lasting")
                            .font(.pearlCaption)
                            .foregroundColor(.pearlGreen)
                    }
                }
            }
        }
        .padding(14)
        .glassBackground(cornerRadius: 16)
        .onLongPressGesture { showRationale.toggle() }
    }
}

struct HabitDeclineView: View {
    let habit: Habit
    let onResult: (Bool, Habit?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var alternativeHabit: Habit? = nil

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            VStack(spacing: 24) {
                Text("Is '\(habit.name)' feasible for you right now?")
                    .font(.pearlTitle2).foregroundColor(.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)

                Text(habit.pearlRationale)
                    .font(.pearlBody).foregroundColor(.tertiaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)

                VStack(spacing: 12) {
                    Button {
                        onResult(true, nil)
                        dismiss()
                    } label: {
                        Text("Yes, I'll try it")
                            .font(.pearlHeadline).foregroundColor(.black)
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(LinearGradient(colors: [.pearlGreen, .pearlMint], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if let alt = alternativeHabit {
                        Button {
                            onResult(false, alt)
                            dismiss()
                        } label: {
                            Text("Try '\(alt.name)' instead")
                                .font(.pearlHeadline).foregroundColor(.primaryText)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .glassBackground(cornerRadius: 16)
                        }
                    }

                    Button {
                        onResult(false, nil)
                        dismiss()
                    } label: {
                        Text("Skip for now")
                            .font(.pearlSubheadline).foregroundColor(.tertiaryText)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            guard let profile = PersistenceService.shared.fetchProfile() else { return }
            let existing = PersistenceService.shared.fetchActiveHabits()
            alternativeHabit = PearlHabitIntelligence().alternativeHabit(
                for: habit, profile: profile, existing: existing
            )
        }
    }
}
