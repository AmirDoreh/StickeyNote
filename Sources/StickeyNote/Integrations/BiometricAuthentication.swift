import Foundation
import LocalAuthentication

@MainActor
enum BiometricAuthentication {
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static var label: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Use Face ID"
        case .touchID: return "Use Touch ID"
        case .opticID: return "Use Optic ID"
        default: return "Use biometrics"
        }
    }

    /// Authenticate before retrieving a locally stored note key from Keychain.
    static func authenticate(reason: String = "Unlock your protected note") async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use note password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch let failure as LAError {
            switch failure.code {
            case .userCancel, .systemCancel, .appCancel, .userFallback,
                 .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                return false
            default: throw failure
            }
        }
    }
}
