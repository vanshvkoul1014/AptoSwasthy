import Foundation

// MARK: - Config (no secrets, Pool ID and Client ID are public identifiers)

enum AWSConfig {
    static let region     = "us-east-1"
    static let userPoolId = "us-east-1_mctlUA1LV"
    static let clientId   = "69hg6pj3eb7ts829l21ogj7kjd"
    static let domain     = "aptoswasthy-auth"

    /// API Gateway base URL for the profile service (output of `sam deploy`
    /// from `infra/`). Leave nil until the stack is deployed - the client
    /// will silently skip cloud sync and keep working purely on-device.
    static let apiBaseURL: String? = "https://keny0pxtig.execute-api.us-east-1.amazonaws.com"

    static var endpoint: URL {
        URL(string: "https://cognito-idp.\(region).amazonaws.com/")!
    }

    static var oauthTokenURL: URL {
        URL(string: "https://\(domain).auth.\(region).amazoncognito.com/oauth2/token")!
    }

    static var hostedUIBase: String {
        "https://\(domain).auth.\(region).amazoncognito.com"
    }
}

// MARK: - Errors

enum CognitoError: LocalizedError {
    case network(Error)
    case invalidResponse
    case userNotFound
    case wrongPassword
    case userNotConfirmed
    case userAlreadyExists
    case invalidPassword(String)
    case codeMismatch
    case codeExpired
    case tooManyAttempts
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network:           return "Network error. Check your connection."
        case .invalidResponse:   return "Unexpected server response."
        case .userNotFound:      return "No account found with that email."
        case .wrongPassword:     return "Incorrect password."
        case .userNotConfirmed:  return "Please verify your email before signing in."
        case .userAlreadyExists: return "An account with this email already exists."
        case .invalidPassword(let msg): return msg
        case .codeMismatch:      return "Incorrect verification code."
        case .codeExpired:       return "Verification code expired. Request a new one."
        case .tooManyAttempts:   return "Too many attempts. Please wait and try again."
        case .unknown(let msg):  return msg
        }
    }
}

// MARK: - Service

final class CognitoAuthService: @unchecked Sendable {
    static let shared = CognitoAuthService()
    private init() {}

    private let session = URLSession.shared

    // MARK: - Sign Up

    func signUp(email: String, password: String, name: String) async throws {
        let body: [String: Any] = [
            "ClientId": AWSConfig.clientId,
            "Username": email.lowercased(),
            "Password": password,
            "UserAttributes": [
                ["Name": "email", "Value": email.lowercased()],
                ["Name": "name",  "Value": name]
            ]
        ]
        try await call(target: "SignUp", body: body)
    }

    // MARK: - Confirm Sign Up

    func confirmSignUp(email: String, code: String) async throws {
        let body: [String: Any] = [
            "ClientId":         AWSConfig.clientId,
            "Username":         email.lowercased(),
            "ConfirmationCode": code
        ]
        try await call(target: "ConfirmSignUp", body: body)
    }

    // MARK: - Resend Confirmation Code

    func resendConfirmationCode(email: String) async throws {
        let body: [String: Any] = [
            "ClientId": AWSConfig.clientId,
            "Username": email.lowercased()
        ]
        try await call(target: "ResendConfirmationCode", body: body)
    }

    // MARK: - Sign In (returns tokens)

    func signIn(email: String, password: String) async throws -> KeychainService.AuthTokens {
        let body: [String: Any] = [
            "AuthFlow":       "USER_PASSWORD_AUTH",
            "ClientId":       AWSConfig.clientId,
            "AuthParameters": [
                "USERNAME": email.lowercased(),
                "PASSWORD": password
            ]
        ]
        let json = try await call(target: "InitiateAuth", body: body)

        guard
            let result = json["AuthenticationResult"] as? [String: Any],
            let access  = result["AccessToken"] as? String,
            let id      = result["IdToken"] as? String,
            let refresh = result["RefreshToken"] as? String
        else {
            // Could be a challenge (NEW_PASSWORD_REQUIRED etc.)
            throw CognitoError.invalidResponse
        }
        return KeychainService.AuthTokens(accessToken: access, idToken: id, refreshToken: refresh)
    }

    // MARK: - Refresh Tokens

    func refreshTokens(refreshToken: String) async throws -> KeychainService.AuthTokens {
        let body: [String: Any] = [
            "AuthFlow":       "REFRESH_TOKEN_AUTH",
            "ClientId":       AWSConfig.clientId,
            "AuthParameters": ["REFRESH_TOKEN": refreshToken]
        ]
        let json = try await call(target: "InitiateAuth", body: body)

        guard
            let result = json["AuthenticationResult"] as? [String: Any],
            let access  = result["AccessToken"] as? String,
            let id      = result["IdToken"] as? String
        else { throw CognitoError.invalidResponse }

        // Cognito doesn't return a new refresh token on refresh, reuse existing
        return KeychainService.AuthTokens(accessToken: access, idToken: id, refreshToken: refreshToken)
    }

    // MARK: - Forgot Password

    func forgotPassword(email: String) async throws {
        let body: [String: Any] = [
            "ClientId": AWSConfig.clientId,
            "Username": email.lowercased()
        ]
        try await call(target: "ForgotPassword", body: body)
    }

    func confirmForgotPassword(email: String, code: String, newPassword: String) async throws {
        let body: [String: Any] = [
            "ClientId":         AWSConfig.clientId,
            "Username":         email.lowercased(),
            "ConfirmationCode": code,
            "Password":         newPassword
        ]
        try await call(target: "ConfirmForgotPassword", body: body)
    }

    // MARK: - Sign Out

    func signOut(accessToken: String) async throws {
        let body: [String: Any] = ["AccessToken": accessToken]
        try await call(target: "GlobalSignOut", body: body)
    }

    // MARK: - Change Password

    /// Rotate a user's password using their current access token. Used to
    /// migrate legacy Apple sign-in users off the deterministic HMAC password
    /// onto a per-device random one. See AuthViewModel for the migration flow.
    func changePassword(accessToken: String, current: String, new: String) async throws {
        let body: [String: Any] = [
            "AccessToken":      accessToken,
            "PreviousPassword": current,
            "ProposedPassword": new
        ]
        try await call(target: "ChangePassword", body: body)
    }

    // MARK: - OAuth authorization code exchange (Apple IdP + Google)

    func exchangeOAuthCode(_ code: String, codeVerifier: String? = nil) async throws -> KeychainService.AuthTokens {
        var request = URLRequest(url: AWSConfig.oauthTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params = [
            "grant_type":   "authorization_code",
            "client_id":    AWSConfig.clientId,
            "code":         code,
            "redirect_uri": "aptoswasthy://callback"
        ]
        // PKCE verifier ties this exchange to the /authorize call that produced
        // the code, so an attacker intercepting the redirect can't trade the
        // code for tokens without also having observed the pre-request state.
        if let codeVerifier { params["code_verifier"] = codeVerifier }

        let formSafe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: formSafe) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        // A non-2xx response carries a JSON error envelope that doesn't match
        // our token shape. Surface it explicitly instead of silently reporting
        // "invalid response" as if the token decoder just got confused.
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CognitoError.invalidResponse
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access  = json["access_token"]  as? String,
              let id      = json["id_token"]      as? String,
              let refresh = json["refresh_token"] as? String
        else { throw CognitoError.invalidResponse }

        return KeychainService.AuthTokens(accessToken: access, idToken: id, refreshToken: refresh)
    }

    // MARK: - Private HTTP helper

    @discardableResult
    private func call(target: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: AWSConfig.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.\(target)", forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
            return json
        }

        // Parse Cognito error
        let code = json["__type"] as? String ?? ""
        let message = json["message"] as? String ?? "Unknown error"

        switch code {
        case "UserNotFoundException":            throw CognitoError.userNotFound
        case "NotAuthorizedException":           throw CognitoError.wrongPassword
        case "UserNotConfirmedException":        throw CognitoError.userNotConfirmed
        case "UsernameExistsException":          throw CognitoError.userAlreadyExists
        case "InvalidPasswordException":         throw CognitoError.invalidPassword(message)
        case "CodeMismatchException":            throw CognitoError.codeMismatch
        case "ExpiredCodeException":             throw CognitoError.codeExpired
        case "LimitExceededException",
             "TooManyRequestsException":         throw CognitoError.tooManyAttempts
        default:                                 throw CognitoError.unknown(message)
        }
    }
}
