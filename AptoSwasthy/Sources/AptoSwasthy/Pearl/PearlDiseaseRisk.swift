import Foundation

final class PearlDiseaseRisk {

    func assessAll(profile: UserProfile, metrics: [HealthMetric], bloodTests: [BloodTest]) -> [DiseaseRisk] {
        var risks: [DiseaseRisk] = []

        let bmi = profile.bmi
        let systolic = latestMetric(metrics, type: .bloodPressureSystolic) ?? 120
        // Default to 0, not 80, so missing diastolic never triggers a BP threshold on its own.
        let diastolic = latestMetric(metrics, type: .bloodPressureDiastolic) ?? 0
        let glucose = latestBloodMarker(bloodTests, name: "glucose")
        let totalCholesterol = latestBloodMarker(bloodTests, name: "total cholesterol")
        let hdl = latestBloodMarker(bloodTests, name: "hdl")
        risks.append(assessCardiovascular(profile: profile, metrics: metrics, systolic: systolic, hdl: hdl, totalCholesterol: totalCholesterol))
        risks.append(assessDiabetes(profile: profile, bmi: bmi, glucose: glucose))
        risks.append(assessHypertension(profile: profile, systolic: systolic, diastolic: diastolic))
        risks.append(assessStroke(profile: profile, systolic: systolic, totalCholesterol: totalCholesterol))
        risks.append(assessObesity(profile: profile, bmi: bmi))
        risks.append(assessSleepApnea(profile: profile, bmi: bmi, metrics: metrics))
        risks.append(assessOsteoporosis(profile: profile))

        if profile.smokingStatus == .current {
            risks.append(assessLungCancer(profile: profile))
        }

        return risks
    }

    // MARK: - Individual Assessments

    private func assessCardiovascular(
        profile: UserProfile,
        metrics: [HealthMetric],
        systolic: Double,
        hdl: Double?,
        totalCholesterol: Double?
    ) -> DiseaseRisk {
        var score = 0.0
        var factors: [String] = []
        var recs: [String] = []

        // Framingham-inspired scoring
        if profile.age > 55 { score += 2; factors.append("Age above 55") }
        else if profile.age > 45 { score += 1 }

        if profile.biologicalSex == .male { score += 1 }

        if systolic >= 140 { score += 2; factors.append("Elevated blood pressure (\(Int(systolic)) mmHg)") }
        else if systolic >= 130 { score += 1 }

        if let tc = totalCholesterol, tc >= 240 { score += 2; factors.append("High total cholesterol (\(Int(tc)) mg/dL)") }
        if let h = hdl, h < 40 { score += 2; factors.append("Low HDL cholesterol (\(Int(h)) mg/dL)") }

        if profile.smokingStatus == .current { score += 3; factors.append("Current smoker") }
        if profile.activityLevel == .sedentary { score += 1; factors.append("Sedentary lifestyle") }
        if profile.familyHistory.contains(where: { $0.lowercased().contains("heart") }) { score += 2; factors.append("Family history of heart disease") }
        if profile.bmi >= 30 { score += 1 }

        let tier: RiskTier = score >= 6 ? .high : score >= 3 ? .moderate : .low
        if tier == .moderate || tier == .high {
            recs.append("Aim for 150 minutes of moderate aerobic activity per week")
            recs.append("Limit saturated fat and increase fiber intake")
            recs.append("Monitor blood pressure regularly")
        }

        return DiseaseRisk(condition: .cardiovascularDisease, tier: tier, drivingFactors: factors, recommendations: recs)
    }

    private func assessDiabetes(profile: UserProfile, bmi: Double, glucose: Double?) -> DiseaseRisk {
        var score = 0.0
        var factors: [String] = []
        var recs: [String] = []

        if bmi >= 30 { score += 3; factors.append("BMI of \(String(format: "%.1f", bmi))") }
        else if bmi >= 25 { score += 1 }

        if let g = glucose {
            if g >= 126 { score += 4; factors.append("Fasting glucose of \(Int(g)) mg/dL (diabetic range)") }
            else if g >= 100 { score += 2; factors.append("Fasting glucose of \(Int(g)) mg/dL (pre-diabetic range)") }
        }

        if profile.activityLevel == .sedentary { score += 1; factors.append("Sedentary lifestyle") }
        if profile.familyHistory.contains(where: { $0.lowercased().contains("diabetes") }) { score += 2; factors.append("Family history of diabetes") }
        if profile.age > 45 { score += 1 }
        if profile.smokingStatus == .current { score += 1 }

        let tier: RiskTier = score >= 6 ? .high : score >= 3 ? .moderate : .low
        if tier != .low {
            recs.append("Reduce refined carbohydrate intake")
            recs.append("Aim for at least 30 minutes of walking daily")
            recs.append("Request a fasting glucose test at your next check-up")
        }

        return DiseaseRisk(condition: .type2Diabetes, tier: tier, drivingFactors: factors, recommendations: recs)
    }

    private func assessHypertension(profile: UserProfile, systolic: Double, diastolic: Double) -> DiseaseRisk {
        var factors: [String] = []
        var recs: [String] = []
        var score = 0.0

        let bpLabel = diastolic > 0 ? "\(Int(systolic))/\(Int(diastolic)) mmHg" : "\(Int(systolic)) mmHg systolic"
        if systolic >= 140 || diastolic >= 90 { score += 4; factors.append("Blood pressure \(bpLabel)") }
        else if systolic >= 130 || diastolic >= 80 { score += 2; factors.append("Elevated blood pressure \(bpLabel)") }

        if profile.smokingStatus == .current { score += 1 }
        if profile.vapes { score += 1 }
        if profile.bmi >= 30 { score += 1 }
        if profile.alcoholFrequency == .daily || profile.alcoholFrequency == .several { score += 1 }
        if profile.alcoholBingeFrequency == .weekly || profile.alcoholBingeFrequency == .several { score += 1; factors.append("Frequent binge drinking") }
        if profile.processedFoodFrequency == .mostly || profile.processedFoodFrequency == .often { score += 1; factors.append("High ultra-processed food intake") }
        if profile.familyHistory.contains(where: { $0.lowercased().contains("hypertension") || $0.lowercased().contains("blood pressure") }) {
            score += 1; factors.append("Family history of hypertension")
        }

        let tier: RiskTier = score >= 5 ? .high : score >= 2 ? .moderate : .low
        if tier != .low {
            recs.append("Reduce sodium intake to under 2,300mg per day")
            recs.append("Limit alcohol consumption")
            recs.append("Practice stress reduction techniques daily")
        }

        return DiseaseRisk(condition: .hypertension, tier: tier, drivingFactors: factors, recommendations: recs)
    }

    private func assessStroke(profile: UserProfile, systolic: Double, totalCholesterol: Double?) -> DiseaseRisk {
        var score = 0.0
        var factors: [String] = []
        var recs: [String] = []

        if systolic >= 140 { score += 3; factors.append("High blood pressure") }
        if profile.smokingStatus == .current { score += 3; factors.append("Current smoker") }
        if profile.age > 65 { score += 2 }
        if let tc = totalCholesterol, tc >= 240 { score += 1 }
        if profile.familyHistory.contains(where: { $0.lowercased().contains("stroke") }) { score += 2; factors.append("Family history of stroke") }
        if profile.activityLevel == .sedentary { score += 1 }

        let tier: RiskTier = score >= 6 ? .high : score >= 3 ? .moderate : .low
        if tier != .low {
            recs.append("Control blood pressure. It's the #1 modifiable stroke risk factor.")
            recs.append("If you smoke, speak with your doctor about cessation options")
        }

        return DiseaseRisk(condition: .stroke, tier: tier, drivingFactors: factors, recommendations: recs)
    }

    private func assessObesity(profile: UserProfile, bmi: Double) -> DiseaseRisk {
        let tier: RiskTier = bmi >= 30 ? .high : bmi >= 25 ? .moderate : .low
        let factors: [String] = bmi >= 25 ? ["Current BMI of \(String(format: "%.1f", bmi))"] : []
        var recs: [String] = []
        if tier != .low {
            recs.append("Focus on a caloric deficit of 300–500 kcal per day")
            recs.append("Increase daily step count gradually toward 8,000–10,000")
            recs.append("Prioritize protein at each meal to preserve muscle mass")
        }
        return DiseaseRisk(condition: .obesity, tier: tier, drivingFactors: factors, recommendations: recs)
    }

    private func assessSleepApnea(profile: UserProfile, bmi: Double, metrics: [HealthMetric]) -> DiseaseRisk {
        var score = 0.0
        var factors: [String] = []

        if bmi >= 30 { score += 3; factors.append("BMI above 30") }
        else if bmi >= 25 { score += 1 }
        if profile.biologicalSex == .male { score += 1 }
        if profile.age > 50 { score += 1 }
        if profile.sleepHoursPerNight < 6 { score += 1 }

        let tier: RiskTier = score >= 4 ? .high : score >= 2 ? .moderate : .low
        return DiseaseRisk(
            condition: .sleepApnea,
            tier: tier,
            drivingFactors: factors,
            recommendations: tier != .low ? ["Consider a sleep study if you experience snoring or daytime fatigue"] : []
        )
    }

    private func assessOsteoporosis(profile: UserProfile) -> DiseaseRisk {
        var score = 0.0
        var factors: [String] = []

        if profile.biologicalSex == .female && profile.age > 50 { score += 3; factors.append("Post-menopausal female") }
        if profile.activityLevel == .sedentary { score += 1 }
        if profile.smokingStatus == .current { score += 1 }
        if profile.familyHistory.contains(where: { $0.lowercased().contains("osteoporosis") || $0.lowercased().contains("fracture") }) { score += 2 }

        let tier: RiskTier = score >= 4 ? .high : score >= 2 ? .moderate : .low
        return DiseaseRisk(
            condition: .osteoporosis,
            tier: tier,
            drivingFactors: factors,
            recommendations: tier != .low ? ["Ensure adequate calcium and vitamin D intake", "Include weight-bearing exercise 3+ days per week"] : []
        )
    }

    private func assessLungCancer(profile: UserProfile) -> DiseaseRisk {
        let factors = ["Current smoker"]
        return DiseaseRisk(
            condition: .lungCancer,
            tier: profile.age > 50 ? .high : .moderate,
            drivingFactors: factors,
            recommendations: ["Speak with your doctor about low-dose CT lung cancer screening", "Quitting smoking now reduces risk significantly within years"]
        )
    }

    // MARK: - Helpers

    private func latestMetric(_ metrics: [HealthMetric], type: MetricType) -> Double? {
        metrics.filter { $0.type == type }.sorted { $0.recordedAt > $1.recordedAt }.first?.value
    }

    private func latestBloodMarker(_ tests: [BloodTest], name: String) -> Double? {
        let lname = name.lowercased()
        for test in tests.sorted(by: { ($0.testDate ?? $0.importedAt) > ($1.testDate ?? $1.importedAt) }) {
            if let marker = test.biomarkers.first(where: { $0.name.lowercased().contains(lname) }) {
                return marker.value
            }
        }
        return nil
    }
}
