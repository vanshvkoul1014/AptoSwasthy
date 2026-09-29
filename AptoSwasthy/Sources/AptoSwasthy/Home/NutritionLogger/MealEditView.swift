import SwiftUI

/// Lets the user adjust portion size and quantity of a logged meal without
/// re-searching for the food. The per-entry macros scale proportionally so
/// the daily totals stay internally consistent.
struct MealEditView: View {
    let meal: Meal
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    // Per-food editable state. Stores each entry's current multiplier
    // (scaled off the originally logged serving size) + quantity count.
    @State private var entryStates: [EntryState] = []
    @State private var editedMealType: MealType = .snack
    @State private var editedLoggedAt: Date = Date()

    struct EntryState: Identifiable {
        let id: UUID
        var baseServingSize: Double
        var baseServingUnit: String
        var servingMultiplier: Double
        var quantity: Int
        // Base per-unit macros at multiplier == 1 & quantity == 1.
        var baseCalories: Double
        var baseProtein: Double
        var baseCarbs: Double
        var baseFat: Double
        var baseFiber: Double

        var displaySize: Double { baseServingSize * servingMultiplier }
        var currentCalories: Double { baseCalories * servingMultiplier * Double(quantity) }
        var currentProtein: Double { baseProtein * servingMultiplier * Double(quantity) }
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(editedMealType.rawValue.uppercased())
                                .font(.pearlCaption.weight(.semibold))
                                .tracking(1.0)
                                .foregroundColor(.tertiaryText)
                            Text(meal.foodItems.first?.foodName ?? "Meal")
                                .font(.pearlTitle2)
                                .foregroundColor(.primaryText)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.quaternaryText)
                        }
                    }

                    mealContextEditor

                    ForEach($entryStates) { $state in
                        entryEditor(state: $state)
                    }

                    Button {
                        applyChanges()
                        onSave()
                        dismiss()
                    } label: {
                        Text("Save Changes")
                            .font(.pearlHeadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(LinearGradient(
                                colors: [.pearlGreen, .pearlMint],
                                startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button(role: .destructive) {
                        PersistenceService.shared.delete(meal)
                        onSave()
                        dismiss()
                    } label: {
                        Text("Delete from log")
                            .font(.pearlSubheadline)
                            .foregroundColor(.riskHigh)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .keyboardDismissable()
        .onAppear(perform: seedState)
        .presentationDetents([.large])
    }

    private var mealContextEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Meal")
                    .font(.pearlCaption.weight(.semibold))
                    .tracking(1.0)
                    .foregroundColor(.tertiaryText)
                    .textCase(.uppercase)
                Spacer()
                Menu {
                    ForEach(MealType.allCases, id: \.self) { type in
                        Button(type.rawValue) { editedMealType = type }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(editedMealType.rawValue)
                            .font(.pearlCallout.weight(.semibold))
                            .foregroundColor(.primaryText)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.tertiaryText)
                    }
                }
            }
            HStack {
                Text("Time")
                    .font(.pearlCaption.weight(.semibold))
                    .tracking(1.0)
                    .foregroundColor(.tertiaryText)
                    .textCase(.uppercase)
                Spacer()
                DatePicker(
                    "",
                    selection: $editedLoggedAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(.pearlGreen)
            }
        }
        .padding(16)
        .glassBackground(cornerRadius: 16)
    }

    private func seedState() {
        editedMealType = meal.mealType
        editedLoggedAt = meal.loggedAt
        guard entryStates.isEmpty else { return }
        entryStates = meal.foodItems.map { item in
            // Assume stored macros already reflect the current serving size -
            // divide by it so the "base" is per-unit-of-servingUnit. This
            // keeps the math stable across edits.
            let size = item.servingSize > 0 ? item.servingSize : 1
            return EntryState(
                id: item.id,
                baseServingSize: size,
                baseServingUnit: item.servingUnit,
                servingMultiplier: 1.0,
                quantity: 1,
                baseCalories: item.calories,
                baseProtein: item.proteinG,
                baseCarbs: item.carbsG,
                baseFat: item.fatG,
                baseFiber: item.fiberG
            )
        }
    }

    @ViewBuilder
    private func entryEditor(state: Binding<EntryState>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item = meal.foodItems.first(where: { $0.id == state.wrappedValue.id }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.foodName)
                            .font(.pearlSubheadline.weight(.semibold))
                            .foregroundColor(.primaryText)
                        if let brand = item.brandName {
                            Text(brand)
                                .font(.pearlCaption)
                                .foregroundColor(.tertiaryText)
                        }
                    }
                    Spacer()
                    Text("\(Int(state.wrappedValue.currentCalories)) kcal")
                        .font(.pearlSubheadline.weight(.semibold))
                        .foregroundColor(.pearlGreen)
                }
            }

            // Serving size slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Serving size")
                        .font(.pearlCaption.weight(.semibold))
                        .foregroundColor(.tertiaryText)
                        .textCase(.uppercase)
                    Spacer()
                    Text("\(formatted(state.wrappedValue.displaySize)) \(state.wrappedValue.baseServingUnit)")
                        .font(.pearlCaption)
                        .foregroundColor(.primaryText)
                }
                Slider(value: state.servingMultiplier, in: 0.25...4.0, step: 0.25)
                    .tint(.pearlGreen)
            }

            // Quantity stepper
            HStack {
                Text("Quantity")
                    .font(.pearlCaption.weight(.semibold))
                    .foregroundColor(.tertiaryText)
                    .textCase(.uppercase)
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        if state.wrappedValue.quantity > 1 {
                            state.wrappedValue.quantity -= 1
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(state.wrappedValue.quantity > 1 ? .pearlGreen : .quaternaryText)
                    }
                    .disabled(state.wrappedValue.quantity <= 1)

                    Text("\(state.wrappedValue.quantity)")
                        .font(.pearlTitle3)
                        .foregroundColor(.primaryText)
                        .frame(minWidth: 28)

                    Button {
                        state.wrappedValue.quantity += 1
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.pearlGreen)
                    }
                }
            }

            // Macro preview
            HStack(spacing: 14) {
                macroChip(label: "P", value: state.wrappedValue.baseProtein * state.wrappedValue.servingMultiplier * Double(state.wrappedValue.quantity), unit: "g")
                macroChip(label: "C", value: state.wrappedValue.baseCarbs * state.wrappedValue.servingMultiplier * Double(state.wrappedValue.quantity), unit: "g")
                macroChip(label: "F", value: state.wrappedValue.baseFat * state.wrappedValue.servingMultiplier * Double(state.wrappedValue.quantity), unit: "g")
            }
        }
        .padding(16)
        .glassBackground(cornerRadius: 18)
    }

    private func macroChip(label: String, value: Double, unit: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.pearlCaption2.weight(.bold))
                .foregroundColor(.pearlMint)
            Text("\(Int(value))\(unit)")
                .font(.pearlCaption)
                .foregroundColor(.primaryText)
        }
    }

    private func formatted(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.1f", v)
    }

    private func applyChanges() {
        for state in entryStates {
            guard let item = meal.foodItems.first(where: { $0.id == state.id }) else { continue }
            let factor = state.servingMultiplier * Double(state.quantity)
            item.servingSize = state.baseServingSize * state.servingMultiplier
            item.calories = state.baseCalories * factor
            item.proteinG = state.baseProtein * factor
            item.carbsG = state.baseCarbs * factor
            item.fatG = state.baseFat * factor
            item.fiberG = state.baseFiber * factor
        }
        meal.mealType = editedMealType
        meal.loggedAt = editedLoggedAt
        PersistenceService.shared.save()
    }
}
