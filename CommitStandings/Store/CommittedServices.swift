import Foundation

/// The object graph both apps run on: the board store, the automatic GitHub roster, the refresh
/// coordinator, sign-in, and Leaderboard Notifications. Built in one place so the Mac and iPhone
/// wire them identically: a manual refresh also re-syncs people, signing in loads the board, and
/// disconnecting drops this account's people and in-flight counts.
@MainActor
final class CommittedServices {
    let store: StandingsStore
    let roster: GitHubRoster
    let refresh: RefreshCoordinator
    let auth: AuthModel
    let notifications: NotificationService

    init(
        store: StandingsStore,
        credentials: any GitHubCredentialStoring,
        rosterPersistence: (any GitHubRosterPersistence)? = nil,
        legacyBackup: (any CompetitorPersistence)? = nil,
        contributions: any ContributionsFetching = ContributionsClient(),
        notifications: NotificationService = NotificationService(),
        gitHubAuth: GitHubAuth = GitHubAuth(clientID: GitHubConfig.clientID, scope: GitHubConfig.scope),
        accountFactory: @escaping @Sendable (String) -> GitHubAccountClient = { GitHubAccountClient(token: $0) },
        fetchRoster: @escaping @Sendable (String) async throws -> GitHubRosterSnapshot = {
            try await GitHubAccountClient(token: $0).roster()
        },
        refreshInterval: TimeInterval = 300,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let roster = GitHubRoster(
            store: store, credentials: credentials,
            persistence: rosterPersistence, legacyBackup: legacyBackup,
            now: now, fetch: fetchRoster
        )
        // The contributions scrape is anonymous, so the standings client needs no token.
        let refresh = RefreshCoordinator(
            store: store, client: contributions, interval: refreshInterval, now: now,
            notifier: notifications,
            beforeRefresh: { reason in await roster.refresh(force: reason == .manual) }
        )
        self.store = store
        self.roster = roster
        self.refresh = refresh
        self.notifications = notifications
        self.auth = AuthModel(
            credentials: credentials,
            auth: gitHubAuth,
            accountFactory: accountFactory,
            onSignedIn: { _ in await refresh.refreshAll(reason: .manual) },
            onSignedOut: { refresh.invalidate(); roster.disconnect() }
        )
    }

    /// True inside a unit-test host, which must never read or change the signed-in user's
    /// Keychain token or saved board.
    static var isRunningTests: Bool { NSClassFromString("XCTestCase") != nil }

    /// Production storage: saved standings and people show immediately on launch, and the token
    /// lives in this device's Keychain. A test host gets in-memory storage instead.
    static func live(isTesting: Bool = isRunningTests) -> CommittedServices {
        guard !isTesting else {
            return CommittedServices(
                store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
                credentials: InMemoryGitHubCredentialStore()
            )
        }
        #if os(macOS)
        // Mac users from before the automatic roster keep a backup of their hand-made list.
        let legacyBackup: (any CompetitorPersistence)? = UserDefaultsCompetitorPersistence(key: "competitors.manual-backup.v1")
        #else
        let legacyBackup: (any CompetitorPersistence)? = nil
        #endif
        return CommittedServices(
            store: StandingsStore(
                snapshotPersistence: UserDefaultsStandingsSnapshotPersistence(),
                hiddenPeoplePersistence: UserDefaultsHiddenPeoplePersistence()
            ),
            credentials: KeychainGitHubCredentialStore(),
            rosterPersistence: UserDefaultsGitHubRosterPersistence(),
            legacyBackup: legacyBackup
        )
    }
}
