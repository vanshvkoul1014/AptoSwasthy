import Foundation
import SwiftData

@Model
final class DiseaseRisk {
    var id: UUID
    var condition: RiskCondition
    var tier: RiskTier
    var drivingFactors: [String]
    var recommendations: [String]
    var calculatedAt: Date
    var inputHash: String

    init(
        id: UUID = UUID(),
        condition: RiskCondition,
        tier: RiskTier,
        drivingFactors: [String] = [],
        recommendations: [String] = [],
        calculatedAt: Date = Date(),
        inputHash: String = ""
    ) {
        self.id = id
        self.condition = condition
        self.tier = tier
        self.drivingFactors = drivingFactors
        self.recommendations = recommendations
        self.calculatedAt = calculatedAt
        self.inputHash = inputHash
    }
}

enum RiskCondition: String, Codable, CaseIterable {
    case cardiovascularDisease = "Cardiovascular Disease"
    case type2Diabetes = "Type 2 Diabetes"
    case hypertension = "Hypertension"
    case stroke = "Stroke"
    case obesity = "Obesity"
    case depression = "Depression"
    case chronicKidneyDisease = "Chronic Kidney Disease"
    case osteoporosis = "Osteoporosis"
    case alzheimers = "Alzheimer's Disease"
    case lungCancer = "Lung Cancer"
    case colonCancer = "Colorectal Cancer"
    case sleepApnea = "Sleep Apnea"

    var description: String {
        switch self {
        case .cardiovascularDisease:
            return "Conditions affecting the heart and blood vessels, including heart attack and heart failure."
        case .type2Diabetes:
            return "A condition where blood sugar levels are chronically elevated due to insulin resistance."
        case .hypertension:
            return "Persistently elevated blood pressure that strains the heart and blood vessels."
        case .stroke:
            return "Sudden interruption of blood flow to the brain, causing cell death."
        case .obesity:
            return "Excessive body weight that increases risk for many other conditions."
        case .depression:
            return "A mood disorder characterized by persistent sadness and loss of interest."
        case .chronicKidneyDisease:
            return "Progressive loss of kidney function over time."
        case .osteoporosis:
            return "Decreased bone density that increases fracture risk."
        case .alzheimers:
            return "A progressive neurological disorder that destroys memory and thinking skills."
        case .lungCancer:
            return "Malignant growth in the lungs, strongly associated with smoking."
        case .colonCancer:
            return "Cancer of the large intestine, influenced by diet and lifestyle."
        case .sleepApnea:
            return "A condition where breathing repeatedly stops during sleep."
        }
    }
}

enum RiskTier: String, Codable, CaseIterable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"

    var color: String {
        switch self {
        case .low: return "green"
        case .moderate: return "yellow"
        case .high: return "red"
        }
    }
}

extension DiseaseRisk {
    /// Pearl's approximate 10-year probability estimate. Derived from the
    /// already-computed tier and driving-factor count so we don't need a
    /// schema migration. Ranges are intentionally wide - this is directional,
    /// not clinical. Condition-specific baselines nudge the numbers so two
    /// "moderate" risks don't read as identical.
    var estimatedPercent: Int {
        let base: ClosedRange<Double>
        switch tier {
        case .low:      base = 3...9
        case .moderate: base = 12...28
        case .high:     base = 34...62
        }

        // drivingFactors up-weight within the tier band.
        let factorWeight = min(Double(drivingFactors.count) / 5.0, 1.0)
        let span = base.upperBound - base.lowerBound
        let inTier = base.lowerBound + span * factorWeight

        // Per-condition nudge (+/-3pp) so different conditions read distinctly.
        let nudge: Double
        switch condition {
        case .cardiovascularDisease, .hypertension: nudge = 2
        case .type2Diabetes, .obesity:              nudge = 1
        case .stroke, .alzheimers:                  nudge = -1
        case .lungCancer, .colonCancer:             nudge = -2
        default:                                    nudge = 0
        }

        let v = max(1.0, min(80.0, inTier + nudge))
        return Int(v.rounded())
    }
}
