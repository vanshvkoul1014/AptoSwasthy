import Foundation

/// Heuristic mapping from a UserProfile to PCA z-scores for ParametricBody.
///
/// IMPORTANT: the CAESAR-norm-WSX shape space is normalized for **W**eight,
/// **S**tature, and sitting-height ratio - those dimensions have been factored
/// out of the PCA basis. Therefore PC scores must NOT be used to encode height
/// or BMI; those are applied as raw mesh scaling in BodyModelView. PC scores
/// here only encode residual shape variation (sex, age proportions).
enum BodyShapeMapper {
    static func scores(for profile: UserProfile, kComponents: Int) -> [Float] {
        var scores = [Float](repeating: 0, count: kComponents)

        // PC1 (largest residual component in CAESAR-norm-WSX) tends to align
        // with male/female body-shape contrast in this normalized space.
        let sexBias: Float
        switch profile.biologicalSex {
        case .male:         sexBias =  1.0
        case .female:       sexBias = -1.0
        case .notSpecified: sexBias =  0.0
        }

        // Slight age-related body-composition drift (older → softer torso).
        let ageBias = clamp(Float((Double(profile.age) - 35.0) / 25.0) * 0.4, -0.8, 0.8)

        if kComponents > 0 { scores[0] = sexBias }
        if kComponents > 1 { scores[1] = ageBias * 0.5 }

        return scores
    }

    /// Per-axis scaling applied to the mesh node so the avatar visually matches
    /// the user's actual stature, BMI, and muscle mass percentage.
    /// - Y (vertical) is scaled directly by stature ratio.
    /// - X/Z (girth) are derived so the resulting volume yields the target BMI,
    ///   then nudged ±10% based on muscle % (more muscle → slightly broader
    ///   shoulders/arms while keeping the same overall mass).
    static func scale(for profile: UserProfile,
                      muscleMassPercent: Double) -> (girth: Float, height: Float) {
        let refHeightCm: Double = 170.0   // approx. CAESAR-norm-WSX mean stature
        let refBMI: Double = 22.0         // healthy mid-range
        let refMuscle: Double = 30.0      // healthy adult average
        let hScale = profile.heightCm / refHeightCm
        let baseGirth = (profile.bmi / refBMI * hScale).squareRoot()
        // ±10% girth swing across the typical muscle-mass range (15%–50%).
        let muscleBoost = 1.0 + (muscleMassPercent - refMuscle) / 100.0 * 0.5
        return (Float(baseGirth * muscleBoost), Float(hScale))
    }

    /// Estimated muscle-mass percentage from profile data. Starts from a
    /// sex-typical baseline then adjusts for activity level, age, and BMI.
    /// Values are clamped to a plausible [15, 50] range.
    static func estimatedMuscleMassPercent(for profile: UserProfile) -> Double {
        let base: Double
        switch profile.biologicalSex {
        case .male:         base = 40
        case .female:       base = 30
        case .notSpecified: base = 35
        }

        let activityAdjust: Double
        switch profile.activityLevel {
        case .sedentary:        activityAdjust = -4
        case .lightlyActive:    activityAdjust = -2
        case .moderatelyActive: activityAdjust =  0
        case .veryActive:       activityAdjust =  3
        case .extremelyActive:  activityAdjust =  5
        }

        // Adult lean mass peaks in the 20s–30s, drifts ≈1.5% lower per decade after.
        let ageAdjust = profile.age > 30 ? -Double(profile.age - 30) * 0.15 : 0

        // Low BMI → less muscle; obesity shifts composition toward fat.
        let bmiAdjust: Double
        switch profile.bmi {
        case ..<18.5:   bmiAdjust = -3
        case 18.5..<25: bmiAdjust =  0
        case 25..<30:   bmiAdjust = -1
        case 30..<35:   bmiAdjust = -3
        default:        bmiAdjust = -5
        }

        let raw = base + activityAdjust + ageAdjust + bmiAdjust
        return min(max(raw, 15), 50)
    }

    private static func clamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
        min(max(x, lo), hi)
    }
}
