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
    /// The Competitor whose person view is open (pushed onto the Board, or the second pane on iPhone Duo), by
    /// login; nil when none is. Forgotten when the graph on screen changes.
    var selectedPerson: String?
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
    /// Where the real board's avatars are saved, for the app, Live rank and the widgets.
    private let avatarCache: AvatarCache
    /// Whether the app is in front, so a Connect GitHub that succeeds in the background (approved
    /// in Safari) doesn't try to start Live rank there.
    private var isActive = false
    /// Connect GitHub's device flow is running. Nothing starts or leaves the Sample board, and no
    /// second Connect GitHub starts, until it ends.
    private(set) var isConnecting = false
    private var connectTask: Task<Void, Never>?
    /// Why a Connect GitHub started on the Sample board didn't connect (declined, expired, or a
    /// network error). The Sample board stays underneath; Connect GitHub shows this with Try Again
    /// until Cancel. A cancelled Connect GitHub sets nothing.
    var sampleBoardConnectError: String?

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
        avatarCache: AvatarCache = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.avatarCache = avatarCache
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
        // A successful Connect GitHub replaces the Sample board before the real board's first
        // refresh, so that refresh and its Live rank run on screen, as after any Connect GitHub.
        services.onSignedIn = { [weak self] in await self?.realAccountConnected() }

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
        now: @escaping @Sendable () -> Date,
        isSampleBoard: Bool = false
    ) -> LiveRankController {
        let refresh = services.refresh
        let auth = services.auth
        return LiveRankController(
            store: services.store,
            activities: activities,
            relay: relay,
            preferences: preferences,
            isSignedIn: { auth.isSignedIn },
            rankDelta: { refresh.rankDelta(for: $0, in: $1) },
            now: now,
            isSampleBoard: isSampleBoard
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
        guard mode == .notConnected, !isConnecting else { return }
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
            preferences: InMemoryLiveRankPreferences(), now: now, isSampleBoard: true
        )
        wire(sample, liveRank: sampleLiveRank, avatars: NoAvatarPrefetching())
        realServices.refresh.pauseTimer()
        services = sample
        selectedPerson = nil
        liveRank = sampleLiveRank
        didRefreshIdentity = false
    }

    /// Leave Sample Board: ends its Live rank, resets the widgets, forgets every sample person and
    /// hide, and returns to Connect GitHub. Not while Connect GitHub is running.
    func leaveSampleBoard() async {
        guard mode == .sampleBoard, !isConnecting else { return }
        // Someone just tapped, so the app is open.
        await endSampleBoard(inForeground: true)
    }

    /// Connect GitHub succeeded: the real board replaces the Sample board, if it's showing.
    private func realAccountConnected() async {
        guard mode == .sampleBoard else { return }
        await endSampleBoard(inForeground: isActive)
    }

    /// Takes the Sample board down and puts the real graph on screen: Connect GitHub when it isn't
    /// connected, or the real board loading right after Connect GitHub.
    private func endSampleBoard(inForeground: Bool) async {
        let sample = services
        let sampleLiveRank = liveRank
        defaults?.removeObject(forKey: Self.sampleBoardKey)
        // Signing the sample graph out ends its Live rank and publishes no widget snapshot.
        sample.refresh.pauseTimer()
        sample.auth.signOut()
        services = realServices
        selectedPerson = nil
        liveRank = realLiveRank
        didRefreshIdentity = false
        liveRankDisclosureRequested = false
        sampleBoardConnectError = nil
        selectedTab = .board
        realServices.refresh.resumeTimer()
        publishWidgets()
        await sampleLiveRank.idle()
        // The real Live rank missed the scene's changes while the Sample board was up. In front,
        // it can start once connected, even after a launch that went straight to the Sample board.
        if inForeground {
            await realLiveRank.enteredForeground()
        } else {
            realLiveRank.enteredBackground()
        }
    }

    /// Write the widgets' snapshot for the board as it stands: nothing when disconnected. The
    /// Sample board's is marked, so the widgets show initials for its made-up people.
    func publishWidgets() {
        let refresh = services.refresh
        var snapshot = auth.isSignedIn
            ? WidgetSnapshot.board(store, window: liveRank.window, rankDelta: { [window = liveRank.window] in refresh.rankDelta(for: $0, in: window) }, now: now())
            : nil
        if mode == .sampleBoard { snapshot?.isSampleBoard = true }
        widgets.publish(snapshot)
    }

    /// The board for Share board, with as many people as its images take. The Sample board's is
    /// marked, so its image shows initials for the made-up people.
    func boardToShare() -> WidgetSnapshot? {
        let refresh = services.refresh
        var snapshot = WidgetSnapshot.board(
            store, window: store.selectedWindow, rankDelta: { [window = store.selectedWindow] in refresh.rankDelta(for: $0, in: window) }, now: now(),
            rows: BoardShareFormat.maxBoardRows
        )
        if mode == .sampleBoard { snapshot?.isSampleBoard = true }
        return snapshot
    }

    /// Saved avatars for the board, read before the network: none on the Sample board, whose
    /// made-up logins could match a real person's saved face. Its people show initials.
    var savedAvatars: AvatarCache? {
        mode == .sampleBoard ? nil : avatarCache
    }

    /// Connect GitHub screen versus the board, from the shared onboarding rule.
    var needsConnect: Bool {
        OnboardingFlow.step(isSignedIn: auth.isSignedIn) == .signIn
    }

    // MARK: - Lifecycle

    /// Becoming active resumes the 5-minute timer and refreshes only when the data is stale
    /// (older than about 2 minutes), so opening the app doesn't flash "updating" every time.
    func sceneDidBecomeActive() async {
        isActive = true
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
        isActive = false
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

    /// Opens `login`'s person view, as tapping their row on the Board does.
    func showPerson(_ login: String) {
        selectedPerson = login
    }

    /// The open person view's content as of now, or nil: nobody chosen, or they've left the board
    /// (hidden, or gone from your people), which closes it.
    var shownPerson: PersonSummary? {
        selectedPerson.flatMap { store.person($0, asOf: now(), calendar: .current) }
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
    /// It always connects the real account. From the Sample board, the code shows over it and the
    /// Sample board stays up underneath: only success replaces it (with no sample person or hide
    /// left), before the real board's first refresh. A declined or expired code returns to it with
    /// `sampleBoardConnectError`; Cancel returns to it with nothing.
    func connectGitHub() async {
        guard !isConnecting else { return }
        // The real account's sign-in, whatever graph is on screen, taken before anything suspends.
        let auth = realServices.auth
        let fromSampleBoard = mode == .sampleBoard
        isConnecting = true
        sampleBoardConnectError = nil
        let token = backgroundTime.begin("Connect GitHub")
        defer {
            backgroundTime.end(token)
            connectTask = nil
            isConnecting = false
        }
        // Its own task, so Cancel can stop the device flow wherever Connect GitHub was started.
        let signIn = Task { await auth.signIn() }
        connectTask = signIn
        await signIn.value
        if fromSampleBoard, !auth.isSignedIn {
            sampleBoardConnectError = auth.errorMessage
        }
    }

    /// Stop Connect GitHub: no error, and the screen it started from stays (the Sample board, or
    /// Connect GitHub).
    func cancelConnect() {
        connectTask?.cancel()
    }

    /// The account Connect GitHub signs in, and whose code it shows: always the real one.
    var connectAuth: AuthModel { realServices.auth }

    /// Connect GitHub was started on the Sample board and is still running: its code shows over the
    /// Sample board, wherever it was started.
    var isConnectingFromSampleBoard: Bool {
        isConnecting && mode == .sampleBoard
    }

    /// Connect GitHub covers the Sample board: while it runs, and after it fails, with the reason
    /// and Try Again. Cancel (`closeConnectOverSampleBoard`) uncovers the Sample board.
    var isShowingConnectOverSampleBoard: Bool {
        mode == .sampleBoard && (isConnecting || sampleBoardConnectError != nil)
    }

    /// Cancel over the Sample board: stops a running Connect GitHub, or dismisses a failed one.
    func closeConnectOverSampleBoard() {
        cancelConnect()
        sampleBoardConnectError = nil
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
