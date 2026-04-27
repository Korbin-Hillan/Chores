import Foundation
import LocalAuthentication

enum BiometricAuth {
    enum BiometricError: LocalizedError {
        case unavailable
        case failed

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Biometric authentication is not available on this device."
            case .failed:
                return "Biometric authentication was cancelled or failed."
            }
        }
    }

    static func biometryType() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        return context.biometryType
    }

    static var isAvailable: Bool {
        biometryType() != .none
    }

    static var localizedBiometryName: String {
        switch biometryType() {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Biometrics"
        }
    }

    static func authenticate(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            context.localizedCancelTitle = "Cancel"

            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                continuation.resume(returning: false)
                return
            }

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
