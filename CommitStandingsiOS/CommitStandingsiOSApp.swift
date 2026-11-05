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
        // Background app refresh keeps Live rank current while the app is closed.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [app] in
            await app.backgroundRefresh()
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
            var dependencies = AppDependencies.demo()
            // `-demoRelay ask|accepted` (opt-in) registers the demo board with this build's
            // COMMITTED_RELAY_URL, e.g. a local `wrangler dev`: `ask` shows the disclosure,
            // `accepted` starts as if it was accepted. Without it the demo never uses a relay.
            if let mode = UserDefaults.standard.string(forKey: "demoRelay"),
               let relay = RelayConfiguration(info: Bundle.main.infoDictionary) {
                dependencies.relay = LiveRankRelayDependencies(
                    client: HTTPLiveRankRelayClient(baseURL: relay.baseURL),
                    store: InMemoryLiveRankRelayStore(),
                    environment: relay.environment
                )
                dependencies.makeLiveRankActivities = { ActivityKitLiveRankActivities(pushType: .token) }
                if mode == "accepted" {
                    dependencies.liveRankPersistence = InMemoryLiveRankPersistence(
                        LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true)
                    )
                }
            }
            let app = AppModel(dependencies)
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
