import Foundation
import Security
import LocalAuthentication
import StickeyCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Optional, device-only password storage. A change to enrolled biometrics
/// invalidates the item; the note's original PIN or password remains the recovery path.
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
        context.localizedFallbackTitle = "Use PIN or password"
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
            case .unavailable: return "Biometric unlock isn’t available on this device. Use your PIN or password."
            case .invalid: return "The stored unlock credential could not be read. Use your PIN or password."
            case .status(let status):
                switch status {
                case errSecUserCanceled: return "Authentication was cancelled."
                case errSecItemNotFound: return "Biometric unlock needs to be enabled again with your PIN or password."
                case errSecAuthFailed: return "Your identity could not be verified. Use your PIN or password."
                default: return SecCopyErrorMessageString(status, nil) as String? ?? "The unlock credential could not be accessed."
                }
            }
        }
    }
}

/// New native note locks use an opaque, random encryption credential. Apple
/// authenticates the device owner; the app never receives their login password.
@MainActor
enum AppleNoteSecurity {
    private final class Request {
        let id = UUID()
        let noteID: UUID
        let context: LAContext
        var isPresentingSystemPrompt = true
        weak var store: NoteStore?
        init(noteID: UUID, context: LAContext, store: NoteStore) {
            self.noteID = noteID; self.context = context; self.store = store
        }
    }
    private static var request: Request?
    static var isAuthenticating: Bool { request != nil }
    static var isPresentingSystemPrompt: Bool { request?.isPresentingSystemPrompt == true }

    static func cancel(noteID: UUID) {
        guard let current = request, current.noteID == noteID else { return }
        request = nil
        current.context.invalidate()
        current.store?.relockNote(noteID)
    }
    static func cancelAll() {
        if let current = request { cancel(noteID: current.noteID) }
    }

    static func protect(store: NoteStore, noteID: UUID) async throws {
        guard let note = store.notes.first(where: { $0.id == noteID }) else { throw NoteSecurityError.unavailable }
        if note.usesAppleAuthentication { store.relockNote(noteID); return }
        guard !store.isLocked(noteID) else { throw NoteSecurityError.locked }
        try await withAuthentication(store: store, noteID: noteID, reason: "Lock this note with Apple authentication") { context, generation in
            let credentialID = UUID()
            let credential = try AppleNoteCredentials.generate()
            do {
                try await Task.detached(priority: .userInitiated) {
                    try AppleNoteCredentials.save(credential, id: credentialID, context: context)
                    // Verify recoverability before replacing the note's encryption.
                    guard try AppleNoteCredentials.retrieve(id: credentialID, context: context) == credential else {
                        throw AuthenticationError.unavailable
                    }
                }.value
                try validateRequest(store: store, noteID: noteID, generation: generation)
                if note.isPasswordProtected {
                    try await store.convertToAppleAuthentication(noteID, credential: credential, credentialID: credentialID, expectedGeneration: generation)
                } else {
                    try await store.lockNoteWithAppleCredential(noteID, credential: credential, credentialID: credentialID, expectedGeneration: generation)
                }
            } catch {
                // A failed disk write can leave the new encrypted envelope in memory.
                // Never strand it (or a duplicate) by deleting its only usable key.
                if !store.notes.contains(where: { $0.encryptedContent?.credentialID == credentialID }) {
                    AppleNoteCredentials.remove(id: credentialID)
                }
                throw error
            }
        }
    }

    static func unlock(store: NoteStore, noteID: UUID) async throws {
        guard let payload = store.notes.first(where: { $0.id == noteID })?.encryptedContent,
              payload.credentialKind == "apple", let credentialID = payload.credentialID else {
            throw AuthenticationError.unavailable
        }
        try await withAuthentication(store: store, noteID: noteID, reason: "Unlock this note") { context, generation in
            let credential = try await Task.detached(priority: .userInitiated) {
                try AppleNoteCredentials.retrieve(id: credentialID, context: context)
            }.value
            try validateRequest(store: store, noteID: noteID, generation: generation)
            try await store.unlockNote(noteID, password: credential, expectedGeneration: generation)
        }
    }

    static func removeProtection(store: NoteStore, noteID: UUID) async throws {
        guard let payload = store.notes.first(where: { $0.id == noteID })?.encryptedContent,
              payload.credentialKind == "apple", let credentialID = payload.credentialID else {
            throw AuthenticationError.unavailable
        }
        try await withAuthentication(store: store, noteID: noteID, reason: "Remove the lock from this note") { context, generation in
            let credential = try await Task.detached(priority: .userInitiated) {
                try AppleNoteCredentials.retrieve(id: credentialID, context: context)
            }.value
            try validateRequest(store: store, noteID: noteID, generation: generation)
            try await store.removePassword(noteID, password: credential, expectedGeneration: generation)
            // Keep the credential for protected duplicates and older encrypted backups.
        }
    }

    private static func withAuthentication(store: NoteStore, noteID: UUID, reason: String,
                                           operation: (LAContext, UInt64) async throws -> Void) async throws {
        guard request == nil else { throw AuthenticationError.inProgress }
        try Task.checkCancellation()
        try AppleNoteCredentials.verifySigning()
        store.relockExpiredNotes()
        let generation = store.securityGenerationToken(for: noteID)
        let context = LAContext()
        context.localizedReason = reason
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            if let availabilityError { throw availabilityError }
            throw AuthenticationError.unavailable
        }
        let current = Request(noteID: noteID, context: context, store: store)
        request = current
        defer {
            if request?.id == current.id { request = nil }
            context.invalidate()
            if !applicationIsActive { store.relockAll() }
        }
        do {
            try await withTaskCancellationHandler {
                // Leave fallback text and presentation to Apple: Touch ID / Face ID,
                // or the device's login password / passcode, in the real system UI.
                guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
                    throw CancellationError()
                }
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while !applicationIsActive, request?.id == current.id, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(50))
                }
                try Task.checkCancellation()
                guard request?.id == current.id, applicationIsActive,
                      store.securityGenerationToken(for: noteID) == generation else { throw CancellationError() }
                // Once Apple's UI is finished, ordinary backgrounding must cancel
                // the remaining Keychain/encryption work just like a PIN unlock.
                current.isPresentingSystemPrompt = false
                try await operation(context, generation)
            } onCancel: {
                context.invalidate()
                Task { @MainActor in
                    if request?.id == current.id { cancel(noteID: noteID) }
                }
            }
        } catch let error as LAError where [.userCancel, .systemCancel, .appCancel].contains(error.code) {
            throw CancellationError()
        }
    }

    private static func validateRequest(store: NoteStore, noteID: UUID, generation: UInt64) throws {
        try Task.checkCancellation()
        guard request?.noteID == noteID, applicationIsActive,
              store.securityGenerationToken(for: noteID) == generation else { throw CancellationError() }
    }

    private static var applicationIsActive: Bool {
        #if os(macOS)
        NSApp.isActive
        #else
        UIApplication.shared.applicationState == .active
        #endif
    }

    enum AuthenticationError: LocalizedError {
        case unavailable, missingCredential, inProgress, keychain(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Apple authentication is unavailable. Set a device password or passcode in Settings and try again."
            case .missingCredential: return "This note uses Apple authentication on the device where it was locked. Open it on that device to unlock it."
            case .inProgress: return "Finish the current Apple authentication prompt first."
            case .keychain(let status):
                if status == errSecMissingEntitlement {
                    return "This copy of Stickey Notes isn’t signed for Apple note locking. Open the signed build to use this feature."
                }
                return SecCopyErrorMessageString(status, nil) as String? ?? "The note’s protected key could not be accessed. Try Apple authentication again."
            }
        }
    }
}

private enum AppleNoteCredentials {
    private static let service = "com.stickeynote.app.apple-note-credential"

    /// Avoid asking for Touch ID when an ad-hoc build cannot access the key store.
    static func verifySigning() throws {
        #if os(macOS)
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any],
              let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              entitlements["com.apple.application-identifier"] is String else {
            throw AppleNoteSecurity.AuthenticationError.keychain(errSecMissingEntitlement)
        }
        #endif
    }

    static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NoteSecurityError.unavailable
        }
        return Data(bytes).base64EncodedString()
    }

    static func save(_ credential: String, id: UUID, context: LAContext) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                         .userPresence, &error) else {
            if let error = error?.takeRetainedValue() { throw error }
            throw NoteSecurityError.unavailable
        }
        var query = baseQuery(id)
        query[kSecValueData as String] = Data(credential.utf8)
        query[kSecAttrAccessControl as String] = access
        query[kSecAttrLabel as String] = "Stickey Notes locked note"
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecUserCanceled { throw CancellationError() }
        guard status == errSecSuccess else { throw AppleNoteSecurity.AuthenticationError.keychain(status) }
    }

    static func retrieve(id: UUID, context: LAContext) throws -> String {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw AppleNoteSecurity.AuthenticationError.missingCredential }
        if status == errSecUserCanceled { throw CancellationError() }
        guard status == errSecSuccess else { throw AppleNoteSecurity.AuthenticationError.keychain(status) }
        guard let data = result as? Data, let credential = String(data: data, encoding: .utf8) else {
            throw NoteSecurityError.unavailable
        }
        return credential
    }

    static func remove(id: UUID) { SecItemDelete(baseQuery(id) as CFDictionary) }

    private static func baseQuery(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }
}
