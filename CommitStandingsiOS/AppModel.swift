import Foundation
import Observation

/// Everything the iPhone app talks to outside itself. `live()` is production; tests and the
/// DEBUG demo board swap in fakes. GitHub stays reachable only through `gitHubSession`, and
/// the token only through `credentials`.
struct AppDependencies {
    var credentials: any GitHubCredentialStoring
    var gitHubSession: URLSession
    var contributions: any ContributionsFetching
    var competitorPersistence: any CompetitorPersistence
    var snapshotPersistence: any StandingsSnapshotPersistence
    var hiddenPeoplePersistence: any HiddenPeoplePersistence
    var rosterPersistence: (any GitHubRosterPersistence)?
    /// Seconds between refreshes while the app is active.
    var refreshInterval: TimeInterval = 300
    /// The wait between device-flow polls (real sleeping in production).
    var authSleep: @Sendable (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }
    var now: @Sendable () -> Date = { Date() }

    static func live() -> AppDependencies {
        AppDependencies(
            credentials: KeychainGitHubCredentialStore(),
            gitHubSession: .shared,
            contributions: ContributionsClient(),
            competitorPersistence: UserDefaultsCompetitorPersistence(),
            snapshotPersistence: UserDefaultsStandingsSnapshotPersistence(),
            hiddenPeoplePersistence: UserDefaultsHiddenPeoplePersistence(),
            rosterPersistence: UserDefaultsGitHubRosterPersistence()
        )
    }
}

/// The iPhone app's composition root: the same shared core the Mac wires up in
/// `CommitStandingsApp.init` (store, roster, refresh, auth, notifications), plus the
/// iPhone-only app state (selected tab, scene-phase and deep-link handling).
@Observable
@MainActor
final class AppModel {
    enum Tab: Hashable { case board, people, settings }

    var selectedTab: Tab = .board
    let store: StandingsStore
    let roster: GitHubRoster
    let refresh: RefreshCoordinator
    let auth: AuthModel
    let notifications: NotificationService

    init(_ dependencies: AppDependencies) {
        let store = StandingsStore(
            persistence: dependencies.competitorPersistence,
            snapshotPersistence: dependencies.snapshotPersistence,
            hiddenPeoplePersistence: dependencies.hiddenPeoplePersistence
        )
        let credentials = dependencies.credentials
        let session = dependencies.gitHubSession
        let roster = GitHubRoster(
            store: store,
            credentials: credentials,
            persistence: dependencies.rosterPersistence,
            now: dependencies.now,
            fetch: { try await GitHubAccountClient(token: $0, session: session).roster() }
        )
        let notifications = NotificationService()
        let refresh = RefreshCoordinator(
            store: store,
            client: dependencies.contributions,
            interval: dependencies.refreshInterval,
            now: dependencies.now,
            notifier: notifications,
            // A manual refresh (pull-to-refresh, Retry, Connect) also re-syncs people.
            beforeRefresh: { reason in await roster.refresh(force: reason == .manual) }
        )
        let auth = AuthModel(
            credentials: credentials,
            auth: GitHubAuth(
                clientID: GitHubConfig.clientID,
                scope: GitHubConfig.scope,
                session: session,
                sleep: dependencies.authSleep,
                now: dependencies.now
            ),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            onSignedIn: { _ in await refresh.refreshAll(reason: .manual) },
            onSignedOut: { refresh.invalidate(); roster.disconnect() }
        )
        self.store = store
        self.roster = roster
        self.refresh = refresh
        self.auth = auth
        self.notifications = notifications
    }

    // MARK: - Refresh policy

    /// The app came to the foreground (including launch): resume the timer, and refresh only
    /// when the board is older than about two minutes so opening the app doesn't flash
    /// "updating" every time.
    func sceneDidBecomeActive() async {
        refresh.resumeTimer()
        guard auth.isSignedIn, refresh.shouldRefreshOnOpen else { return }
        await refresh.refreshAll(reason: .becameActive)
    }

    /// The app left the foreground: no timer refreshes until it's active again.
    func sceneDidEnterBackground() {
        refresh.pauseTimer()
    }

    /// The Window switch changed: cached numbers are already showing; fetch only when stale.
    func windowDidChange() async {
        guard auth.isSignedIn, refresh.needsRefresh(for: store.selectedWindow) else { return }
        await refresh.refreshAll(reason: .windowChanged)
    }

    // MARK: - Deep links

    /// Handle `committed://board?window=<daily|weekly|monthly>` (Live rank taps use it): show
    /// the Board on that Window, or on the current Window when none is given. Returns false,
    /// changing nothing, for links it doesn't understand.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard url.scheme == "committed", url.host() == "board" else { return false }
        let windowValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "window" }?.value
        var window: ContributionWindow?
        if let windowValue {
            guard let requested = ContributionWindow(rawValue: windowValue) else { return false }
            window = requested
        }
        selectedTab = .board
        if let window { store.selectedWindow = window }
        return true
    }
}
