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
        SystemChrome.apply()
    }

    private static var loadsGitHubAvatars: Bool {
        #if DEBUG
        if ScreenshotFixture.isRequested { return false }
        #endif
        return true
    }

    private static func makeModel() -> AppModel {
        #if DEBUG
        if ScreenshotFixture.isRequested {
            let model = AppModel(
                services: ScreenshotFixture.services(), backgroundTime: UIApplicationBackgroundTime(),
                liveRankActivities: ScreenshotFixture.liveRankActivities(ActivityKitLiveRankActivities()),
                liveRankPreferences: ScreenshotFixture.liveRankPreferences(),
                liveRankRelay: makeLiveRankRelay(),
                avatars: ScreenshotFixture.avatars(),
                widgets: WidgetPublisher()
            )
            if let tab = ScreenshotFixture.requestedTab { model.selectedTab = tab }
            return model
        }
        #endif
        let services = CommittedServices.live()
        // A unit-test host never shows a Live Activity or touches saved Live rank settings, and
        // never reopens a saved Sample board.
        guard !CommittedServices.isRunningTests else {
            return AppModel(services: services, backgroundTime: UIApplicationBackgroundTime())
        }
        let model = AppModel(
            services: services,
            // Reopening the app returns to the Sample board.
            defaults: .standard,
            backgroundTime: UIApplicationBackgroundTime(),
            liveRankActivities: ActivityKitLiveRankActivities(),
            liveRankPreferences: UserDefaultsLiveRankPreferences(),
            liveRankRelay: makeLiveRankRelay(),
            avatars: GitHubAvatarPrefetcher.live(),
            widgets: WidgetPublisher()
        )
        #if DEBUG
        if let tab = ScreenshotFixture.requestedTab { model.selectedTab = tab }
        #endif
        return model
    }

    /// Keeps ActivityKit's token observers alive for the app's lifetime.
    private static var liveRankTokens: ActivityKitLiveRankTokens?

    /// The Committed relay when the `COMMITTED_RELAY_URL` build setting names one (phase 2), with
    /// ActivityKit's token streams feeding it from launch. Otherwise phase 1: no relay.
    private static func makeLiveRankRelay() -> any LiveRankRegistrar {
        let settings = LiveRankRelaySettings.main
        guard let baseURL = settings.baseURL else { return NoLiveRankRelay() }
        let registrar = RelayLiveRankRegistrar(
            api: URLSessionLiveRankRelayAPI(baseURL: baseURL),
            installations: KeychainRelayInstallationStore(),
            apnsEnvironment: settings.apnsEnvironment,
            backgroundTime: UIApplicationBackgroundTime()
        )
        let tokens = ActivityKitLiveRankTokens(receiver: registrar)
        tokens.start()
        liveRankTokens = tokens
        LiveRankLog.relay.info("relay \(baseURL.absoluteString, privacy: .public), \(settings.apnsEnvironment.rawValue, privacy: .public)")
        return registrar
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
                // The Sample board's people are made up (some may be real GitHub users), and
                // nothing on it leaves the phone: initials only.
                .environment(\.loadsGitHubAvatars, CommittedApp.loadsGitHubAvatars && model.mode != .sampleBoard)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [model] in
            await model.backgroundRefresh()
            await BackgroundRefresh.schedule()
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
