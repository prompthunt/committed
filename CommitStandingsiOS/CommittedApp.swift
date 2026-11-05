import SwiftUI
import UIKit

@main
struct CommittedApp: App {
    // The same shared graph as the Mac app: saved standings and people show immediately on
    // launch, and the token lives in this iPhone's Keychain.
    @State private var model = AppModel(
        services: CommittedServices.live(),
        backgroundTime: UIApplicationBackgroundTime()
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.store)
                .environment(model.refresh)
                .environment(model.auth)
                .environment(model.roster)
                .environment(model.services.notifications)
        }
    }
}

/// Background running time from UIKit, so device-flow polling outlives the switch to Safari.
/// When iOS's allowance runs out the task ends cleanly and the app is suspended; polling resumes
/// on return.
@MainActor
final class UIApplicationBackgroundTime: BackgroundTimeProviding {
    private var active: Set<Int> = []

    func begin(_ name: String) -> Int {
        var token = UIBackgroundTaskIdentifier.invalid.rawValue
        let identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end(token) }
        }
        token = identifier.rawValue
        if identifier != .invalid { active.insert(token) }
        return token
    }

    func end(_ token: Int) {
        guard active.remove(token) != nil else { return }
        UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: token))
    }
}
