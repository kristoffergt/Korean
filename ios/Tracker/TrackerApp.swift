import SwiftUI
import UIKit

@main
struct TrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var lock: AppLock
    @State private var shell: Shell

    init() {
        let lock = AppLock()
        _lock = State(initialValue: lock)
        _shell = State(initialValue: Shell(lock: lock))
    }

    var body: some Scene {
        WindowGroup {
            RootView(shell: shell, lock: lock)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Before launching ends, so a reminder pressed while the app was
        // closed still reaches it.
        Reminders.shared.install()
        return true
    }
}
