import Foundation
import Observation

/// Live rank on this iPhone: keeps one Live Activity in step with the board, and, when a
/// Committed relay is configured, keeps the relay's registration in step too (phase 2).
///
/// Every trigger funnels into `sync()`: after each refresh (foreground, timer, and background
/// refresh, via `RefreshCoordinator.afterRefresh`), on becoming active, on a visibility change,
/// on a settings change, on a time-zone change, and on a new push token. `sync()` derives the
/// state, ends strays, updates the kept activity only when its state changed, and starts one
/// when none is showing and the app is in the foreground (iOS refuses to start one from the
/// background). Then it registers what the relay needs, or unregisters when Live rank is off
/// or GitHub is disconnected.
///
/// With a relay, Live rank stays off until the person accepts the disclosure of what the relay
/// receives. Without one, nothing is sent anywhere and Live rank is on unless turned off.
@Observable
@MainActor
final class LiveRankController {
    enum Status: Equatable {
        /// The Live rank switch is off.
        case off
        /// On, but nothing is showing yet: not connected, no board yet, or in the background.
        case waiting
        /// The activity is showing.
        case live
        /// Live Activities are turned off for Committed in iOS Settings.
        case disabledInSystem
        /// iOS refused to start it.
        case failed(String)
    }

    private(set) var isEnabled: Bool
    /// The relay disclosure sheet is up: shown once the board is here when the person hasn't
    /// decided yet, and whenever they turn Live rank on before accepting it.
    private(set) var isPresentingDisclosure = false
    /// Whether a Committed relay keeps Live rank current while the app is closed.
    var usesRelay: Bool { relay != nil }
    private(set) var window: ContributionWindow
    private(set) var status: Status
    /// What Live rank shows (or would show); nil when it's off or there's no board.
    private(set) var latestState: LiveRankState?

    /// Today's movement as the board reports it. Set once the refresh coordinator exists.
    var rankDelta: @MainActor (String) -> Int? = { _ in nil }

    private let store: StandingsStore
    private let activities: any LiveRankActivities
    private let persistence: any LiveRankPersistence
    private let now: @Sendable () -> Date
    private let timeZone: @Sendable () -> TimeZone
    private let relay: LiveRankRelay?
    private var preferences: LiveRankPreferences
    private var offeredDisclosure = false
    /// Whether GitHub is connected. `.unknown` after a launch while the phone was locked (the
    /// token can't be read yet): then nothing is ended or unregistered, because that isn't a
    /// disconnect.
    private enum Connection { case unknown, connected, disconnected }
    private var connection = Connection.unknown
    private var isConnected: Bool { connection == .connected }
    private var isForeground = false
    private var isSyncing = false
    private var syncAgain = false
    private var pending: Task<Void, Never>?

    init(
        store: StandingsStore,
        activities: any LiveRankActivities,
        persistence: any LiveRankPersistence,
        relay: LiveRankRelayDependencies? = nil,
        timeZone: @escaping @Sendable () -> TimeZone = { .autoupdatingCurrent },
        now: @escaping @Sendable () -> Date
    ) {
        self.store = store
        self.activities = activities
        self.persistence = persistence
        self.now = now
        self.timeZone = timeZone
        self.relay = relay.map { LiveRankRelay($0, now: now) }
        let preferences = persistence.loadPreferences()
        self.preferences = preferences
        let enabled = Self.isEnabled(preferences, usesRelay: relay != nil)
        isEnabled = enabled
        window = preferences.window
        status = enabled ? .waiting : .off
        if self.relay != nil {
            activities.observePushTokens { [weak self] token in self?.received(token) }
        }
    }

    /// Without a relay, undecided means on (phase 1). With one, Live rank is on only after the
    /// disclosure was accepted and it was turned on.
    private static func isEnabled(_ preferences: LiveRankPreferences, usesRelay: Bool) -> Bool {
        usesRelay
            ? preferences.isEnabled == true && preferences.relayDisclosureAccepted == true
            : preferences.isEnabled ?? true
    }

    private var needsDisclosure: Bool {
        relay != nil && preferences.relayDisclosureAccepted != true
    }

    /// The Window to keep fresh for Live rank: none when it's off, disconnected, or when iOS
    /// won't show Live Activities, so no fetch is wasted on an activity nobody can see.
    var windowsToRefresh: [ContributionWindow] {
        isEnabled && isConnected && activities.areActivitiesEnabled ? [window] : []
    }

    // MARK: - Settings

    /// The Live rank switch. Turning it on before the relay disclosure was accepted shows the
    /// disclosure instead; Live rank turns on only if it's accepted.
    func setEnabled(_ enabled: Bool) async {
        if enabled, needsDisclosure {
            isPresentingDisclosure = true
            return
        }
        preferences.isEnabled = enabled
        persistence.savePreferences(preferences)
        isEnabled = Self.isEnabled(preferences, usesRelay: relay != nil)
        await sync()
    }

    /// "Turn On Live rank" on the disclosure sheet.
    func acceptDisclosure() async {
        isPresentingDisclosure = false
        preferences.relayDisclosureAccepted = true
        await setEnabled(true)
    }

    /// "Not Now" on the disclosure sheet: Live rank stays off, and the app doesn't ask again on
    /// its own (the switch in Settings still can).
    func declineDisclosure() {
        isPresentingDisclosure = false
        guard !isEnabled else { return }
        preferences.isEnabled = false
        persistence.savePreferences(preferences)
        status = .off
    }

    /// A different Window ends the current activity and starts one for the new Window.
    func setWindow(_ newWindow: ContributionWindow) async {
        guard newWindow != window else { return }
        preferences.window = newWindow
        window = newWindow
        persistence.savePreferences(preferences)
        await sync()
    }

    // MARK: - App lifecycle

    func connected() {
        connection = .connected
    }

    /// Disconnect GitHub: end Live rank now and delete the relay registration.
    /// `AuthModel.signOut` is synchronous, so the ending runs in a task; `idle()` waits for it.
    func disconnected() {
        connection = .disconnected
        scheduleSync()
    }

    /// Launched without a readable token while the phone could read it: really signed out.
    func signedOutAtLaunch() {
        connection = .disconnected
    }

    /// Sync soon, from synchronous code (hide/show, sign-out); `idle()` waits for it.
    func scheduleSync() {
        let previous = pending
        pending = Task {
            await previous?.value
            await sync()
        }
    }

    func enteredForeground() async {
        isForeground = true
        await sync()
    }

    func enteredBackground() {
        isForeground = false
    }

    /// Wait for work started by `scheduleSync()`.
    func idle() async {
        while let task = pending {
            await task.value
            if pending == task { break }
        }
    }

    // MARK: - Relay push tokens

    /// A push token from ActivityKit: remember it, then register or report it. The app may have
    /// been launched in the background for it (a relay-started activity) before first unlock,
    /// when the GitHub token can't be read and the board looks disconnected. Then only the
    /// activity's token is reported, and nothing is ended.
    private func received(_ token: LiveRankPushToken) {
        relay?.record(token)
        guard !isConnected else {
            scheduleSync()
            return
        }
        guard case .activity(let id, _) = token, let relay, let registered = relay.registered,
              activities.current().contains(where: { $0.id == id && $0.selfLogin == registered.login
                  && $0.state.window == registered.window })
        else { return }
        let previous = pending
        pending = Task {
            await previous?.value
            await relay.reportIfRegistered(activityID: id)
        }
    }

    // MARK: - Sync

    /// Bring the Live Activity in line with the board. Calls that arrive while one is running
    /// coalesce into one more pass, so two triggers can never start two activities.
    func sync() async {
        if isSyncing {
            syncAgain = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncAgain = false
            await syncOnce()
        } while syncAgain
    }

    private func syncOnce() async {
        // Launched while locked: leave the activity and the relay alone until we know.
        guard connection != .unknown else { return }
        let running = activities.current()
        guard isEnabled, isConnected else {
            for activity in running { await activities.end(id: activity.id) }
            latestState = nil
            persistence.saveLatestState(nil)
            status = isEnabled ? .waiting : .off
            offerDisclosureIfUndecided()
            await relay?.sync(board: nil, activityID: nil)
            return
        }
        // Connected but your board isn't here yet (first sync): leave any activity as it is.
        guard let me = store.selfCompetitor?.username else {
            status = .waiting
            return
        }
        let keptID = await syncActivity(me: me, running: running)
        await relay?.sync(board: relayBoard(me: me), activityID: keptID)
    }

    /// With a relay and no decision yet, ask once per launch, in the foreground, once your
    /// board is here (so it doesn't cover Connect GitHub).
    private func offerDisclosureIfUndecided() {
        guard relay != nil, preferences.isEnabled == nil, needsDisclosure, isConnected, isForeground,
              store.selfCompetitor != nil, !offeredDisclosure else { return }
        offeredDisclosure = true
        isPresentingDisclosure = true
    }

    private func relayBoard(me: String) -> RelayBoard {
        var competitors = store.visibleCompetitors.map(\.username)
        if competitors.count > RelayRegistration.maxCompetitors {
            competitors = [me] + competitors.filter { $0 != me }.prefix(RelayRegistration.maxCompetitors - 1)
        }
        return RelayBoard(login: me, competitors: competitors, window: window.rawValue,
                          timeZone: timeZone().identifier)
    }

    /// Ends strays, updates or starts the one activity; returns the ID of the one showing.
    private func syncActivity(me: String, running: [LiveRankActivity]) async -> String? {
        let state = LiveRankState(store: store, window: window, rankDelta: rankDelta, now: now())
        latestState = state
        persistence.saveLatestState(state)

        let kept = running.first { $0.selfLogin == me && $0.state.window == state.window }
        for stray in running where stray.id != kept?.id {
            await activities.end(id: stray.id)
        }
        let enabledInSystem = activities.areActivitiesEnabled
        if let kept {
            if kept.state != state { await activities.update(id: kept.id, to: state) }
            status = enabledInSystem ? .live : .disabledInSystem
            return kept.id
        }
        guard enabledInSystem else {
            status = .disabledInSystem
            return nil
        }
        guard isForeground else {
            status = .waiting
            return nil
        }
        do {
            let started = try activities.start(selfLogin: me, state: state)
            status = .live
            return started.id
        } catch {
            status = .failed(error.localizedDescription)
            return nil
        }
    }
}
