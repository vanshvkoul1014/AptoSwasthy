import SwiftUI

struct PersonalDetailsEditView: View {
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var dateOfBirth: Date
    @State private var biologicalSex: BiologicalSex
    @State private var heightCm: Double
    @State private var weightKg: Double
    @State private var activityLevel: ActivityLevel
    @State private var sleepHoursPerNight: Double
    @State private var smokingStatus: SmokingStatus
    @State private var alcoholFrequency: AlcoholFrequency
    @State private var vegetableServingsPerDay: Int
    @State private var fruitServingsPerDay: Int
    @State private var stressLevel: Int
    @State private var processedFoodFrequency: ProcessedFoodFrequency
    @State private var eatingWindowHours: Int
    @State private var alcoholDrinksPerWeek: Int

    init(profile: UserProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _dateOfBirth = State(initialValue: profile.dateOfBirth)
        _biologicalSex = State(initialValue: profile.biologicalSex)
        _heightCm = State(initialValue: profile.heightCm)
        _weightKg = State(initialValue: profile.weightKg)
        _activityLevel = State(initialValue: profile.activityLevel)
        _sleepHoursPerNight = State(initialValue: profile.sleepHoursPerNight)
        _smokingStatus = State(initialValue: profile.smokingStatus)
        _alcoholFrequency = State(initialValue: profile.alcoholFrequency)
        _vegetableServingsPerDay = State(initialValue: profile.vegetableServingsPerDay)
        _fruitServingsPerDay = State(initialValue: profile.fruitServingsPerDay)
        _stressLevel = State(initialValue: profile.stressLevel)
        _processedFoodFrequency = State(initialValue: profile.processedFoodFrequency)
        _eatingWindowHours = State(initialValue: profile.eatingWindowHours)
        _alcoholDrinksPerWeek = State(initialValue: profile.alcoholDrinksPerWeek)
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("Personal Details")
                            .font(.pearlTitle)
                            .foregroundColor(.primaryText)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.quaternaryText)
                        }
                    }
                    .padding(.top, 24)

                    // Name
                    EditSection(title: "Name") {
                        TextField("Full name", text: $name)
                            .font(.pearlBody)
                            .foregroundColor(.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }

                    // Date of birth
                    EditSection(title: "Date of Birth") {
                        DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }

                    // Biological sex
                    EditSection(title: "Biological Sex") {
                        Picker("", selection: $biologicalSex) {
                            ForEach(BiologicalSex.allCases, id: \.self) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    // Height
                    EditSection(title: "Height: \(Int(heightCm)) cm") {
                        Slider(value: $heightCm, in: 120...220, step: 1)
                            .tint(.pearlGreen)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }

                    // Weight
                    EditSection(title: "Weight: \(String(format: "%.1f", weightKg)) kg") {
                        Slider(value: $weightKg, in: 30...200, step: 0.5)
                            .tint(.pearlGreen)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }

                    // Sleep
                    EditSection(title: "Nightly Sleep: \(String(format: "%.1f", sleepHoursPerNight)) hrs") {
                        Slider(value: $sleepHoursPerNight, in: 4...12, step: 0.5)
                            .tint(.pearlGreen)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }

                    // Activity level
                    EditSection(title: "Activity Level") {
                        Picker("", selection: $activityLevel) {
                            ForEach(ActivityLevel.allCases, id: \.self) { l in
                                Text(l.rawValue).tag(l)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .padding(.horizontal, 16)
                    }

                    // Smoking
                    EditSection(title: "Smoking Status") {
                        Picker("", selection: $smokingStatus) {
                            ForEach(SmokingStatus.allCases, id: \.self) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    // Alcohol
                    EditSection(title: "Alcohol Frequency") {
                        Picker("", selection: $alcoholFrequency) {
                            ForEach(AlcoholFrequency.allCases, id: \.self) { a in
                                Text(a.rawValue).tag(a)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .padding(.horizontal, 16)
                    }

                    EditSection(title: "Drinks per week: \(alcoholDrinksPerWeek)") {
                        Slider(value: Binding(get: { Double(alcoholDrinksPerWeek) }, set: { alcoholDrinksPerWeek = Int($0) }), in: 0...40, step: 1)
                            .tint(.pearlGreen)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                    }

                    EditSection(title: "Vegetables per day: \(vegetableServingsPerDay)") {
                        Slider(value: Binding(get: { Double(vegetableServingsPerDay) }, set: { vegetableServingsPerDay = Int($0) }), in: 0...10, step: 1)
                            .tint(.pearlGreen)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                    }

                    EditSection(title: "Fruit per day: \(fruitServingsPerDay)") {
                        Slider(value: Binding(get: { Double(fruitServingsPerDay) }, set: { fruitServingsPerDay = Int($0) }), in: 0...10, step: 1)
                            .tint(.pearlGreen)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                    }

                    EditSection(title: "Eating window: \(eatingWindowHours) hrs/day") {
                        Slider(value: Binding(get: { Double(eatingWindowHours) }, set: { eatingWindowHours = Int($0) }), in: 4...24, step: 1)
                            .tint(.pearlGreen)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                    }

                    EditSection(title: "Stress level: \(stressLevel)/10") {
                        Slider(value: Binding(get: { Double(stressLevel) }, set: { stressLevel = Int($0) }), in: 1...10, step: 1)
                            .tint(.pearlGreen)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                    }

                    EditSection(title: "Processed food frequency") {
                        Picker("", selection: $processedFoodFrequency) {
                            ForEach(ProcessedFoodFrequency.allCases, id: \.self) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 100)
                        .padding(.horizontal, 16)
                    }

                    // Save
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Text("Save Changes")
                            .font(.pearlHeadline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(LinearGradient(
                                colors: [.pearlGreen, .pearlMint],
                                startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 20)
            }
        }
        .keyboardDismissable()
    }

    private func save() {
        profile.name = name
        profile.dateOfBirth = dateOfBirth
        profile.biologicalSex = biologicalSex
        profile.heightCm = heightCm
        profile.weightKg = weightKg
        profile.activityLevel = activityLevel
        profile.sleepHoursPerNight = sleepHoursPerNight
        profile.smokingStatus = smokingStatus
        profile.alcoholFrequency = alcoholFrequency
        profile.alcoholDrinksPerWeek = alcoholDrinksPerWeek
        profile.vegetableServingsPerDay = vegetableServingsPerDay
        profile.fruitServingsPerDay = fruitServingsPerDay
        profile.stressLevel = stressLevel
        profile.processedFoodFrequency = processedFoodFrequency
        profile.eatingWindowHours = eatingWindowHours
        PersistenceService.shared.save()
        NotificationCenter.default.post(name: .profileUpdated, object: nil)
        let dto = ProfileDTO(from: profile)
        Task.detached {
            do {
                try await ProfileAPIService.shared.putProfile(dto)
            } catch ProfileAPIError.cloudDisabled {
                // Stack not yet deployed - local-only is expected.
            } catch {
                #if DEBUG
                print("[PersonalDetailsEditView] cloud profile push failed: \(error)")
                #endif
            }
        }
    }
}

private struct EditSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.pearlFootnote.weight(.semibold))
                .foregroundColor(.quaternaryText)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Color.glassBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.glassBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
