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
///
/// The model runs one of two graphs. The real one (the Keychain token and the saved board) is
/// built once at launch. The Sample board's is built on `SampleServices` when it starts and thrown
/// away when it ends, with its own Live rank on the no-relay path. `services`, `store`, `auth`,
/// `liveRank` and the rest always name the graph on screen.
@Observable
@MainActor
final class AppModel {
    /// Connected to GitHub, on the Sample board, or neither (the Connect GitHub screen).
    enum Mode: Equatable {
        case connected
        case sampleBoard
        case notConnected
    }

    var selectedTab: AppTab = .board
    /// The switch in Settings asked for the relay disclosure.
    private var liveRankDisclosureRequested = false

    /// The graph on screen: the real one, or the Sample board's.
    private(set) var services: CommittedServices
    /// Live rank in the Dynamic Island and on the Lock Screen, for the graph on screen.
    private(set) var liveRank: LiveRankController
    /// The real graph and its Live rank, kept while the Sample board is showing.
    private let realServices: CommittedServices
    private let realLiveRank: LiveRankController
    private let makeSampleServices: () -> CommittedServices
    private let defaults: UserDefaults?
    private let liveRankActivities: any LiveRankActivities
    private let backgroundTime: any BackgroundTimeProviding
    /// The Home Screen and Lock Screen widgets' snapshot. One publisher for both graphs, so its
    /// de-duplication spans a switch.
    private let widgets: WidgetPublisher
    private let now: @Sendable () -> Date
    private var didRefreshIdentity = false

    var store: StandingsStore { services.store }
    var refresh: RefreshCoordinator { services.refresh }
    var auth: AuthModel { services.auth }
    var roster: GitHubRoster { services.roster }

    /// Where the Sample board is remembered across launches (UserDefaults).
    nonisolated static let sampleBoardKey = "sampleBoard.v1"

    /// `services` is the real graph. `defaults` remembers the Sample board across launches; nil
    /// keeps it in memory (tests, previews, the screenshot fixture). The Live rank defaults never
    /// show an activity, and the widget default writes nothing, for tests and previews. The app
    /// passes ActivityKit, saved preferences, the relay, and the App Group.
    init(
        services: CommittedServices,
        sampleServices: @escaping () -> CommittedServices = { SampleServices.make() },
        defaults: UserDefaults? = nil,
        backgroundTime: any BackgroundTimeProviding,
        liveRankActivities: any LiveRankActivities = NoLiveRankActivities(),
        liveRankPreferences: any LiveRankPreferenceStoring = InMemoryLiveRankPreferences(),
        liveRankRelay: any LiveRankRegistrar = NoLiveRankRelay(),
        avatars: any AvatarPrefetching = NoAvatarPrefetching(),
        widgets: WidgetPublisher = WidgetPublisher(save: { _ in }, reload: {}),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.realServices = services
        self.makeSampleServices = sampleServices
        self.defaults = defaults
        self.liveRankActivities = liveRankActivities
        self.backgroundTime = backgroundTime
        self.widgets = widgets
        self.now = now
        let realLiveRank = Self.makeLiveRank(
            for: services, activities: liveRankActivities, relay: liveRankRelay,
            preferences: liveRankPreferences, now: now
        )
        self.realLiveRank = realLiveRank
        self.services = services
        self.liveRank = realLiveRank
        wire(services, liveRank: realLiveRank, avatars: avatars)

        // A relaunch returns to the Sample board, unless a real account is connected.
        if defaults?.bool(forKey: Self.sampleBoardKey) == true {
            if services.auth.isSignedIn {
                defaults?.removeObject(forKey: Self.sampleBoardKey)
            } else {
                showSampleBoard()
            }
        }
    }

    private static func makeLiveRank(
        for services: CommittedServices,
        activities: any LiveRankActivities,
        relay: any LiveRankRegistrar,
        preferences: any LiveRankPreferenceStoring,
        now: @escaping @Sendable () -> Date
    ) -> LiveRankController {
        let refresh = services.refresh
        let auth = services.auth
        return LiveRankController(
            store: services.store,
            activities: activities,
            relay: relay,
            preferences: preferences,
            isSignedIn: { auth.isSignedIn },
            rankDelta: { refresh.rankDelta(for: $0) },
            now: now
        )
    }

    /// Hooks a graph up to its Live rank and to the widgets. A graph that's no longer on screen
    /// never writes the widgets.
    private func wire(_ services: CommittedServices, liveRank: LiveRankController, avatars: any AvatarPrefetching) {
        let refresh = services.refresh
        let auth = services.auth
        let store = services.store
        // Every refresh also brings Live rank's Window up to date and then updates the activity.
        // Avatars for the board are saved first: Live rank can't load images, so it reads them
        // from the App Group (`AvatarCache`) when it renders.
        // The widgets show Live rank's Window, so it stays fresh even with Live rank off.
        refresh.additionalWindows = {
            auth.isSignedIn ? liveRank.windowsToRefresh + [liveRank.window] : liveRank.windowsToRefresh
        }
        refresh.didRefresh = { [weak self, weak services] _ in
            await avatars.prefetch(store.visibleCompetitors.map(\.username))
            await liveRank.sync()
            if let self, let services, self.services === services { self.publishWidgets() }
        }
        services.onDisconnect = { [weak self, weak services] in
            liveRank.disconnected()
            if let self, let services, self.services === services { self.publishWidgets() }
        }
    }

    // MARK: - Sample board

    var mode: Mode {
        if services !== realServices { return .sampleBoard }
        return auth.isSignedIn ? .connected : .notConnected
    }

    /// Try a sample board, from Connect GitHub: the real app on built-in sample data, with nothing
    /// sent over the network. Remembered until it's left or replaced by Connect GitHub.
    func startSampleBoard() async {
        guard mode == .notConnected else { return }
        defaults?.set(true, forKey: Self.sampleBoardKey)
        selectedTab = .board
        showSampleBoard()
        await sceneDidBecomeActive()
    }

    /// Builds the Sample board's graph and puts it on screen. Its Live rank stays on the phone
    /// (`NoLiveRankRelay`, whatever the build's relay) with settings that aren't saved, and it
    /// never loads avatars over the network.
    private func showSampleBoard() {
        let sample = makeSampleServices()
        let sampleLiveRank = Self.makeLiveRank(
            for: sample, activities: liveRankActivities, relay: NoLiveRankRelay(),
            preferences: InMemoryLiveRankPreferences(), now: now
        )
        wire(sample, liveRank: sampleLiveRank, avatars: NoAvatarPrefetching())
        realServices.refresh.pauseTimer()
        services = sample
        liveRank = sampleLiveRank
        didRefreshIdentity = false
    }

    /// Leave Sample Board: ends its Live rank, resets the widgets, forgets every sample person and
    /// hide, and returns to Connect GitHub.
    func leaveSampleBoard() async {
        guard mode == .sampleBoard else { return }
        let sample = services
        let sampleLiveRank = liveRank
        defaults?.removeObject(forKey: Self.sampleBoardKey)
        // Signing the sample graph out ends its Live rank and publishes no widget snapshot.
        sample.refresh.pauseTimer()
        sample.auth.signOut()
        services = realServices
        liveRank = realLiveRank
        didRefreshIdentity = false
        liveRankDisclosureRequested = false
        selectedTab = .board
        realServices.refresh.resumeTimer()
        publishWidgets()
        await sampleLiveRank.idle()
        // The app is open (someone just tapped), so the real Live rank can start once connected,
        // even after a launch that went straight to the Sample board.
        await realLiveRank.enteredForeground()
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
    ///
    /// From the Sample board, it's left first: Connect GitHub shows over the real graph, and the
    /// real board loads with no sample person or hide. A declined or expired code stays on Connect
    /// GitHub, where Try a sample board is one tap away.
    func connectGitHub() async {
        let token = backgroundTime.begin("Connect GitHub")
        defer { backgroundTime.end(token) }
        await leaveSampleBoard()
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
