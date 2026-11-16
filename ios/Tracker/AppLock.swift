import LocalAuthentication
import SwiftUI

/// The Face ID lock, per phone (switched in the page's "iPhone app" card).
/// On, the app opens locked and locks again after a couple of minutes away;
/// while it is in the app switcher a cover hides the page.
@Observable
final class AppLock {
    private static let key = "trLockOn"
    /// How long the app can be away before it asks again.
    private static let grace: TimeInterval = 120

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.key) }
    }
    var locked: Bool
    /// The app switcher's picture: the cover, not the page.
    var covered = false

    @ObservationIgnored private var leftAt: Date?
    @ObservationIgnored private var asking = false

    init() {
        let on = UserDefaults.standard.bool(forKey: Self.key)
        enabled = on
        locked = on
    }

    /// faceID, touchID, opticID, passcode (no biometrics), or none (no
    /// passcode either, so there is nothing to lock with).
    var kind: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return "none" }
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceID"
        case .touchID: return "touchID"
        case .opticID: return "opticID"
        default: return "passcode"
        }
    }

    /// Face ID, falling back to the passcode.
    func authenticate(reason: String) async -> Bool {
        asking = true
        defer { asking = false }
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    func unlock(reason: String) {
        guard locked, !asking else { return }
        Task {
            if await authenticate(reason: reason) {
                withAnimation(.easeOut(duration: 0.2)) { locked = false }
            }
        }
    }

    func phaseChanged(_ phase: ScenePhase, reason: String) {
        guard enabled else {
            covered = false
            locked = false
            return
        }
        switch phase {
        case .background:
            if leftAt == nil { leftAt = Date() }
            covered = true
        case .inactive:
            // Face ID's own sheet makes the app inactive too.
            if !asking { covered = true }
        case .active:
            if let leftAt, Date().timeIntervalSince(leftAt) > Self.grace { locked = true }
            leftAt = nil
            covered = false
            if locked { unlock(reason: reason) }
        @unknown default:
            break
        }
    }
}
