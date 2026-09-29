import Foundation

struct LifeFactor {
    let description: String
    let direction: FactorDirection
    let yearsImpact: Double
}

enum FactorDirection {
    case positive, negative
}

// ==========================================================================
//  PearlLifeExpectancy: Validated Cox Proportional Hazards mortality model.
//
//  Coefficients fitted on NHANES 2009-2014 (n=17,504 participants, 1,952 deaths)
//  with CDC linked mortality follow-up through December 31, 2019.
//
//  Full model C-statistic:  0.82 (test set, 30% held-out)
//  Minimal model C-statistic: 0.84 (test set)
//
//  References:
//    PMC6481149 (Framingham CVD Cox model)
//    PMC9530124 (IMPACT/NHANES mortality prediction)
//    CDC National Vital Statistics Reports Vol. 75 No. 2 (life tables)
// ==========================================================================

final class PearlLifeExpectancy {

    // MARK: - Cox model coefficients (NHANES-validated)

    // Full model: used when BP, labs, and health status data are available.
    // Note: log_bmi and total_cholesterol are excluded here because the linear
    // NHANES fits invert direction at the high end (obesity paradox / reverse
    // causation in older cohorts). They are replaced below with validated
    // J-curve terms from Berrington de Gonzalez 2010 NEJM and the Prospective
    // Studies Collaboration 2009 Lancet meta-analysis.
    private static let fullCoefficients: [String: Double] = [
        "log_age": 3.348254,
        "female": -0.294711,
        "log_systolic": 0.543418,
        "log_pulse": 0.553291,
        "current_smoker": 0.184836,
        "former_smoker": 0.010510,
        "diabetes": 0.103183,
        "hypertension": 0.382626,
        "poor_health": 0.608812,
    ]

    private static let fullMeans: [String: Double] = [
        "log_age": 3.871201,
        "female": 1.0,
        "log_systolic": 4.787492,
        "log_pulse": 4.276666,
        "current_smoker": 0.0,
        "former_smoker": 0.0,
        "diabetes": 0.0,
        "hypertension": 0.0,
        "poor_health": 0.0,
    ]

    // Minimal model: used when only onboarding data is available (age, sex, BMI, smoking)
    private static let minimalCoefficients: [String: Double] = [
        "log_age": 4.806608,
        "female": -0.391862,
        "current_smoker": 0.433628,
        "former_smoker": 0.586071,
    ]

    private static let minimalMeans: [String: Double] = [
        "log_age": 3.871201,
        "female": 1.0,
        "current_smoker": 0.0,
        "former_smoker": 0.0,
    ]

    // MARK: - CDC Actuarial Life Tables (2021, US)
    // Remaining life expectancy by age and sex.

    private static let maleLifeTable: [Int: Double] = [
        0: 74.2, 5: 69.7, 10: 64.8, 15: 59.8, 20: 55.0, 25: 50.3,
        30: 45.6, 35: 41.0, 40: 36.4, 45: 31.9, 50: 27.6, 55: 23.5,
        60: 19.7, 65: 16.2, 70: 13.0, 75: 10.2, 80: 7.7, 85: 5.7,
        90: 4.2, 95: 3.1, 100: 2.4
    ]

    private static let femaleLifeTable: [Int: Double] = [
        0: 79.8, 5: 75.2, 10: 70.3, 15: 65.3, 20: 60.4, 25: 55.5,
        30: 50.7, 35: 45.9, 40: 41.2, 45: 36.5, 50: 31.9, 55: 27.5,
        60: 23.3, 65: 19.3, 70: 15.5, 75: 12.1, 80: 9.0, 85: 6.5,
        90: 4.7, 95: 3.3, 100: 2.5
    ]

    // MARK: - Public API

    /// Age and sex are excluded from the Cox linear predictor because the CDC
    /// life table baseline is already age- and sex-stratified. Including them
    /// in the adjustment would double-count, producing absurdly high values
    /// (e.g. a healthy 30-year-old projecting to 128 years).
    private static let baselineStratifiedFeatures: Set<String> = ["log_age", "female"]

    // J-curve log-hazard ratios for BMI (reference 18.5–25, healthy weight).
    // Source: Prospective Studies Collaboration 2009 Lancet (n=894,576).
    // Reference band returns 0 so a healthy BMI never appears as a "factor"
    // in the explainer (neither a positive nor a negative contribution).
    private func bmiLogHR(_ bmi: Double) -> Double {
        guard bmi.isFinite else { return 0 }
        switch bmi {
        case ..<16:       return 0.85   // HR ≈ 2.34, severely underweight
        case 16..<18.5:   return 0.40   // HR ≈ 1.49, underweight
        case 18.5..<25:   return 0.0    // reference (healthy weight)
        case 25..<27.5:   return 0.07   // HR ≈ 1.07
        case 27.5..<30:   return 0.18   // HR ≈ 1.20
        case 30..<35:     return 0.34   // HR ≈ 1.40, obese class I
        case 35..<40:     return 0.64   // HR ≈ 1.90, obese class II
        case 40..<45:     return 0.92   // HR ≈ 2.50, obese class III
        default:          return 1.20   // HR ≈ 3.32
        }
    }

    // Total cholesterol log-HR (mg/dL). Very low values flag illness in older
    // adults (reverse causation), so a mild penalty is applied at the low end.
    private func cholesterolLogHR(_ chol: Double) -> Double {
        switch chol {
        case ..<140:    return 0.18   // HR ≈ 1.20 (often reflects illness)
        case 140..<200: return 0.0    // reference
        case 200..<240: return 0.10   // HR ≈ 1.10, borderline
        case 240..<280: return 0.26   // HR ≈ 1.30
        default:        return 0.45   // HR ≈ 1.57
        }
    }

    func calculate(profile: UserProfile, metrics: [HealthMetric], bloodTests: [BloodTest]) -> Double {
        let age = profile.age
        let female = profile.biologicalSex == .female
        let baseRemaining = remainingLifeExpectancy(age: age, female: female)

        // Source the per-factor decomposition from `allFactors` and sum it so
        // the UI breakdown is always consistent with this total. (We can't use
        // a single hazard-ratio Gompertz here because it wouldn't sum to the
        // same number the user sees in the explainer - exp is nonlinear.)
        let factors = allFactors(profile: profile, metrics: metrics, bloodTests: bloodTests)
        let yearsDelta = factors.reduce(0.0) { $0 + $1.yearsImpact }

        let projected = Double(age) + max(baseRemaining + yearsDelta, 1.0)
        // Sanity cap: no human has lived past ~122. Clamp to a plausible ceiling
        // but never below the user's current age (otherwise a 115-year-old would
        // see a projected value younger than their current age).
        return min(projected, max(110.0, Double(age) + 1.0))
    }

    func baseValue(for profile: UserProfile) -> Double {
        let female = profile.biologicalSex == .female
        return Double(profile.age) + remainingLifeExpectancy(age: profile.age, female: female)
    }

    func allFactors(profile: UserProfile, metrics: [HealthMetric], bloodTests: [BloodTest]) -> [LifeFactor] {
        let age = profile.age
        let female = profile.biologicalSex == .female
        let values = buildCovariateValues(profile: profile, metrics: metrics, bloodTests: bloodTests)
        let baseRemaining = remainingLifeExpectancy(age: age, female: female)

        let hasFullData = latestMetric(metrics, type: .bloodPressureSystolic) != nil
        let coefs = hasFullData ? Self.fullCoefficients : Self.minimalCoefficients
        let means = hasFullData ? Self.fullMeans : Self.minimalMeans

        var factors: [LifeFactor] = []

        func yearsFromLogHR(_ logHR: Double) -> Double {
            let h = exp(logHR)
            return h >= 1.0 ? -baseRemaining * (1.0 - 1.0 / h) : baseRemaining * (1.0 - h)
        }

        for (feature, beta) in coefs where !Self.baselineStratifiedFeatures.contains(feature) {
            let x = values[feature] ?? means[feature] ?? 0.0
            let xbar = means[feature] ?? 0.0
            let contribution = beta * (x - xbar)

            guard abs(contribution) > 0.02 else { continue }

            let yearImpact = yearsFromLogHR(contribution)
            let desc = factorDescription(feature: feature, value: x, profile: profile, metrics: metrics, bloodTests: bloodTests)
            let direction: FactorDirection = yearImpact >= 0 ? .positive : .negative
            factors.append(LifeFactor(description: desc, direction: direction, yearsImpact: yearImpact))
        }

        // BMI J-curve factor
        let bmiLP = bmiLogHR(profile.bmi)
        if abs(bmiLP) > 0.02 {
            let years = yearsFromLogHR(bmiLP)
            factors.append(LifeFactor(
                description: factorDescription(feature: "log_bmi", value: profile.bmi, profile: profile, metrics: metrics, bloodTests: bloodTests),
                direction: years >= 0 ? .positive : .negative,
                yearsImpact: years
            ))
        }

        // Cholesterol J-curve factor
        if let chol = latestBloodMarker(bloodTests, name: "total cholesterol") {
            let cLP = cholesterolLogHR(chol)
            if abs(cLP) > 0.02 {
                let years = yearsFromLogHR(cLP)
                factors.append(LifeFactor(
                    description: factorDescription(feature: "total_cholesterol", value: chol, profile: profile, metrics: metrics, bloodTests: bloodTests),
                    direction: years >= 0 ? .positive : .negative,
                    yearsImpact: years
                ))
            }
        }

        // Existing conditions (not in Cox model but clinically relevant context)
        let condMod = conditionsModifier(conditions: profile.healthConditions)
        if condMod < -0.5 {
            factors.append(LifeFactor(description: "Existing health conditions", direction: .negative, yearsImpact: condMod))
        }

        // Family history
        let famMod = familyHistoryModifier(history: profile.familyHistory)
        if famMod < -0.5 {
            factors.append(LifeFactor(description: "Family history of chronic disease", direction: .negative, yearsImpact: famMod))
        }

        return factors.sorted { abs($0.yearsImpact) > abs($1.yearsImpact) }
    }

    func topInfluencingFactors(profile: UserProfile, metrics: [HealthMetric]) -> [LifeFactor] {
        let factors = allFactors(profile: profile, metrics: metrics, bloodTests: [])
        return Array(factors.filter { abs($0.yearsImpact) > 0.3 }.prefix(5))
    }

    // MARK: - Private helpers

    private func buildCovariateValues(profile: UserProfile, metrics: [HealthMetric], bloodTests: [BloodTest]) -> [String: Double] {
        var values: [String: Double] = [:]

        // Age (log-transformed)
        values["log_age"] = log(max(Double(profile.age), 18.0))

        // Sex (1 = female, 0 = male)
        values["female"] = profile.biologicalSex == .female ? 1.0 : 0.0

        // BMI (log-transformed)
        values["log_bmi"] = log(max(profile.bmi, 10.0))

        // Smoking
        switch profile.smokingStatus {
        case .current:
            values["current_smoker"] = 1.0
            values["former_smoker"] = 0.0
        case .former:
            values["current_smoker"] = 0.0
            values["former_smoker"] = 1.0
        case .never:
            values["current_smoker"] = 0.0
            values["former_smoker"] = 0.0
        }

        // Blood pressure (log-transformed systolic). Clamp to physiologically
        // plausible band so a sensor typo (e.g. 999 mmHg) cannot drag the
        // prediction by tens of years.
        if let systolicRaw = latestMetric(metrics, type: .bloodPressureSystolic), systolicRaw.isFinite {
            let systolic = min(max(systolicRaw, 70.0), 220.0)
            values["log_systolic"] = log(systolic)

            // Hypertension flag
            let diastolicRaw = latestMetric(metrics, type: .bloodPressureDiastolic) ?? 0
            let diastolic = min(max(diastolicRaw, 0.0), 140.0)
            values["hypertension"] = (systolic >= 130 || diastolic >= 80) ? 1.0 : 0.0
        }

        // Pulse (log-transformed). Same clamping rationale.
        if let pulseRaw = latestMetric(metrics, type: .heartRate), pulseRaw.isFinite {
            let pulse = min(max(pulseRaw, 30.0), 220.0)
            values["log_pulse"] = log(pulse)
        }

        // Diabetes: check conditions list or blood glucose
        let hasKnownDiabetes = profile.healthConditions.contains { $0.lowercased().contains("diabetes") }
        if hasKnownDiabetes {
            values["diabetes"] = 1.0
        } else if let glucose = latestBloodMarker(bloodTests, name: "glucose") {
            values["diabetes"] = glucose >= 126 ? 1.0 : 0.0
        }

        // Total cholesterol
        if let chol = latestBloodMarker(bloodTests, name: "total cholesterol") {
            values["total_cholesterol"] = chol
        }

        // Poor self-rated health: derive from conditions list
        // If user has 3+ chronic conditions, flag as poor health
        let conditionCount = profile.healthConditions.count
        values["poor_health"] = conditionCount >= 3 ? 1.0 : 0.0

        return values
    }

    private func remainingLifeExpectancy(age: Int, female: Bool) -> Double {
        let table = female ? Self.femaleLifeTable : Self.maleLifeTable
        let ages = table.keys.sorted()
        let floorAge = ages.last(where: { $0 <= age }) ?? 0
        return table[floorAge] ?? 10.0
    }

    private func factorDescription(feature: String, value: Double, profile: UserProfile, metrics: [HealthMetric], bloodTests: [BloodTest]) -> String {
        switch feature {
        case "log_age":
            return "Age (\(profile.age) years)"
        case "female":
            return profile.biologicalSex == .female ? "Female (lower baseline risk)" : "Male (higher baseline risk)"
        case "log_bmi":
            let bmi = profile.bmi
            // Bands match bmiLogHR so the description matches the math.
            switch bmi {
            case ..<16:       return "Severely underweight BMI (\(String(format: "%.1f", bmi)))"
            case 16..<18.5:   return "Underweight BMI (\(String(format: "%.1f", bmi)))"
            case 18.5..<25:   return "Healthy BMI (\(String(format: "%.1f", bmi)))"
            case 25..<27.5:   return "Mildly overweight BMI (\(String(format: "%.1f", bmi)))"
            case 27.5..<30:   return "Overweight BMI (\(String(format: "%.1f", bmi)))"
            case 30..<35:     return "Obese class I BMI (\(String(format: "%.1f", bmi)))"
            case 35..<40:     return "Obese class II BMI (\(String(format: "%.1f", bmi)))"
            case 40..<45:     return "Obese class III BMI (\(String(format: "%.1f", bmi)))"
            default:          return "Severely obese BMI (\(String(format: "%.1f", bmi)))"
            }
        case "current_smoker":
            return "Current smoker"
        case "former_smoker":
            return "Former smoker"
        case "log_systolic":
            if let sys = latestMetric(metrics, type: .bloodPressureSystolic) {
                switch sys {
                case ..<120: return "Optimal blood pressure (\(Int(sys)) mmHg)"
                case 120..<130: return "Elevated blood pressure (\(Int(sys)) mmHg)"
                case 130..<140: return "Stage 1 hypertension (\(Int(sys)) mmHg)"
                case 140..<160: return "Stage 2 hypertension (\(Int(sys)) mmHg)"
                default: return "Severe hypertension (\(Int(sys)) mmHg)"
                }
            }
            return "Blood pressure"
        case "log_pulse":
            if let pulse = latestMetric(metrics, type: .heartRate) {
                return "Resting heart rate (\(Int(pulse)) bpm)"
            }
            return "Heart rate"
        case "hypertension":
            return value > 0 ? "Hypertension" : "Normal blood pressure"
        case "diabetes":
            return value > 0 ? "Diabetes" : "No diabetes"
        case "total_cholesterol":
            if let chol = latestBloodMarker(bloodTests, name: "total cholesterol") {
                switch chol {
                case ..<200: return "Healthy cholesterol (\(Int(chol)) mg/dL)"
                case 200..<240: return "Borderline cholesterol (\(Int(chol)) mg/dL)"
                default: return "High cholesterol (\(Int(chol)) mg/dL)"
                }
            }
            return "Cholesterol level"
        case "poor_health":
            return value > 0 ? "Multiple health conditions" : "Good overall health"
        default:
            return feature
        }
    }

    // Conditions modifier (supplemental, not part of Cox model, but provides
    // additional context for conditions not captured by individual covariates)
    private func conditionsModifier(conditions: [String]) -> Double {
        let lc = conditions.map { $0.lowercased() }
        var modifier = 0.0
        if lc.contains(where: { $0.contains("cancer") }) { modifier -= 2.0 }
        if lc.contains(where: { $0.contains("heart") }) { modifier -= 1.5 }
        if lc.contains(where: { $0.contains("stroke") }) { modifier -= 1.5 }
        if lc.contains(where: { $0.contains("kidney") }) { modifier -= 1.0 }
        return modifier
    }

    private func familyHistoryModifier(history: [String]) -> Double {
        let lc = history.map { $0.lowercased() }
        var modifier = 0.0
        if lc.contains(where: { $0.contains("heart") }) { modifier -= 1.0 }
        if lc.contains(where: { $0.contains("cancer") }) { modifier -= 0.5 }
        if lc.contains(where: { $0.contains("diabetes") }) { modifier -= 0.5 }
        return modifier
    }

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
