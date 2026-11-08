import Foundation
import Security
import LocalAuthentication

/// Optional, device-only password storage. A change to enrolled biometrics
/// invalidates the item; the note's original password remains the recovery path.
enum BiometricNoteKeys {
    private static let service = "com.stickeynote.app.protected-note"

    static func save(password: String, noteID: UUID) throws {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &accessError) else {
            if let error = accessError?.takeRetainedValue() { throw error }
            throw CredentialError.unavailable
        }
        var query = baseQuery(noteID)
        query[kSecValueData as String] = Data(password.utf8)
        query[kSecAttrAccessControl as String] = access
        query[kSecAttrLabel as String] = "StickeyNote protected note"
        // Replacing an enrollment is an explicit in-app opt-in after password entry.
        let removal = SecItemDelete(baseQuery(noteID) as CFDictionary)
        guard removal == errSecSuccess || removal == errSecItemNotFound else { throw CredentialError.status(removal) }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialError.status(status) }
    }

    /// Run off the main actor: Keychain displays the biometric authentication UI.
    static func retrieve(noteID: UUID) throws -> String {
        let context = LAContext()
        context.localizedReason = "Unlock your protected StickeyNote"
        context.localizedFallbackTitle = "Use note password"
        var query = baseQuery(noteID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw CredentialError.status(status) }
        guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else { throw CredentialError.invalid }
        return password
    }

    static func hasCredential(noteID: UUID) -> Bool {
        var query = baseQuery(noteID)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func remove(noteID: UUID) {
        SecItemDelete(baseQuery(noteID) as CFDictionary)
    }

    private static func baseQuery(_ noteID: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: noteID.uuidString,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    enum CredentialError: LocalizedError {
        case unavailable, invalid, status(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Biometric unlock isn’t available on this device. Use your note password."
            case .invalid: return "The stored unlock credential could not be read. Use your note password."
            case .status(let status):
                switch status {
                case errSecUserCanceled: return "Authentication was cancelled."
                case errSecItemNotFound: return "Biometric unlock needs to be enabled again with your note password."
                case errSecAuthFailed: return "Your identity could not be verified. Use your note password."
                default: return SecCopyErrorMessageString(status, nil) as String? ?? "The unlock credential could not be accessed."
                }
            }
        }
    }
}
