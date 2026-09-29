import Foundation
import SwiftData

@Model
final class HealthMetric {
    var id: UUID
    var type: MetricType
    var value: Double
    var unit: String
    var recordedAt: Date
    var source: String

    init(
        id: UUID = UUID(),
        type: MetricType,
        value: Double,
        unit: String,
        recordedAt: Date = Date(),
        source: String = "Manual"
    ) {
        self.id = id
        self.type = type
        self.value = value
        self.unit = unit
        self.recordedAt = recordedAt
        self.source = source
    }
}

enum MetricType: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case steps = "Steps"
    case heartRate = "Heart Rate"
    case restingHeartRate = "Resting Heart Rate"
    case weight = "Weight"
    case bloodPressureSystolic = "Blood Pressure (Systolic)"
    case bloodPressureDiastolic = "Blood Pressure (Diastolic)"
    case bloodGlucose = "Blood Glucose"
    case cholesterolTotal = "Total Cholesterol"
    case cholesterolLDL = "LDL Cholesterol"
    case cholesterolHDL = "HDL Cholesterol"
    case triglycerides = "Triglycerides"
    case sleepDuration = "Sleep Duration"
    case oxygenSaturation = "Oxygen Saturation"
    case bodyFatPercentage = "Body Fat %"
    case vo2Max = "VO2 Max"
    case waterIntake = "Water Intake"
    case nutritionScore = "Nutrition Score"
    case fitnessScore = "Fitness Score"
    case heartRateVariability = "HRV"
    case recoveryScore = "Recovery"
    case stressScore = "Stress"
    case activeEnergy = "Active Energy"
    case exerciseMinutes = "Exercise Minutes"
    case caloriesConsumed = "Calories Consumed"
    case proteinConsumed = "Protein"
    case carbsConsumed = "Carbohydrates"
    case fatConsumed = "Fat"
    case fiberConsumed = "Fiber"
    case respiratoryRate = "Respiratory Rate"

    var defaultUnit: String {
        switch self {
        case .steps: return "steps"
        case .heartRate, .restingHeartRate: return "bpm"
        case .weight: return "kg"
        case .bloodPressureSystolic, .bloodPressureDiastolic: return "mmHg"
        case .bloodGlucose: return "mg/dL"
        case .cholesterolTotal, .cholesterolLDL, .cholesterolHDL, .triglycerides: return "mg/dL"
        case .sleepDuration: return "hours"
        case .oxygenSaturation: return "%"
        case .bodyFatPercentage: return "%"
        case .vo2Max: return "mL/kg/min"
        case .waterIntake: return "ml"
        case .nutritionScore, .fitnessScore, .recoveryScore, .stressScore: return "/100"
        case .heartRateVariability: return "ms"
        case .activeEnergy, .caloriesConsumed: return "kcal"
        case .exerciseMinutes: return "min"
        case .proteinConsumed, .carbsConsumed, .fatConsumed, .fiberConsumed: return "g"
        case .respiratoryRate: return "br/min"
        }
    }

    var icon: String {
        switch self {
        case .steps: return "figure.walk"
        case .heartRate, .restingHeartRate: return "heart.fill"
        case .weight: return "scalemass.fill"
        case .bloodPressureSystolic, .bloodPressureDiastolic: return "waveform.path.ecg"
        case .bloodGlucose: return "drop.fill"
        case .cholesterolTotal, .cholesterolLDL, .cholesterolHDL, .triglycerides: return "staroflife.fill"
        case .sleepDuration: return "moon.fill"
        case .oxygenSaturation: return "lungs.fill"
        case .bodyFatPercentage: return "person.fill"
        case .vo2Max: return "flame.fill"
        case .waterIntake: return "drop.fill"
        case .nutritionScore: return "leaf.fill"
        case .fitnessScore: return "bolt.fill"
        case .heartRateVariability: return "waveform.path"
        case .recoveryScore: return "arrow.clockwise.heart"
        case .stressScore: return "exclamationmark.triangle.fill"
        case .activeEnergy: return "flame.fill"
        case .exerciseMinutes: return "figure.run"
        case .caloriesConsumed: return "fork.knife"
        case .proteinConsumed: return "fish.fill"
        case .carbsConsumed: return "carrot.fill"
        case .fatConsumed: return "drop.triangle.fill"
        case .fiberConsumed: return "leaf"
        case .respiratoryRate: return "wind"
        }
    }
}
