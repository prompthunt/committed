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
    /// The switch in Settings asked for the relay disclosure.
    private var liveRankDisclosureRequested = false

    let services: CommittedServices
    /// Live rank in the Dynamic Island and on the Lock Screen.
    let liveRank: LiveRankController
    private let backgroundTime: any BackgroundTimeProviding
    /// The Home Screen and Lock Screen widgets' snapshot.
    private let widgets: WidgetPublisher
    private let now: @Sendable () -> Date
    private var didRefreshIdentity = false

    var store: StandingsStore { services.store }
    var refresh: RefreshCoordinator { services.refresh }
    var auth: AuthModel { services.auth }
    var roster: GitHubRoster { services.roster }

    /// The Live rank defaults never show an activity, and the widget default writes nothing, for
    /// tests and previews. The app passes ActivityKit, saved preferences, and the App Group.
    init(
        services: CommittedServices,
        backgroundTime: any BackgroundTimeProviding,
        liveRankActivities: any LiveRankActivities = NoLiveRankActivities(),
        liveRankPreferences: any LiveRankPreferenceStoring = InMemoryLiveRankPreferences(),
        liveRankRelay: any LiveRankRegistrar = NoLiveRankRelay(),
        avatars: any AvatarPrefetching = NoAvatarPrefetching(),
        widgets: WidgetPublisher = WidgetPublisher(save: { _ in }, reload: {}),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.services = services
        self.backgroundTime = backgroundTime
        self.widgets = widgets
        self.now = now
        let refresh = services.refresh
        let auth = services.auth
        let liveRank = LiveRankController(
            store: services.store,
            activities: liveRankActivities,
            relay: liveRankRelay,
            preferences: liveRankPreferences,
            isSignedIn: { auth.isSignedIn },
            rankDelta: { refresh.rankDelta(for: $0) },
            now: now
        )
        self.liveRank = liveRank
        // Every refresh also brings Live rank's Window up to date and then updates the activity.
        // Avatars for the board are saved first: Live rank can't load images, so it reads them
        // from the App Group (`AvatarCache`) when it renders.
        // The widgets show Live rank's Window, so it stays fresh even with Live rank off.
        let store = services.store
        refresh.additionalWindows = {
            auth.isSignedIn ? liveRank.windowsToRefresh + [liveRank.window] : liveRank.windowsToRefresh
        }
        refresh.didRefresh = { [weak self] _ in
            await avatars.prefetch(store.visibleCompetitors.map(\.username))
            await liveRank.sync()
            self?.publishWidgets()
        }
        services.onDisconnect = { [weak self] in
            liveRank.disconnected()
            self?.publishWidgets()
        }
    }

    /// Write the widgets' snapshot for the board as it stands: nothing when disconnected.
    func publishWidgets() {
        let refresh = services.refresh
        widgets.publish(auth.isSignedIn
            ? WidgetSnapshot.board(store, window: liveRank.window, rankDelta: { refresh.rankDelta(for: $0) }, now: now())
            : nil)
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
        // Ends strays from an earlier launch, and restarts Live rank if iOS ended it.
        await liveRank.enteredForeground()
        // Saved numbers reach the widgets now, before any refresh (and after an update from a
        // build without widgets).
        publishWidgets()
        await liveRank.retryRelay()
        guard auth.isSignedIn else { return }
        if !didRefreshIdentity {
            didRefreshIdentity = true
            // A relaunch never ran sign-in, so fetch the display name for the summary.
            await auth.refreshIdentity()
        }
        if refresh.shouldRefreshOnOpen || liveRankNeedsRefresh {
            await refresh.refreshAll(reason: .becameActive)
        }
    }

    /// The timer pauses in the background; iOS would suspend it anyway.
    func sceneDidEnterBackground() {
        refresh.pauseTimer()
        liveRank.enteredBackground()
    }

    /// Background app refresh: people and Contributions, then Live rank (update only; iOS doesn't
    /// let the app start one from the background).
    func backgroundRefresh() async {
        await liveRank.retryRelay()
        guard auth.isSignedIn else { return }
        await refresh.refreshAll(reason: .background)
    }

    // MARK: - Live rank

    /// The Committed relay disclosure sheet: offered once after Connect GitHub, and whenever the
    /// switch is turned on before it's been accepted.
    var isShowingLiveRankDisclosure: Bool {
        get {
            guard auth.isSignedIn, !needsConnect else { return false }
            return liveRank.requiresRelayDisclosure && (liveRankDisclosureRequested || liveRank.offersRelayDisclosure)
        }
        set {
            if !newValue { liveRankDisclosureRequested = false }
        }
    }

    /// The Live rank switch in Settings. Turning it on asks first when the relay needs the disclosure.
    func liveRankSwitchChanged(_ enabled: Bool) async {
        if enabled && liveRank.requiresRelayDisclosure {
            liveRankDisclosureRequested = true
            return
        }
        await setLiveRankEnabled(enabled)
    }

    func acceptLiveRankDisclosure() async {
        liveRankDisclosureRequested = false
        await liveRank.acceptRelayDisclosure()
        await refreshLiveRankIfStale()
    }

    func declineLiveRankDisclosure() async {
        liveRankDisclosureRequested = false
        await liveRank.declineRelayDisclosure()
    }

    func setLiveRankEnabled(_ enabled: Bool) async {
        await liveRank.setEnabled(enabled)
        await refreshLiveRankIfStale()
    }

    func setLiveRankWindow(_ window: ContributionWindow) async {
        await liveRank.setWindow(window)
        publishWidgets()
        await refreshLiveRankIfStale()
    }

    /// Hiding or showing someone updates Live rank and the widgets right away while the app is open.
    func visibilityDidChange() async {
        await liveRank.sync()
        publishWidgets()
    }

    /// Live rank's Window, when Live rank or the widgets need it fetched.
    private var liveRankNeedsRefresh: Bool {
        (liveRank.windowsToRefresh + [liveRank.window]).contains { refresh.needsRefresh(for: $0) }
    }

    /// A Window Live rank hasn't loaded yet is fetched now (the refresh then updates Live rank).
    private func refreshLiveRankIfStale() async {
        guard auth.isSignedIn, liveRankNeedsRefresh else { return }
        await refresh.refreshAll(reason: .windowChanged)
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
