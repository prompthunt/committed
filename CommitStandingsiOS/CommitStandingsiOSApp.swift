import SwiftUI

/// Committed for iPhone. The app compiles the Mac app's platform-neutral core (models,
/// ranking, persistence, the stores, auth, and `StandingRow`) through shared target
/// membership; `AppModel` composes it.
@main
struct CommitStandingsiOSApp: App {
    @State private var app = AppModel.forLaunch()

    init() {
        // Leaderboard Notifications found while the app is open show as banners.
        if NSClassFromString("XCTestCase") == nil { ForegroundNotificationPresenter.install() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.store)
                .environment(app.refresh)
                .environment(app.auth)
                .environment(app.roster)
                .environment(app.notifications)
        }
    }
}

extension AppModel {
    /// Production wiring, except under the unit-test host (which must never touch the real
    /// Keychain or network) and the DEBUG `-demoBoard` launch argument used for screenshots.
    static func forLaunch() -> AppModel {
        if NSClassFromString("XCTestCase") != nil {
            return AppModel(.testHost())
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoBoard") {
            let app = AppModel(.demo())
            // `-demoTab people|settings` opens on that tab, for screenshots.
            switch UserDefaults.standard.string(forKey: "demoTab") {
            case "people": app.selectedTab = .people
            case "settings": app.selectedTab = .settings
            default: break
            }
            return app
        }
        #endif
        return AppModel(.live())
    }
}

extension AppDependencies {
    /// Signed out, in memory, offline: the test host app does nothing on its own.
    static func testHost() -> AppDependencies {
        AppDependencies(
            credentials: InMemoryGitHubCredentialStore(),
            gitHubSession: .shared,
            contributions: ContributionsClient(),
            competitorPersistence: InMemoryCompetitorPersistence(),
            snapshotPersistence: InMemoryStandingsSnapshotPersistence(),
            hiddenPeoplePersistence: InMemoryHiddenPeoplePersistence(),
            rosterPersistence: nil
        )
    }
}
