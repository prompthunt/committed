import Foundation
import UserNotifications
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
    /// login; nil when none is. Forgotten when the graph on screen changes. Closing it, or showing
    /// someone else, drops a Challenge asked for them.
    var selectedPerson: String? {
        didSet { if selectedPerson != requestedChallenge { requestedChallenge = nil } }
    }
    /// The switch in Settings asked for the relay disclosure.
    private var liveRankDisclosureRequested = false
    /// A notification switch asked for the relay notifications sheet.
    private var relayNotificationsConsentRequested = false
    /// The switch turned on that's waiting for **Turn On** in that sheet.
    private var pendingNotificationSwitch: PendingNotificationSwitch?

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
    /// Relay notification choices per GitHub account.
    let notificationPreferences: any NotificationPreferencesStoring
    /// Bumped on every saved choice, so the Notifications screen redraws (the store isn't observable).
    private var notificationChoicesRevision = 0
    /// iOS's notification permission for Committed, read when the Notifications screen shows.
    private let notificationAuthorization: @Sendable () async -> UNAuthorizationStatus
    /// Notifications for Committed are off in iOS Settings: the Notifications screen says so.
    private(set) var notificationsDeniedInSettings = false
    private let remoteNotifications: any RemoteNotificationRegistering
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
    /// Where dismissed record cards are remembered (UserDefaults), by GitHub account.
    nonisolated static let dismissedRecordCardsKey = "recordCards.dismissed.v1"

    /// Record cards dismissed on the real board, by GitHub account, newest last (`dismissRecordCard`).
    private var dismissedRecordCards: [String: [String]]
    /// The Sample board's, forgotten when it ends.
    private var sampleDismissedRecordCards: [String: [String]] = [:]

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
        notificationPreferences: any NotificationPreferencesStoring = InMemoryNotificationPreferences(),
        remoteNotifications: any RemoteNotificationRegistering = NoRemoteNotifications(),
        notificationAuthorization: @escaping @Sendable () async -> UNAuthorizationStatus = {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.avatarCache = avatarCache
        self.notificationPreferences = notificationPreferences
        self.remoteNotifications = remoteNotifications
        self.notificationAuthorization = notificationAuthorization
        self.realServices = services
        self.makeSampleServices = sampleServices
        self.defaults = defaults
        self.dismissedRecordCards = defaults?.dictionary(forKey: Self.dismissedRecordCardsKey) as? [String: [String]] ?? [:]
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
        // One source at a time: while the relay delivers notifications, the app posts no passes of
        // its own, and none while relay notifications are on with Passes off.
        services.notifications.isDeliveredByRelay = { [weak self, weak realLiveRank] in
            (realLiveRank?.relayDeliversNotifications ?? false) || (self?.passesOffForTheRelay ?? false)
        }
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
            // Before Live rank tells the relay the board, so a board with Live rank off isn't
            // taken for "both off" before the notification choices are known.
            if let self, let services, self.services === services { await self.syncRelayNotifications() }
            await liveRank.sync()
            if let self, let services, self.services === services { self.publishWidgets() }
        }
        services.onDisconnect = { [weak self, weak services] in
            liveRank.disconnected()
            if let self, let services, self.services === services { self.forgetNotificationSwitchRequest() }
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
        sampleDismissedRecordCards = [:]
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
        forgetNotificationSwitchRequest()
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
        await syncRelayNotifications()
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
        await syncRelayNotifications()
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
        let pending = takeNotificationSwitchRequest()
        await liveRank.acceptRelayDisclosure()
        // The sheet also agreed to relay notifications: with a switch on, they start now.
        if let pending {
            await commit(pending)
        } else {
            await syncRelayNotifications()
        }
        await refreshLiveRankIfStale()
    }

    func declineLiveRankDisclosure() async {
        liveRankDisclosureRequested = false
        forgetNotificationSwitchRequest()
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

    // MARK: - Relay notifications

    /// Relay notifications are on (the "any switch" gate): a connected real board in a relay build,
    /// agreed to in a relay sheet, notifications turned on with iOS's permission, and at least one
    /// kind on (Passes, or any other switch on the Notifications screen). With Passes off the relay
    /// hears `passes: "off"`; only with every kind off does it hear notifications off. Otherwise the
    /// app's own (in-app) crossing notifications carry on as before; the Sample board never uses
    /// the relay.
    var relayNotificationsOn: Bool {
        relayNotificationsAllowed && savedNotificationChoices.anyKindOn
    }

    /// Everything relay notifications need but a kind turned on.
    private var relayNotificationsAllowed: Bool {
        mode == .connected && liveRank.isRelayConfigured && liveRank.relayNotificationsChoice == true
            && notificationsTurnedOn
    }

    /// A notification switch has been turned on with iOS's permission granted: the flag that was
    /// Leaderboard Notifications. In a relay build it stays on while Passes is off, and the
    /// Notifications screen's switches read off until it's on. (It isn't observable on its own;
    /// every change here bumps `notificationChoicesRevision`.)
    private var notificationsTurnedOn: Bool {
        _ = notificationChoicesRevision
        return services.notifications.isEnabled
    }

    /// The real board's relay choices have Passes off: the app posts no passes of its own either.
    private var passesOffForTheRelay: Bool {
        services === realServices && showsRelayNotificationChoices && savedNotificationChoices.passes == .off
    }

    /// "Get notifications with Committed closed?": shown once, unasked, the first time relay
    /// notifications would turn on for someone who hasn't agreed to them (for example after
    /// accepting the earlier relay sheet), and whenever a switch is turned on before agreeing (and
    /// after **Not Now**). Never over the relay sheet, which covers notifications itself.
    var isShowingRelayNotificationsConsent: Bool {
        get {
            guard mode == .connected, !needsConnect, liveRank.isRelayConfigured, !isShowingLiveRankDisclosure,
                  liveRank.relayNotificationsChoice != true else { return false }
            if relayNotificationsConsentRequested { return true }
            return liveRank.relayNotificationsChoice == nil && notificationsTurnedOn && savedNotificationChoices.anyKindOn
        }
        set {
            if !newValue { forgetNotificationSwitchRequest() }
        }
    }

    /// The Passes switch (formerly Leaderboard Notifications). On, it takes the shared step every
    /// switch takes (`setNotificationChoice`). Off, with the relay's choices, it sends
    /// `passes: "off"` and leaves the other kinds on; without them it turns the in-app
    /// notifications off, as it always has.
    func leaderboardNotificationsChanged(_ enabled: Bool) async {
        if enabled {
            await notificationSwitchTurnedOn(isPasses: true) { choices in
                // Back on about the same people (Everyone or Pinned rivals) as before it went off.
                if choices.passes == .off { choices.turnPassesOn() }
            }
            return
        }
        if showsRelayNotificationChoices && notificationsTurnedOn {
            await updateNotificationChoices { $0.passes = .off }
            return
        }
        await services.notifications.setEnabled(false)
        forgetNotificationSwitchRequest()
        notificationChoicesRevision += 1
        await syncRelayNotifications()
    }

    /// The Passes switch as the Notifications screen shows it.
    var passesOn: Bool {
        guard notificationsTurnedOn else { return false }
        return !showsRelayNotificationChoices || savedNotificationChoices.passes != .off
    }

    /// Settings' Notifications row: On while any notification is.
    var notificationsOn: Bool {
        guard notificationsTurnedOn else { return false }
        return !showsRelayNotificationChoices || savedNotificationChoices.anyKindOn
    }

    /// A switch turned on, waiting for the relay notifications sheet.
    private struct PendingNotificationSwitch {
        /// Notifications weren't on yet: the choices become the defaults, with this switch on.
        var isFirst: Bool
        var turnOn: (inout NotificationPreferences) -> Void
    }

    /// A notification switch is being turned on (waiting for iOS's prompt). Switches wait for it.
    private(set) var isTurningOnNotifications = false

    /// The one step every notification switch takes when it's turned on (#130's gate): iOS's
    /// permission prompt the first time, then the relay notifications sheet unless already agreed
    /// to. On success, the first time, the choices become the spec defaults (passes for everyone,
    /// results and records on, delivery summary, quiet hours 10 PM to 8 AM; the Window stays) with
    /// the tapped switch on. Denied permission, **Not Now** or dismissing the sheet leave
    /// everything as it was, except that Passes keeps today's in-app notifications after **Not
    /// Now**.
    private func notificationSwitchTurnedOn(
        isPasses: Bool, _ turnOn: @escaping (inout NotificationPreferences) -> Void
    ) async {
        guard !isTurningOnNotifications else { return }
        isTurningOnNotifications = true
        defer { isTurningOnNotifications = false }
        let pending = PendingNotificationSwitch(isFirst: !notificationsTurnedOn, turnOn: turnOn)
        if pending.isFirst {
            // Passes, as Leaderboard Notifications did, is on at once (in the app) and goes back off
            // if denied. Any other switch only asks: nothing is saved before it's agreed to.
            let granted: Bool
            if isPasses {
                granted = await services.notifications.setEnabled(true)
            } else {
                granted = await services.notifications.requestAuthorization()
            }
            notificationChoicesRevision += 1
            guard granted else {
                await checkNotificationPermission()
                return
            }
        }
        if mode == .connected, liveRank.isRelayConfigured, liveRank.relayNotificationsChoice != true {
            pendingNotificationSwitch = pending
            relayNotificationsConsentRequested = true
            await syncRelayNotifications()
            return
        }
        await commit(pending)
    }

    /// Turns notifications on with this switch, saved for this account, and tells the relay.
    private func commit(_ pending: PendingNotificationSwitch) async {
        services.notifications.markEnabled()
        if mode == .connected, let owner = store.selfCompetitor?.username {
            var choices = notificationPreferences.load(account: owner)
            if pending.isFirst { choices = choices.turnedOnDefaults }
            pending.turnOn(&choices)
            notificationPreferences.save(choices, account: owner)
        }
        notificationChoicesRevision += 1
        await syncRelayNotifications()
    }

    private func takeNotificationSwitchRequest() -> PendingNotificationSwitch? {
        defer { pendingNotificationSwitch = nil }
        relayNotificationsConsentRequested = false
        return pendingNotificationSwitch
    }

    private func forgetNotificationSwitchRequest() {
        relayNotificationsConsentRequested = false
        pendingNotificationSwitch = nil
    }

    /// **Turn On**: relay notifications start, with the switch that asked; Live rank stays as it is.
    func acceptRelayNotifications() async {
        let pending = takeNotificationSwitchRequest()
        liveRank.setRelayNotificationsChoice(true)
        if let pending {
            await commit(pending)
        } else {
            await syncRelayNotifications()
        }
        await liveRank.sync()
    }

    /// **Not Now**: the in-app notifications carry on.
    func declineRelayNotifications() async {
        forgetNotificationSwitchRequest()
        liveRank.setRelayNotificationsChoice(false)
        notificationChoicesRevision += 1
        await syncRelayNotifications()
    }

    /// Tells the relay the notification choices: this account's, or off. Only the real graph's
    /// relay hears; while the board's owner isn't known yet (a cold launch), it waits rather than
    /// say off.
    func syncRelayNotifications() async {
        guard services === realServices else { return }
        guard relayNotificationsAllowed else {
            await realLiveRank.relayNotificationsDidChange(nil)
            return
        }
        guard let owner = store.selfCompetitor?.username else { return }
        let choices = notificationPreferences.load(account: owner)
        guard choices.anyKindOn else {
            await realLiveRank.relayNotificationsDidChange(nil)
            return
        }
        remoteNotifications.register()
        await realLiveRank.relayNotificationsDidChange(RelayNotificationsConfiguration(
            preferences: choices,
            rivals: store.pinnedRivals.map(\.username)
        ))
    }

    // MARK: - Notifications screen

    /// Whether the Notifications screen shows the relay's choices (Everyone or Pinned rivals,
    /// Window, Quiet hours and the sections later tickets add) or only Passes, which then work as
    /// they always have: in the app, while it's open. Only Passes in a build without the relay, on
    /// the Sample board, and after **Not Now** (until Passes is turned off and on, which asks again).
    var showsRelayNotificationChoices: Bool {
        mode == .connected && liveRank.isRelayConfigured && liveRank.relayNotificationsChoice != false
    }

    /// This account's saved choices (defaults until one is saved, and on the Sample board).
    private var savedNotificationChoices: NotificationPreferences {
        _ = notificationChoicesRevision
        guard mode == .connected, let owner = store.selfCompetitor?.username else { return NotificationPreferences() }
        return notificationPreferences.load(account: owner)
    }

    /// This account's notification choices as the Notifications screen shows them: until a switch
    /// has been turned on, every kind reads off.
    var notificationChoices: NotificationPreferences {
        var choices = savedNotificationChoices
        if showsRelayNotificationChoices && !notificationsTurnedOn { choices.turnEveryKindOff() }
        return choices
    }

    /// Changes a notification choice: saved on this iPhone for this GitHub account, and sent to the
    /// relay right away. Nothing is saved on the Sample board or before the board's owner is known.
    func updateNotificationChoices(_ change: (inout NotificationPreferences) -> Void) async {
        guard mode == .connected, let owner = store.selfCompetitor?.username else { return }
        var choices = notificationPreferences.load(account: owner)
        change(&choices)
        notificationPreferences.save(choices, account: owner)
        notificationChoicesRevision += 1
        await syncRelayNotifications()
    }

    /// Every row on the Notifications screen goes through here (`notificationChoice`). A switch
    /// turned on (any `Bool` choice: each is a kind of notification) takes the shared step that
    /// asks for permission and relay consent; anything else is saved and sent right away.
    func setNotificationChoice<Value>(_ keyPath: WritableKeyPath<NotificationPreferences, Value>, _ value: Value) async {
        if let on = value as? Bool, on, let kind = keyPath as? WritableKeyPath<NotificationPreferences, Bool> {
            await notificationSwitchTurnedOn(isPasses: false) { $0[keyPath: kind] = true }
            return
        }
        await updateNotificationChoices { $0[keyPath: keyPath] = value }
    }

    /// Quiet hours' switch. Back on, they're the default 10 PM to 8 AM.
    func setQuietHoursOn(_ on: Bool) async {
        await updateNotificationChoices { $0.quietHours = on ? NotificationPreferences().quietHours : nil }
    }

    /// Rival in someone's person view: pins or unpins them (see `StandingsStore.setPinned`) and
    /// tells the relay the new rivals. False when nothing changed.
    @discardableResult
    func setRivalPinned(_ pinned: Bool, username: String) async -> Bool {
        guard store.setPinned(pinned, username: username) else { return false }
        await syncRelayNotifications()
        return true
    }

    /// Reads iOS's permission, for the Notifications screen's "off in iOS Settings" state.
    func checkNotificationPermission() async {
        notificationsDeniedInSettings = await notificationAuthorization() == .denied
    }

    /// Opens `login`'s person view, as tapping their row on the Board does.
    func showPerson(_ login: String) {
        selectedPerson = login
    }

    // MARK: - Challenge

    /// Someone whose Challenge share should open by itself once their race has loaded: asked for
    /// from outside the person view (a pass notification's Share your race, #137).
    private(set) var requestedChallenge: String?

    /// Challenge for `person`'s view: your 30-day race with them. nil on your own view, until both
    /// your counts have loaded, and on the Sample board, whose people are made up.
    func challenge(for person: PersonSummary) -> Challenge? {
        guard mode == .connected, let you = store.selfCompetitor?.username else { return nil }
        return Challenge(you: you, person: person)
    }

    // MARK: - Face-off

    /// You against `login` over `window` as of now, for Share face-off: nil until both calendars
    /// have loaded, and on your own view.
    func faceOff(with login: String, window: ContributionWindow) -> FaceOff? {
        FaceOff(store: store, friend: login, window: window, asOf: now())
    }

    /// Everyone on your board but you, for Share face-off's "Compare with".
    var faceOffPeople: [String] {
        store.visibleCompetitors.filter { !$0.isSelf }.map(\.username)
    }

    /// Opens `login`'s view on the Board and presents their Challenge share as soon as their race
    /// has loaded, as tapping Challenge would. Nothing opens on the Sample board.
    func requestChallenge(_ login: String) {
        selectedTab = .board
        showPerson(login)
        requestedChallenge = mode == .connected ? login : nil
    }

    /// The Challenge asked for with `requestChallenge`, once, when `person` is the one asked for
    /// and their race has loaded; nil until then.
    func takeRequestedChallenge(for person: PersonSummary) -> Challenge? {
        guard requestedChallenge == person.login, selectedPerson == person.login,
              let challenge = challenge(for: person) else { return nil }
        requestedChallenge = nil
        return challenge
    }

    /// The open person view's content as of now, or nil: nobody chosen, or they've left the board
    /// (hidden, or gone from your people), which closes it.
    var shownPerson: PersonSummary? {
        selectedPerson.flatMap { store.person($0, asOf: now(), calendar: .current) }
    }

    /// Your rivals on the Board, from `ranked` (the selected Window's board), with your weekly
    /// records as of the app's clock, the same date the person view uses.
    func yourRivals(ranked: [Ranking.Entry]) -> [YourRivals.Row] {
        YourRivals.rows(ranked: ranked, store: store, asOf: now())
    }

    // MARK: - Your records

    /// Your records as of now, against the people on the board: nil until your calendar loads.
    var yourRecords: PersonalRecords? {
        store.records(asOf: now())
    }

    /// The Board's record card: a record you broke today that's worth celebrating and that you
    /// haven't dismissed. It goes by itself when the day ends.
    var recordCard: PersonalRecords.Broken? {
        guard let me = store.selfCompetitor?.username else { return nil }
        return yourRecords?.card(dismissed: Set(dismissed(for: me)))
    }

    /// Hides the record card for this record, on this account. Saved on the real board; the Sample
    /// board's are forgotten when it ends.
    func dismissRecordCard(_ record: PersonalRecords.Broken) {
        guard let me = store.selfCompetitor?.username else { return }
        // A card lasts a day, so a few recent ids are all that's ever needed.
        let kept = Array((dismissed(for: me).filter { $0 != record.id } + [record.id]).suffix(12))
        if mode == .sampleBoard {
            sampleDismissedRecordCards[me] = kept
        } else {
            dismissedRecordCards[me] = kept
            defaults?.set(dismissedRecordCards, forKey: Self.dismissedRecordCardsKey)
        }
    }

    private func dismissed(for login: String) -> [String] {
        (mode == .sampleBoard ? sampleDismissedRecordCards : dismissedRecordCards)[login] ?? []
    }

    /// See your records: your own view, on the Board.
    func showYourRecords() {
        guard let me = store.selfCompetitor?.username else { return }
        selectedTab = .board
        showPerson(me)
    }

    /// Hiding or showing someone updates Live rank, the relay's rivals (hiding unpins) and the
    /// widgets right away while the app is open.
    func visibilityDidChange() async {
        // Live rank first: its new board already leaves a hidden rival out of `rivals` (the
        // registrar keeps only rivals on the board), so the notification sync after it sends the
        // same body and the relay hears one write, not two.
        await liveRank.sync()
        await syncRelayNotifications()
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

    /// `committed://board?window=…` opens the Board on that Window; `committed://person/<login>` opens
    /// that person's view on the Board, or just the Board when they're not on it (hidden, or gone);
    /// `committed://challenge/<login>` does the same and presents their Challenge share once their
    /// race loads (a pass notification's Share your race). Returns whether it handled the URL.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        open(link)
        return true
    }

    func open(_ link: DeepLink) {
        switch link {
        case .board(let window):
            selectedTab = .board
            if let window { store.selectedWindow = window }
        case .person(let login):
            selectedTab = .board
            selectedPerson = isOnBoard(login) ? login : nil
        case .challenge(let login):
            guard isOnBoard(login) else { return open(.person(login: login)) }
            requestChallenge(login)
        }
    }

    private func isOnBoard(_ login: String) -> Bool {
        store.visibleCompetitors.contains { $0.username == login }
    }
}
