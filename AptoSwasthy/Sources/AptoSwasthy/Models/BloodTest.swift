import Foundation
import SwiftData

@Model
final class BloodTest: Identifiable {
    var id: UUID
    var importedAt: Date
    var testDate: Date?
    var labName: String?
    var biomarkers: [BloodBiomarker]
    var rawText: String

    init(
        id: UUID = UUID(),
        importedAt: Date = Date(),
        testDate: Date? = nil,
        labName: String? = nil,
        biomarkers: [BloodBiomarker] = [],
        rawText: String = ""
    ) {
        self.id = id
        self.importedAt = importedAt
        self.testDate = testDate
        self.labName = labName
        self.biomarkers = biomarkers
        self.rawText = rawText
    }
}

struct BloodBiomarker: Codable {
    var name: String
    var value: Double
    var unit: String
    var referenceRange: String
    var isAbnormal: Bool

    static let known: [String: (unit: String, normalRange: ClosedRange<Double>)] = [
        "glucose": ("mg/dL", 70...99),
        "hba1c": ("%", 4.0...5.6),
        "total cholesterol": ("mg/dL", 0...199),
        "ldl": ("mg/dL", 0...99),
        "hdl": ("mg/dL", 40...200),
        "triglycerides": ("mg/dL", 0...149),
        "creatinine": ("mg/dL", 0.6...1.2),
        "sodium": ("mEq/L", 135...145),
        "potassium": ("mEq/L", 3.5...5.0),
        "hemoglobin": ("g/dL", 12.0...17.5),
        "tsh": ("mIU/L", 0.4...4.0),
        "vitamin d": ("ng/mL", 20...50),
        "b12": ("pg/mL", 200...900),
        "ferritin": ("ng/mL", 12...300)
    ]
}
