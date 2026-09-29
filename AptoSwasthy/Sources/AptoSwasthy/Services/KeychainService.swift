import Foundation
import Security

final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()
    private init() {}

    private enum Key: String {
        case accessToken  = "com.aptoswasthy.accessToken"
        case idToken      = "com.aptoswasthy.idToken"
        case refreshToken = "com.aptoswasthy.refreshToken"
        case appleEmail   = "com.aptoswasthy.appleEmail"
        case applePassword = "com.aptoswasthy.applePassword"
        /// Per-install 32-byte secret used as the HMAC key when deriving a
        /// deterministic Apple password. Synced via iCloud Keychain so a
        /// reinstall on a different device can still recover the password.
        /// Key material itself never leaves Keychain.
        case appleDerivationSecret = "com.aptoswasthy.appleDerivationSecret"
    }

    // MARK: - Tokens

    struct AuthTokens {
        let accessToken: String
        let idToken: String
        let refreshToken: String
    }

    func saveTokens(_ tokens: AuthTokens) {
        set(tokens.accessToken,  for: .accessToken)
        set(tokens.idToken,      for: .idToken)
        set(tokens.refreshToken, for: .refreshToken)
    }

    func loadTokens() -> AuthTokens? {
        guard
            let access  = get(.accessToken),
            let id      = get(.idToken),
            let refresh = get(.refreshToken)
        else { return nil }
        return AuthTokens(accessToken: access, idToken: id, refreshToken: refresh)
    }

    func clearTokens() {
        delete(.accessToken)
        delete(.idToken)
        delete(.refreshToken)
    }

    // MARK: - Apple Sign In helpers

    func saveAppleCredentials(email: String, password: String) {
        set(email,    for: .appleEmail)
        set(password, for: .applePassword)
    }

    func loadAppleCredentials() -> (email: String, password: String)? {
        guard let email = get(.appleEmail), let password = get(.applePassword) else { return nil }
        return (email, password)
    }

    func clearAppleCredentials() {
        delete(.appleEmail)
        delete(.applePassword)
    }

    // MARK: - Apple derivation secret

    /// Load the device-scoped HMAC key used to derive Apple-sign-in passwords,
    /// generating and persisting a fresh 32-byte secret on first access. The
    /// entry is stored with iCloud Keychain sync so the same derivation works
    /// across the user's devices as long as they have iCloud Keychain enabled.
    func loadOrCreateAppleDerivationSecret() -> Data {
        if let existing = getData(.appleDerivationSecret), existing.count == 32 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        setData(data, for: .appleDerivationSecret, synchronizable: true)
        return data
    }

    // MARK: - Clear all

    func clearAll() {
        clearTokens()
        clearAppleCredentials()
    }

    // MARK: - Fresh-install wipe

    /// iOS keeps Keychain items alive across app deletion, which means a user
    /// who reinstalls the app would skip the login screen. UserDefaults is
    /// wiped on uninstall, so a missing flag here is a reliable signal for
    /// "first launch since install" - use it to clear saved tokens.
    func clearTokensIfFreshInstall() {
        let defaults = UserDefaults.standard
        let flagKey = "com.aptoswasthy.keychain.hasLaunchedBefore"
        if !defaults.bool(forKey: flagKey) {
            clearAll()
            defaults.set(true, forKey: flagKey)
        }
    }

    // MARK: - Private primitives

    private func set(_ value: String, for key: Key) {
        guard let data = value.data(using: .utf8) else { return }
        setData(data, for: key, synchronizable: false)
    }

    private func get(_ key: Key) -> String? {
        guard let data = getData(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func setData(_ data: Data, for key: Key, synchronizable: Bool) {
        delete(key)
        var query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
            kSecValueData:   data,
            kSecAttrAccessible: synchronizable
                ? kSecAttrAccessibleAfterFirstUnlock
                : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if synchronizable {
            query[kSecAttrSynchronizable] = kCFBooleanTrue
        }
        SecItemAdd(query as CFDictionary, nil)
    }

    private func getData(_ key: Key) -> Data? {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        key.rawValue,
            kSecReturnData:         true,
            kSecMatchLimit:         kSecMatchLimitOne,
            // Match regardless of whether the item was stored synchronized
            // or not - this lets a single helper serve both kinds.
            kSecAttrSynchronizable: kSecAttrSynchronizableAny
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    private func delete(_ key: Key) {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        key.rawValue,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }
}
