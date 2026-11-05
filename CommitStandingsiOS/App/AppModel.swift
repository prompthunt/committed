import Foundation
import Observation

/// The iPhone app's tabs. Each tab owns its own `NavigationStack`.
enum AppTab: Hashable, CaseIterable {
    case board
    case people
    case settings
}

/// Extra running time while the app is in the background, so the device-flow poll keeps going for
/// a while after the user switches to Safari. A seam over `UIApplication.beginBackgroundTask`.
@MainActor
protocol BackgroundTimeProviding {
    func begin(_ name: String) -> Int
    func end(_ token: Int)
}

/// iPhone app state and lifecycle on top of the shared core: which tab is showing, when the board
/// refreshes, and deep links. Views call these methods; all ranking, roster, and sign-in logic
/// stays in the shared `CommittedServices`.
@Observable
@MainActor
final class AppModel {
    var selectedTab: AppTab = .board

    let services: CommittedServices
    private let backgroundTime: any BackgroundTimeProviding
    private var didRefreshIdentity = false

    var store: StandingsStore { services.store }
    var refresh: RefreshCoordinator { services.refresh }
    var auth: AuthModel { services.auth }
    var roster: GitHubRoster { services.roster }

    init(services: CommittedServices, backgroundTime: any BackgroundTimeProviding) {
        self.services = services
        self.backgroundTime = backgroundTime
    }

    /// Connect GitHub screen versus the board, from the shared onboarding rule.
    var needsConnect: Bool {
        OnboardingFlow.step(isSignedIn: auth.isSignedIn) == .signIn
    }

    // MARK: - Lifecycle

    /// Becoming active resumes the 5-minute timer and refreshes only when the data is stale
    /// (older than about 2 minutes), so opening the app doesn't flash "updating" every time.
    func sceneDidBecomeActive() async {
        refresh.resumeTimer()
        guard auth.isSignedIn else { return }
        if !didRefreshIdentity {
            didRefreshIdentity = true
            // A relaunch never ran sign-in, so fetch the display name for the summary.
            await auth.refreshIdentity()
        }
        if refresh.shouldRefreshOnOpen {
            await refresh.refreshAll(reason: .becameActive)
        }
    }

    /// The timer pauses in the background; iOS would suspend it anyway.
    func sceneDidEnterBackground() {
        refresh.pauseTimer()
    }

    /// Switching Window shows cached numbers instantly and fetches only when they're stale.
    func windowDidChange() async {
        guard auth.isSignedIn, refresh.needsRefresh(for: store.selectedWindow) else { return }
        await refresh.refreshAll(reason: .windowChanged)
    }

    /// Pull-to-refresh is the manual Refresh: people plus Contributions. If a timer refresh is
    /// already running, wait for it so the manual one (which also re-syncs people) still happens.
    func pullToRefresh() async {
        guard auth.isSignedIn else { return }
        while refresh.isRefreshing {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
        }
        await refresh.refreshAll(reason: .manual)
    }

    // MARK: - Connect GitHub

    /// Runs the device flow, holding background time so polling continues across the Safari
    /// hand-off. If iOS suspends the app anyway, polling resumes on return, and a code that
    /// expired meanwhile is reported then.
    func connectGitHub() async {
        let token = backgroundTime.begin("Connect GitHub")
        defer { backgroundTime.end(token) }
        await auth.signIn()
    }

    // MARK: - Deep links

    /// `committed://board?window=…` opens the Board on that Window. Returns whether it handled the URL.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        switch link {
        case .board(let window):
            selectedTab = .board
            if let window { store.selectedWindow = window }
        }
        return true
    }
}
