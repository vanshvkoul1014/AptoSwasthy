import Foundation
import SwiftData

@Model
final class Meal {
    var id: UUID
    var name: String
    var mealType: MealType
    var loggedAt: Date
    @Relationship(deleteRule: .cascade) var foodItems: [FoodEntry]
    var notes: String

    init(
        id: UUID = UUID(),
        name: String = "",
        mealType: MealType,
        loggedAt: Date = Date(),
        foodItems: [FoodEntry] = [],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.mealType = mealType
        self.loggedAt = loggedAt
        self.foodItems = foodItems
        self.notes = notes
    }

    var totalCalories: Double { foodItems.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { foodItems.reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double { foodItems.reduce(0) { $0 + $1.carbsG } }
    var totalFat: Double { foodItems.reduce(0) { $0 + $1.fatG } }
    var totalFiber: Double { foodItems.reduce(0) { $0 + $1.fiberG } }
}

@Model
final class FoodEntry {
    var id: UUID
    var foodName: String
    var brandName: String?
    var servingSize: Double
    var servingUnit: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var sugarG: Double
    var sodiumMg: Double
    var saturatedFatG: Double
    var cholesterolMg: Double
    var vitaminAPercent: Double
    var vitaminCPercent: Double
    var calciumPercent: Double
    var ironPercent: Double
    var fdcId: String?
    var barcode: String?

    init(
        id: UUID = UUID(),
        foodName: String,
        brandName: String? = nil,
        servingSize: Double = 1.0,
        servingUnit: String = "serving",
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double = 0,
        sugarG: Double = 0,
        sodiumMg: Double = 0,
        saturatedFatG: Double = 0,
        cholesterolMg: Double = 0,
        vitaminAPercent: Double = 0,
        vitaminCPercent: Double = 0,
        calciumPercent: Double = 0,
        ironPercent: Double = 0,
        fdcId: String? = nil,
        barcode: String? = nil
    ) {
        self.id = id
        self.foodName = foodName
        self.brandName = brandName
        self.servingSize = servingSize
        self.servingUnit = servingUnit
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
        self.saturatedFatG = saturatedFatG
        self.cholesterolMg = cholesterolMg
        self.vitaminAPercent = vitaminAPercent
        self.vitaminCPercent = vitaminCPercent
        self.calciumPercent = calciumPercent
        self.ironPercent = ironPercent
        self.fdcId = fdcId
        self.barcode = barcode
    }
}

enum MealType: String, Codable, CaseIterable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snacks"

    static func fromHour(_ hour: Int) -> MealType {
        switch hour {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}
