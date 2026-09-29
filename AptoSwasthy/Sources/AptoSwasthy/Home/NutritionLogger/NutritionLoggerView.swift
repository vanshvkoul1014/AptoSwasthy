import SwiftUI

struct NutritionLoggerView: View {
    var vm: HomeViewModel
    @Binding var showAddFood: Bool
    @State private var showWaterAdd = false
    @State private var waterAmountMl: Double = 250
    @State private var showScoreDetail = false
    @State private var mealToEdit: Meal? = nil

    var mealGroups: [(MealType, [Meal])] {
        let grouped = Dictionary(grouping: vm.todayMeals.filter { $0.foodItems.first?.foodName != "Water" }) { $0.mealType }
        return MealType.allCases.compactMap { type in
            guard let meals = grouped[type], !meals.isEmpty else { return nil }
            return (type, meals)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Nutrition")
                    .font(.pearlTitle3).foregroundColor(.primaryText)
                Spacer()
                Button { showAddFood = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add Food")
                    }
                    .font(.pearlSubheadline)
                    .foregroundColor(.pearlGreen)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassBackground(cornerRadius: 20)
                }
            }

            // Score + macros
            NutritionScoreRow(
                score: vm.nutritionScore,
                calories: vm.totalCaloriesToday,
                protein: vm.totalProteinToday,
                carbs: vm.totalCarbsToday,
                fat: vm.totalFatToday
            )
            .contentShape(Rectangle())
            .onTapGesture { showScoreDetail = true }

            // Meal groups
            if vm.todayMeals.filter({ $0.foodItems.first?.foodName != "Water" }).isEmpty {
                Text("Nothing logged yet. Tap Add Food to get started.")
                    .font(.pearlSubheadline)
                    .foregroundColor(.quaternaryText)
                    .padding(.vertical, 12)
            } else {
                ForEach(mealGroups, id: \.0) { type, meals in
                    MealGroupSection(
                        type: type,
                        meals: meals,
                        unitPreference: vm.profile?.unitPreference ?? .imperial,
                        onEdit: { meal in mealToEdit = meal },
                        onDelete: { meal in vm.deleteMeal(meal) }
                    )
                }
            }

            // Water
            HStack {
                Image(systemName: "drop.fill").foregroundColor(.pearlMint)
                Text("Water").font(.pearlSubheadline).foregroundColor(.tertiaryText)
                Spacer()
                Button { showWaterAdd = true } label: {
                    Text("+ Log water")
                        .font(.pearlCaption)
                        .foregroundColor(.pearlGreen)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .glassBackground(cornerRadius: 22)
        .alert("Log Water", isPresented: $showWaterAdd) {
            Button("Log \(Int(waterAmountMl))ml") { vm.addWater(ml: waterAmountMl) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Quick-add water to your daily intake")
        }
        .sheet(isPresented: $showScoreDetail) {
            if let profile = vm.profile {
                NutritionScoreDetailView(
                    score: vm.nutritionScore,
                    meals: vm.todayMeals,
                    profile: profile
                )
            }
        }
        .sheet(item: $mealToEdit) { meal in
            MealEditView(meal: meal) { vm.refresh() }
        }
    }
}

struct NutritionScoreRow: View {
    let score: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    var scoreColor: Color {
        switch score {
        case 80...: return .riskLow
        case 60...: return .riskModerate
        default: return .riskHigh
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Score circle
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.glassBorder, lineWidth: 4)
                        .frame(width: 60, height: 60)
                    Circle()
                        .trim(from: 0, to: score / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(score))")
                        .font(.pearlHeadline).foregroundColor(.primaryText)
                }
                Text("Score").font(.pearlCaption2).foregroundColor(.tertiaryText)
            }
            .padding(.trailing, 16)

            // Macros
            VStack(alignment: .leading, spacing: 4) {
                MacroRow(name: "Calories", value: Int(calories), unit: "kcal")
                MacroRow(name: "Protein",  value: Int(protein),  unit: "g")
                MacroRow(name: "Carbs",    value: Int(carbs),    unit: "g")
                MacroRow(name: "Fat",      value: Int(fat),      unit: "g")
            }
        }
        .padding(14)
        .glassBackground(cornerRadius: 16)
    }
}

struct MacroRow: View {
    let name: String
    let value: Int
    let unit: String

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.pearlCaption)
                .foregroundColor(.tertiaryText)
                .frame(width: 60, alignment: .leading)
            Text("\(value) \(unit)")
                .font(.pearlCaption)
                .foregroundColor(.primaryText)
        }
    }
}

struct MealGroupSection: View {
    let type: MealType
    let meals: [Meal]
    let unitPreference: UnitSystem
    let onEdit: (Meal) -> Void
    let onDelete: (Meal) -> Void

    var totalCalories: Double { meals.reduce(0) { $0 + $1.totalCalories } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(type.rawValue)
                    .font(.pearlSubheadline.weight(.semibold))
                    .foregroundColor(.tertiaryText)
                Spacer()
                Text("\(Int(totalCalories)) kcal")
                    .font(.pearlCaption)
                    .foregroundColor(.quaternaryText)
            }

            ForEach(meals) { meal in
                ForEach(meal.foodItems) { item in
                    FoodItemRow(item: item)
                        .contextMenu {
                            Button { onEdit(meal) } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) { onDelete(meal) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onTapGesture { onEdit(meal) }
                }
            }
        }
    }
}

struct FoodItemRow: View {
    let item: FoodEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.foodName)
                    .font(.pearlSubheadline)
                    .foregroundColor(.primaryText)
                if let brand = item.brandName {
                    Text(brand)
                        .font(.pearlCaption)
                        .foregroundColor(.tertiaryText)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(item.calories)) kcal")
                    .font(.pearlSubheadline)
                    .foregroundColor(.primaryText)
                Text("\(String(format: "%.0f", item.servingSize)) \(item.servingUnit)")
                    .font(.pearlCaption2)
                    .foregroundColor(.quaternaryText)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.quaternaryText)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassBackground(cornerRadius: 12)
        .contentShape(Rectangle())
    }
}
