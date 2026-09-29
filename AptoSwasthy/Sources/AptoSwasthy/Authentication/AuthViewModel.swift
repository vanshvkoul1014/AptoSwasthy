import Foundation
import LocalAuthentication
import AuthenticationServices
import Observation
import CryptoKit
import Security

@MainActor
@Observable
final class AuthViewModel: NSObject, ObservableObject {
    var isAuthenticated = false
    var isLoading = false
    var errorMessage: String? = nil
    var pendingVerificationEmail: String? = nil
    var verificationSucceeded = false
    var resendCooldownUntil: Date? = nil

    private let cognito    = CognitoAuthService.shared
    private let keychain   = KeychainService.shared
    private let persistence = PersistenceService.shared

    // MARK: - OAuth flow state (PKCE + CSRF)

    /// Code verifier for the currently in-flight OAuth request. Persisted in
    /// UserDefaults so it survives the app moving to the background during the
    /// browser round-trip (iOS may terminate us mid-auth on a low-memory day).
    /// It's not secret on its own - it's only the pairing with the server-held
    /// code that provides security.
    private let pkceVerifierKey = "com.aptoswasthy.oauth.codeVerifier"
    private let oauthStateKey   = "com.aptoswasthy.oauth.state"

    // MARK: - Auto-login on launch

    func attemptAutoLogin() async {
        if let tokens = keychain.loadTokens() {
            do {
                let refreshed = try await cognito.refreshTokens(refreshToken: tokens.refreshToken)
                keychain.saveTokens(refreshed)
                isAuthenticated = true
                await syncCloudProfile()
                return
            } catch {
                // Stale / revoked tokens - clear them, then fall through to
                // biometric fallback so the user isn't forced to the login screen.
                keychain.clearTokens()
            }
        }

        // Biometric fast-login: available for users who completed onboarding
        // locally (offline/guest) OR whose cloud session expired. Uses Face ID
        // or Touch ID to re-establish the session without a password.
        await tryBiometricLogin()
    }

    private func tryBiometricLogin() async {
        let profile = persistence.fetchProfile()
        guard let profile, profile.onboardingComplete, profile.faceIDEnabled else { return }

        let context = LAContext()
        var biometricError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                        error: &biometricError) else {
            // Device has no biometrics or they're locked out - silent fail is
            // correct here; user will see the normal login screen.
            return
        }

        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Sign back in to AptoSwasthy"
            )
            if ok { isAuthenticated = true }
        } catch let laError as LAError {
            // User-cancel / fallback are expected; anything else worth logging.
            if laError.code != .userCancel && laError.code != .userFallback {
                #if DEBUG
                print("[FaceID] Biometric error: \(laError.localizedDescription)")
                #endif
            }
        } catch {}
    }

    // MARK: - Email + Password Sign In

    func login(email: String, password: String) {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }
            do {
                let tokens = try await cognito.signIn(email: email, password: password)
                keychain.saveTokens(tokens)
                isAuthenticated = true
                await syncCloudProfile()
            } catch {
                // Use a generic message to prevent account enumeration
                errorMessage = "Incorrect email or password."
            }
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, name: String) {
        guard !email.isEmpty, !password.isEmpty, !name.isEmpty else {
            errorMessage = "Please fill in all fields."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }
            do {
                try await cognito.signUp(email: email, password: password, name: name)
                pendingVerificationEmail = email
            } catch CognitoError.userAlreadyExists {
                errorMessage = "This email already has an account. Sign in instead."
            } catch {
                errorMessage = (error as? CognitoError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Verify Email

    func verifyEmail(code: String, email: String) {
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            errorMessage = "Enter the 6-digit code from your email."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }
            do {
                try await cognito.confirmSignUp(email: email, code: code)
                verificationSucceeded = true
            } catch {
                errorMessage = (error as? CognitoError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func dismissVerification() {
        pendingVerificationEmail = nil
        verificationSucceeded = false
    }

    func resendCode(email: String) {
        if let until = resendCooldownUntil, until > Date() { return }
        resendCooldownUntil = Date().addingTimeInterval(30)
        Task { try? await cognito.resendConfirmationCode(email: email) }
    }

    // MARK: - Sign In with Apple

    func handleAppleCredential(_ credential: ASAuthorizationAppleIDCredential) {
        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }

            // Primary path: Cognito Apple IdP federation. Only consume the
            // authorization code if federation succeeds - a thrown error must
            // fall through to the fallback, not abort the sign-in.
            if let codeData = credential.authorizationCode,
               let code = String(data: codeData, encoding: .utf8) {
                do {
                    let tokens = try await cognito.exchangeOAuthCode(code)
                    keychain.saveTokens(tokens)
                    isAuthenticated = true
                    await syncCloudProfile()
                    return
                } catch {
                    // Federation not configured or transient failure - drop to
                    // the Cognito-native fallback below.
                }
            }

            // Fallback: Cognito account keyed by Apple sub (no federation required).
            do {
                // Prefer a keychain-cached credential pair (same device or an
                // iCloud-Keychain-synced peer). Fall back to re-deriving from
                // the Apple sub using an iCloud-synced per-user secret, so a
                // fresh device without a cached credential still converges on
                // the same password.
                let cached = keychain.loadAppleCredentials()
                guard let emailRaw = credential.email ?? cached?.email else {
                    errorMessage = "Could not retrieve your Apple email. Please sign in with email instead."
                    return
                }
                let email = emailRaw.lowercased()

                if credential.email != nil {
                    // First time this Apple account has signed in on this install.
                    // Apple only gives us the email once, so this is also our one
                    // chance to register a cryptographically random password -
                    // no need for the deterministic-derivation escape hatch here.
                    let password = Self.randomPassword()
                    keychain.saveAppleCredentials(email: email, password: password)

                    do {
                        let tokens = try await cognito.signIn(email: email, password: password)
                        keychain.saveTokens(tokens)
                        isAuthenticated = true
                        await syncCloudProfile()
                    } catch CognitoError.userNotFound, CognitoError.wrongPassword {
                        let parts = [credential.fullName?.givenName, credential.fullName?.familyName]
                        let name = parts.compactMap { $0 }.joined(separator: " ")
                        try await cognito.signUp(email: email, password: password,
                                                 name: name.isEmpty ? "Apple User" : name)
                        pendingVerificationEmail = email
                    } catch CognitoError.userNotConfirmed {
                        pendingVerificationEmail = email
                    }
                    return
                }

                // Subsequent sign-in. Try the keychain-cached password first, and
                // only fall back to the derived password if the cache is missing
                // or wrong - rotating onto a random password on the way through
                // for any legacy account still on the old clientId-keyed hash.
                let derivedLegacy  = deriveLegacyApplePassword(sub: credential.user)
                let derivedCurrent = deriveApplePassword(sub: credential.user)
                let cachedPassword = cached?.password

                func tryAuth(_ password: String) async throws -> KeychainService.AuthTokens {
                    try await cognito.signIn(email: email, password: password)
                }

                do {
                    let tokens: KeychainService.AuthTokens
                    let usedPassword: String

                    if let cachedPassword, let t = try? await tryAuth(cachedPassword) {
                        tokens = t
                        usedPassword = cachedPassword
                    } else if let t = try? await tryAuth(derivedCurrent) {
                        tokens = t
                        usedPassword = derivedCurrent
                    } else {
                        // Last-resort: legacy clientId-keyed password. Authentic
                        // legacy users land here; if this also fails, the final
                        // throw below surfaces the real error.
                        tokens = try await tryAuth(derivedLegacy)
                        usedPassword = derivedLegacy
                    }

                    keychain.saveTokens(tokens)

                    // Rotate any non-random password onto a fresh random one so the
                    // account stops being derivable from the Apple sub.
                    if usedPassword != cachedPassword {
                        let fresh = Self.randomPassword()
                        do {
                            try await cognito.changePassword(accessToken: tokens.accessToken,
                                                             current: usedPassword,
                                                             new: fresh)
                            keychain.saveAppleCredentials(email: email, password: fresh)
                        } catch {
                            // If rotation fails we still have a valid session -
                            // cache the password we authenticated with so the
                            // next launch doesn't re-derive from scratch.
                            keychain.saveAppleCredentials(email: email, password: usedPassword)
                        }
                    }

                    isAuthenticated = true
                    await syncCloudProfile()
                } catch CognitoError.userNotFound {
                    let parts = [credential.fullName?.givenName, credential.fullName?.familyName]
                    let name = parts.compactMap { $0 }.joined(separator: " ")
                    let password = Self.randomPassword()
                    try await cognito.signUp(email: email, password: password,
                                             name: name.isEmpty ? "Apple User" : name)
                    keychain.saveAppleCredentials(email: email, password: password)
                    pendingVerificationEmail = email
                } catch CognitoError.userNotConfirmed {
                    pendingVerificationEmail = email
                }
            } catch {
                errorMessage = (error as? CognitoError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func handleAppleError(_ error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled { return }
        errorMessage = "Apple Sign In failed. Please try again."
    }

    // MARK: - Sign In with Google (Cognito Hosted UI)

    func googleSignInURL() -> URL? {
        let verifier  = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state     = Self.randomURLSafeString(length: 32)

        let defaults = UserDefaults.standard
        defaults.set(verifier, forKey: pkceVerifierKey)
        defaults.set(state,    forKey: oauthStateKey)

        guard var components = URLComponents(string: "\(AWSConfig.hostedUIBase)/authorize") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "client_id",             value: AWSConfig.clientId),
            URLQueryItem(name: "redirect_uri",          value: "aptoswasthy://callback"),
            URLQueryItem(name: "identity_provider",     value: "Google"),
            URLQueryItem(name: "scope",                 value: "openid email profile"),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state",                 value: state)
        ]
        return components.url
    }

    func handleGoogleCallback(url: URL) {
        let defaults = UserDefaults.standard
        let expectedState = defaults.string(forKey: oauthStateKey)
        let verifier      = defaults.string(forKey: pkceVerifierKey)
        defer {
            defaults.removeObject(forKey: oauthStateKey)
            defaults.removeObject(forKey: pkceVerifierKey)
        }

        // Validate callback URL to prevent open-redirect attacks
        guard url.scheme?.lowercased() == "aptoswasthy",
              url.host?.lowercased() == "callback" else {
            errorMessage = "Authentication callback was invalid."
            return
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        // CSRF protection: reject if the returned state doesn't match what we
        // generated at /authorize time.
        let returnedState = items.first(where: { $0.name == "state" })?.value
        guard let expectedState, let returnedState, expectedState == returnedState else {
            errorMessage = "Authentication callback was invalid."
            return
        }

        // Surface OAuth provider errors
        if let oauthError = items.first(where: { $0.name == "error" })?.value {
            errorMessage = oauthError == "access_denied" ? "Sign in was cancelled." : "Sign in failed. Please try again."
            return
        }

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            errorMessage = "Google Sign In failed. Please try again."
            return
        }

        guard let verifier else {
            errorMessage = "Authentication callback was invalid."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }
            do {
                let tokens = try await cognito.exchangeOAuthCode(code, codeVerifier: verifier)
                keychain.saveTokens(tokens)
                isAuthenticated = true
                await syncCloudProfile()
            } catch {
                errorMessage = (error as? CognitoError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Cloud profile sync

    /// Pull the cloud-persisted profile (if the stack is deployed) and merge
    /// it into SwiftData. Called after any successful authentication so that
    /// a user who reinstalls or signs in on a new device gets their answers
    /// back without redoing onboarding.
    private func syncCloudProfile() async {
        do {
            guard let dto = try await ProfileAPIService.shared.fetchProfile() else { return }
            persistence.upsertProfile(from: dto)
        } catch ProfileAPIError.cloudDisabled {
            // Stack not yet deployed - fall back to local-only.
        } catch {
            #if DEBUG
            print("[AuthViewModel] cloud profile fetch failed: \(error)")
            #endif
        }
    }

    // MARK: - Forgot Password

    func forgotPassword(email: String) {
        guard !email.isEmpty else { errorMessage = "Enter your email address."; return }
        Task {
            // Always show success to prevent email enumeration
            _ = try? await cognito.forgotPassword(email: email)
        }
    }

    func confirmForgotPassword(email: String, code: String, newPassword: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await cognito.confirmForgotPassword(email: email, code: code, newPassword: newPassword)
            return true
        } catch CognitoError.codeMismatch {
            errorMessage = "Incorrect code. Check your email and try again."
        } catch CognitoError.codeExpired {
            errorMessage = "Code expired. Request a new one."
        } catch CognitoError.invalidPassword(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Reset failed. Please try again."
        }
        return false
    }

    // MARK: - Sign Out

    func logout() {
        Task {
            if let tokens = keychain.loadTokens() {
                try? await cognito.signOut(accessToken: tokens.accessToken)
            }
            keychain.clearAll()
            persistence.deleteAllUserData()
            isAuthenticated = false
        }
    }

    // MARK: - Private helpers

    /// HMAC-SHA256 of the Apple sub keyed by a per-user 32-byte secret stored
    /// in iCloud Keychain. Keeps the "same Apple account → same password"
    /// property across the user's devices without the secret being derivable
    /// from public identifiers (the old keying material was the Cognito
    /// client ID, which anyone inspecting the app could read).
    private func deriveApplePassword(sub: String) -> String {
        let secret = keychain.loadOrCreateAppleDerivationSecret()
        let key = SymmetricKey(data: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(sub.utf8), using: key)
        let hex = Data(mac).map { String(format: "%02x", $0) }.joined()
        return "Ap1\(hex.prefix(29))"
    }

    /// Legacy derivation path (clientId-keyed) kept only so we can recognize
    /// an existing account during migration and rotate it onto a random
    /// password. Remove once telemetry shows no one is still signing in with
    /// a legacy-derived password.
    private func deriveLegacyApplePassword(sub: String) -> String {
        let key = SymmetricKey(data: Data(AWSConfig.clientId.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(sub.utf8), using: key)
        let hex = Data(mac).map { String(format: "%02x", $0) }.joined()
        return "Ap1\(hex.prefix(29))"
    }

    /// Cognito's default policy requires upper + lower + digit + 8+ chars.
    /// Use a URL-safe alphabet + a fixed "Ap1" prefix to satisfy it trivially.
    private static func randomPassword() -> String {
        let body = randomURLSafeString(length: 32)
        return "Ap1\(body)"
    }

    /// Cryptographically random, URL-safe (base64url without padding) string.
    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// RFC 7636 S256 code challenge: base64url(SHA256(verifier)).
    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
