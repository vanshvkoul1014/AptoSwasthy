import Foundation

// =====================================================================
//  ProfileAPIService - cloud sync for the onboarding UserProfile.
//
//  Talks to the HttpApi provisioned by infra/template.yaml. Requests are
//  authenticated with the Cognito access token - the Lambda reads the
//  caller's sub directly from the JWT claims, so there is no userSub in
//  the wire payload.
//
//  If AWSConfig.apiBaseURL is nil (stack not yet deployed), every call
//  short-circuits with .cloudDisabled. Callers should treat that as a
//  no-op rather than an error, so the app stays usable offline-only
//  during development.
// =====================================================================

final class ProfileAPIService: @unchecked Sendable {
    static let shared = ProfileAPIService()
    private init() {}

    private let session = URLSession.shared
    private let keychain = KeychainService.shared

    // MARK: - Public

    func fetchProfile() async throws -> ProfileDTO? {
        let (data, http) = try await sendAuthed(path: "/profile", method: "GET", body: nil)
        switch http.statusCode {
        case 200:
            return try Self.decoder.decode(ProfileDTO.self, from: data)
        case 404:
            return nil
        case 401:
            throw ProfileAPIError.unauthorized
        default:
            throw ProfileAPIError.server(http.statusCode)
        }
    }

    func putProfile(_ dto: ProfileDTO) async throws {
        let body = try Self.encoder.encode(dto)
        let (_, http) = try await sendAuthed(path: "/profile", method: "PUT", body: body)
        switch http.statusCode {
        case 200...299: return
        case 401:       throw ProfileAPIError.unauthorized
        default:        throw ProfileAPIError.server(http.statusCode)
        }
    }

    // MARK: - Private

    /// Send an authenticated request. If the first attempt gets a 401, try to
    /// refresh the access token with the stored refresh token and retry once.
    /// Only after the retry 401s do we surface `.unauthorized` to the caller -
    /// which is the right signal to force re-login.
    private func sendAuthed(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        let (data, http) = try await send(path: path, method: method, body: body)
        guard http.statusCode == 401 else { return (data, http) }

        guard let tokens = keychain.loadTokens() else { throw ProfileAPIError.notAuthenticated }
        do {
            let refreshed = try await CognitoAuthService.shared.refreshTokens(refreshToken: tokens.refreshToken)
            keychain.saveTokens(refreshed)
        } catch {
            // Refresh failed - the refresh token is revoked or expired. Let the
            // caller handle it as a hard unauthorized (forces sign-in).
            throw ProfileAPIError.unauthorized
        }
        return try await send(path: path, method: method, body: body)
    }

    private func send(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        let request = try buildRequest(path: path, method: method, body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProfileAPIError.badResponse }
        return (data, http)
    }

    private func buildRequest(path: String, method: String, body: Data?) throws -> URLRequest {
        guard let base = AWSConfig.apiBaseURL, !base.isEmpty,
              let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)
        else { throw ProfileAPIError.cloudDisabled }

        guard let tokens = keychain.loadTokens() else {
            throw ProfileAPIError.notAuthenticated
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 15
        return req
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

enum ProfileAPIError: LocalizedError {
    case cloudDisabled
    case notAuthenticated
    case unauthorized
    case badResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .cloudDisabled:    return "Cloud sync is not configured yet."
        case .notAuthenticated: return "You're not signed in."
        case .unauthorized:     return "Session expired. Please sign in again."
        case .badResponse:      return "Unexpected server response."
        case .server(let code): return "Profile service error (\(code))."
        }
    }
}

// =====================================================================
// MARK: - Wire format
// =====================================================================

struct ProfileDTO: Codable {
    var name: String
    var dateOfBirth: Date
    var biologicalSex: String
    var ethnicity: String
    var heightCm: Double
    var weightKg: Double
    var activityLevel: String
    var activityMinutesPerSession: Int
    var sleepBedtime: Date
    var sleepWakeTime: Date
    var sleepHoursPerNight: Double
    var healthConditions: [String]
    var medications: [String]
    var familyHistory: [String]
    var smokingStatus: String
    var alcoholFrequency: String
    var healthGoals: [String]
    var unitPreference: String
    var onboardingComplete: Bool
    var connectedApps: [String]
    var createdAt: Date

    // Rich lifestyle - all optional on the wire so profiles stored by older
    // app versions still decode cleanly. Defaults applied in toUserProfile().
    var dietType: String?
    var mealsPerDay: Int?
    var fastFoodPerWeek: Int?
    var waterGlassesPerDay: Int?
    var caffeineCupsPerDay: Int?
    var addedSugarServingsPerDay: Int?
    var smokingPackYears: Double?
    var yearsSmoking: Int?
    var yearsSinceQuitSmoking: Int?
    var alcoholDrinksPerWeek: Int?
    var stressLevel: Int?
    var sleepQuality: String?
    var screenTimeHoursPerDay: Double?
    var exerciseTypes: [String]?
    var biographyNote: String?

    // v3 granular lifestyle fields
    var cigarettesPerDay: Int?
    var vapes: Bool?
    var secondhandSmokeExposure: String?
    var cannabisUseFrequency: String?
    var alcoholBingeFrequency: String?
    var alcoholFreeDaysPerWeek: Int?
    var alcoholBeverageTypes: [String]?
    var vegetableServingsPerDay: Int?
    var fruitServingsPerDay: Int?
    var homeCookedMealsPerWeek: Int?
    var lateNightEatingTimesPerWeek: Int?
    var processedFoodFrequency: String?
    var emotionalEatingFrequency: String?
    var eatingWindowHours: Int?
    var proteinSources: [String]?
}

extension ProfileDTO {
    init(from p: UserProfile) {
        self.name = p.name
        self.dateOfBirth = p.dateOfBirth
        self.biologicalSex = p.biologicalSex.rawValue
        self.ethnicity = p.ethnicity.rawValue
        self.heightCm = p.heightCm
        self.weightKg = p.weightKg
        self.activityLevel = p.activityLevel.rawValue
        self.activityMinutesPerSession = p.activityMinutesPerSession
        self.sleepBedtime = p.sleepBedtime
        self.sleepWakeTime = p.sleepWakeTime
        self.sleepHoursPerNight = p.sleepHoursPerNight
        self.healthConditions = p.healthConditions
        self.medications = p.medications
        self.familyHistory = p.familyHistory
        self.smokingStatus = p.smokingStatus.rawValue
        self.alcoholFrequency = p.alcoholFrequency.rawValue
        self.healthGoals = p.healthGoals.map(\.rawValue)
        self.unitPreference = p.unitPreference.rawValue
        self.onboardingComplete = p.onboardingComplete
        self.connectedApps = p.connectedApps
        self.createdAt = p.createdAt
        self.dietType = p.dietType.rawValue
        self.mealsPerDay = p.mealsPerDay
        self.fastFoodPerWeek = p.fastFoodPerWeek
        self.waterGlassesPerDay = p.waterGlassesPerDay
        self.caffeineCupsPerDay = p.caffeineCupsPerDay
        self.addedSugarServingsPerDay = p.addedSugarServingsPerDay
        self.smokingPackYears = p.smokingPackYears
        self.yearsSmoking = p.yearsSmoking
        self.yearsSinceQuitSmoking = p.yearsSinceQuitSmoking
        self.alcoholDrinksPerWeek = p.alcoholDrinksPerWeek
        self.stressLevel = p.stressLevel
        self.sleepQuality = p.sleepQuality.rawValue
        self.screenTimeHoursPerDay = p.screenTimeHoursPerDay
        self.exerciseTypes = p.exerciseTypes
        self.biographyNote = p.biographyNote
        self.cigarettesPerDay = p.cigarettesPerDay
        self.vapes = p.vapes
        self.secondhandSmokeExposure = p.secondhandSmokeExposure.rawValue
        self.cannabisUseFrequency = p.cannabisUseFrequency.rawValue
        self.alcoholBingeFrequency = p.alcoholBingeFrequency.rawValue
        self.alcoholFreeDaysPerWeek = p.alcoholFreeDaysPerWeek
        self.alcoholBeverageTypes = p.alcoholBeverageTypes
        self.vegetableServingsPerDay = p.vegetableServingsPerDay
        self.fruitServingsPerDay = p.fruitServingsPerDay
        self.homeCookedMealsPerWeek = p.homeCookedMealsPerWeek
        self.lateNightEatingTimesPerWeek = p.lateNightEatingTimesPerWeek
        self.processedFoodFrequency = p.processedFoodFrequency.rawValue
        self.emotionalEatingFrequency = p.emotionalEatingFrequency.rawValue
        self.eatingWindowHours = p.eatingWindowHours
        self.proteinSources = p.proteinSources
    }

    /// Build a detached UserProfile from this DTO. Caller is responsible for
    /// inserting into SwiftData (or merging into an existing row).
    func toUserProfile() -> UserProfile {
        UserProfile(
            name: name,
            dateOfBirth: dateOfBirth,
            biologicalSex: BiologicalSex(rawValue: biologicalSex) ?? .notSpecified,
            ethnicity: Ethnicity(rawValue: ethnicity) ?? .preferNotToSay,
            heightCm: heightCm,
            weightKg: weightKg,
            activityLevel: ActivityLevel(rawValue: activityLevel) ?? .moderatelyActive,
            activityMinutesPerSession: activityMinutesPerSession,
            sleepBedtime: sleepBedtime,
            sleepWakeTime: sleepWakeTime,
            sleepHoursPerNight: sleepHoursPerNight,
            healthConditions: healthConditions,
            medications: medications,
            familyHistory: familyHistory,
            smokingStatus: SmokingStatus(rawValue: smokingStatus) ?? .never,
            alcoholFrequency: AlcoholFrequency(rawValue: alcoholFrequency) ?? .never,
            healthGoals: healthGoals.compactMap { HealthGoal(rawValue: $0) },
            unitPreference: UnitSystem(rawValue: unitPreference) ?? .imperial,
            onboardingComplete: onboardingComplete,
            connectedApps: connectedApps,
            createdAt: createdAt,
            dietType: dietType.flatMap(DietType.init(rawValue:)) ?? .omnivore,
            mealsPerDay: mealsPerDay ?? 3,
            fastFoodPerWeek: fastFoodPerWeek ?? 2,
            waterGlassesPerDay: waterGlassesPerDay ?? 6,
            caffeineCupsPerDay: caffeineCupsPerDay ?? 2,
            addedSugarServingsPerDay: addedSugarServingsPerDay ?? 2,
            smokingPackYears: smokingPackYears ?? 0,
            yearsSmoking: yearsSmoking ?? 0,
            yearsSinceQuitSmoking: yearsSinceQuitSmoking ?? 0,
            alcoholDrinksPerWeek: alcoholDrinksPerWeek ?? 0,
            stressLevel: stressLevel ?? 5,
            sleepQuality: sleepQuality.flatMap(SleepQuality.init(rawValue:)) ?? .okay,
            screenTimeHoursPerDay: screenTimeHoursPerDay ?? 4,
            exerciseTypes: exerciseTypes ?? [],
            biographyNote: biographyNote ?? "",
            cigarettesPerDay: cigarettesPerDay ?? 0,
            vapes: vapes ?? false,
            secondhandSmokeExposure: secondhandSmokeExposure.flatMap(SecondhandSmokeLevel.init(rawValue:)) ?? .none,
            cannabisUseFrequency: cannabisUseFrequency.flatMap(CannabisFrequency.init(rawValue:)) ?? .never,
            alcoholBingeFrequency: alcoholBingeFrequency.flatMap(BingeFrequency.init(rawValue:)) ?? .never,
            alcoholFreeDaysPerWeek: alcoholFreeDaysPerWeek ?? 7,
            alcoholBeverageTypes: alcoholBeverageTypes ?? [],
            vegetableServingsPerDay: vegetableServingsPerDay ?? 2,
            fruitServingsPerDay: fruitServingsPerDay ?? 1,
            homeCookedMealsPerWeek: homeCookedMealsPerWeek ?? 10,
            lateNightEatingTimesPerWeek: lateNightEatingTimesPerWeek ?? 2,
            processedFoodFrequency: processedFoodFrequency.flatMap(ProcessedFoodFrequency.init(rawValue:)) ?? .sometimes,
            emotionalEatingFrequency: emotionalEatingFrequency.flatMap(EmotionalEatingFrequency.init(rawValue:)) ?? .sometimes,
            eatingWindowHours: eatingWindowHours ?? 14,
            proteinSources: proteinSources ?? []
        )
    }
}
