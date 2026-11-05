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
    /// Loads your people (follows plus accessible org members) with a token.
    var rosterFetch: @Sendable (URLSession, String) async throws -> GitHubRosterSnapshot = { session, token in
        try await GitHubAccountClient(token: token, session: session).roster()
    }
    /// Seconds between refreshes while the app is active.
    var refreshInterval: TimeInterval = 300
    /// The wait between device-flow polls (real sleeping in production).
    var authSleep: @Sendable (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }
    var now: @Sendable () -> Date = { Date() }
    /// Where the Leaderboard Notifications toggle is saved, and the center that shows them.
    var notificationDefaults: UserDefaults = .standard
    var notificationCenter: any NotificationCentering = SystemNotificationCenter()
    /// ActivityKit, for Live rank. The default never shows anything (the unit-test host).
    var makeLiveRankActivities: @MainActor () -> any LiveRankActivities = { NoLiveRankActivities() }
    var liveRankPersistence: any LiveRankPersistence = InMemoryLiveRankPersistence()
    /// Ask iOS for the next background refresh (`BGAppRefreshTask`).
    var scheduleBackgroundRefresh: @Sendable () -> Void = {}

    static func live() -> AppDependencies {
        var dependencies = AppDependencies(
            credentials: KeychainGitHubCredentialStore(),
            gitHubSession: .shared,
            contributions: ContributionsClient(),
            competitorPersistence: UserDefaultsCompetitorPersistence(),
            snapshotPersistence: UserDefaultsStandingsSnapshotPersistence(),
            hiddenPeoplePersistence: UserDefaultsHiddenPeoplePersistence(),
            rosterPersistence: UserDefaultsGitHubRosterPersistence()
        )
        dependencies.makeLiveRankActivities = { ActivityKitLiveRankActivities() }
        dependencies.liveRankPersistence = UserDefaultsLiveRankPersistence()
        dependencies.scheduleBackgroundRefresh = { BackgroundRefresh.schedule() }
        return dependencies
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
    let liveRank: LiveRankController
    private let scheduleBackgroundRefresh: @Sendable () -> Void

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
            fetch: { [rosterFetch = dependencies.rosterFetch] in try await rosterFetch(session, $0) }
        )
        let notifications = NotificationService(
            defaults: dependencies.notificationDefaults,
            center: dependencies.notificationCenter
        )
        let liveRank = LiveRankController(
            store: store,
            activities: dependencies.makeLiveRankActivities(),
            persistence: dependencies.liveRankPersistence,
            now: dependencies.now
        )
        let refresh = RefreshCoordinator(
            store: store,
            client: dependencies.contributions,
            interval: dependencies.refreshInterval,
            now: dependencies.now,
            notifier: notifications,
            // Live rank can follow another Window than the board; keep it current too.
            additionalWindows: { liveRank.windowsToRefresh },
            // A manual refresh (pull-to-refresh, Retry, Connect) also re-syncs people.
            beforeRefresh: { reason in await roster.refresh(force: reason == .manual) },
            // Every refresh, timer ticks and background refresh included, updates Live rank.
            afterRefresh: { _ in await liveRank.sync() }
        )
        liveRank.rankDelta = { [weak refresh] in refresh?.rankDelta(for: $0) }
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
            onSignedIn: { _ in
                liveRank.connected()
                await refresh.refreshAll(reason: .manual)
            },
            onSignedOut: {
                refresh.invalidate()
                roster.disconnect()
                liveRank.disconnected()
            }
        )
        if auth.isSignedIn { liveRank.connected() }
        self.store = store
        self.roster = roster
        self.refresh = refresh
        self.auth = auth
        self.notifications = notifications
        self.liveRank = liveRank
        scheduleBackgroundRefresh = dependencies.scheduleBackgroundRefresh
    }

    // MARK: - Refresh policy

    /// The app came to the foreground (including launch): resume the timer, and refresh only
    /// when the board is older than about two minutes so opening the app doesn't flash
    /// "updating" every time.
    func sceneDidBecomeActive() async {
        refresh.resumeTimer()
        // Ends strays from an earlier launch, restarts Live rank if iOS ended it, and picks up
        // a change to Live Activities in iOS Settings.
        await liveRank.enteredForeground()
        guard auth.isSignedIn, refresh.shouldRefreshOnOpen else { return }
        await refresh.refreshAll(reason: .becameActive)
    }

    /// The app left the foreground: no timer refreshes until it's active again, and iOS is asked
    /// for a background refresh so Live rank keeps up while the app is closed.
    func sceneDidEnterBackground() {
        refresh.pauseTimer()
        liveRank.enteredBackground()
        if auth.isSignedIn { scheduleBackgroundRefresh() }
    }

    /// A `BGAppRefreshTask` run: refresh (which updates Live rank) and ask for the next one.
    func backgroundRefresh() async {
        guard auth.isSignedIn else { return }
        await refresh.refreshAll(reason: .backgroundRefresh)
        scheduleBackgroundRefresh()
    }

    // MARK: - Live rank

    func setLiveRankEnabled(_ enabled: Bool) async {
        await liveRank.setEnabled(enabled)
        await refreshLiveRankWindowIfStale()
    }

    /// Live rank's own Window (Settings), separate from the board's: ends the activity, starts
    /// one for the new Window with the numbers on hand, then fetches them if they're stale.
    func setLiveRankWindow(_ window: ContributionWindow) async {
        await liveRank.setWindow(window)
        await refreshLiveRankWindowIfStale()
    }

    private func refreshLiveRankWindowIfStale() async {
        guard auth.isSignedIn, let window = liveRank.windowsToRefresh.first, refresh.needsRefresh(for: window) else { return }
        await refresh.refreshAll(reason: .windowChanged)
    }

    /// The Window switch changed: cached numbers are already showing; fetch only when stale.
    func windowDidChange() async {
        guard auth.isSignedIn, refresh.needsRefresh(for: store.selectedWindow) else { return }
        await refresh.refreshAll(reason: .windowChanged)
    }

    // MARK: - People and account

    /// Hide or show someone from the People tab. The board changes before this returns; the
    /// returned task is the one-person refresh after showing someone again. Every visibility
    /// change on iPhone comes through here, so anything that mirrors the visible board (Live
    /// rank, the relay) hooks in below.
    @discardableResult
    func setHidden(_ hidden: Bool, username: String) -> Task<Void, Never>? {
        let refreshOne = PeopleDirectory.setHidden(hidden, username: username, store: store, refresh: refresh)
        // Live rank follows the board right away, not at the next refresh.
        liveRank.scheduleSync()
        return refreshOne
    }

    /// Settings → Disconnect GitHub: delete the token and this account's cached people and counts,
    /// keeping visibility choices for a later reconnect. Anything else to revoke on disconnect
    /// (Live rank, the relay registration) goes here.
    func disconnect() {
        auth.signOut()
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
