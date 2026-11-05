import SwiftUI
import UIKit

@main
struct CommittedApp: App {
    // The same shared graph as the Mac app: saved standings and people show immediately on
    // launch, and the token lives in this iPhone's Keychain.
    @State private var model = CommittedApp.makeModel()

    init() {
        // A unit-test host must not touch the notification center at launch.
        if !CommittedServices.isRunningTests { ForegroundNotificationPresenter.install() }
    }

    private static func makeModel() -> AppModel {
        let model = AppModel(services: makeServices(), backgroundTime: UIApplicationBackgroundTime())
        #if DEBUG
        if let tab = ScreenshotFixture.requestedTab { model.selectedTab = tab }
        #endif
        return model
    }

    private static var loadsGitHubAvatars: Bool {
        #if DEBUG
        if ScreenshotFixture.isRequested { return false }
        #endif
        return true
    }

    private static func makeServices() -> CommittedServices {
        #if DEBUG
        if ScreenshotFixture.isRequested { return ScreenshotFixture.services() }
        #endif
        return CommittedServices.live()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.store)
                .environment(model.refresh)
                .environment(model.auth)
                .environment(model.roster)
                .environment(model.services.notifications)
                .environment(\.loadsGitHubAvatars, CommittedApp.loadsGitHubAvatars)
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
