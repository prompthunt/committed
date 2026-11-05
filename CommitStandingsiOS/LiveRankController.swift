import Foundation
import Observation

/// Live rank on this iPhone (phase 1): keeps one Live Activity in step with the board.
///
/// Every trigger funnels into `sync()`: after each refresh (foreground, timer, and background
/// refresh, via `RefreshCoordinator.afterRefresh`), on becoming active, on a visibility change,
/// and on a settings change. `sync()` derives the state, ends strays, updates the kept activity
/// only when its state changed, and starts one when none is showing and the app is in the
/// foreground (iOS refuses to start one from the background).
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
    private var preferences: LiveRankPreferences
    private var isConnected = false
    private var isForeground = false
    private var isSyncing = false
    private var syncAgain = false
    private var pending: Task<Void, Never>?

    init(
        store: StandingsStore,
        activities: any LiveRankActivities,
        persistence: any LiveRankPersistence,
        now: @escaping @Sendable () -> Date
    ) {
        self.store = store
        self.activities = activities
        self.persistence = persistence
        self.now = now
        let preferences = persistence.loadPreferences()
        self.preferences = preferences
        isEnabled = preferences.isEnabled ?? true
        window = preferences.window
        status = (preferences.isEnabled ?? true) ? .waiting : .off
    }

    /// The Window to keep fresh for Live rank: none when it's off, disconnected, or when iOS
    /// won't show Live Activities, so no fetch is wasted on an activity nobody can see.
    var windowsToRefresh: [ContributionWindow] {
        isEnabled && isConnected && activities.areActivitiesEnabled ? [window] : []
    }

    // MARK: - Settings

    func setEnabled(_ enabled: Bool) async {
        preferences.isEnabled = enabled
        isEnabled = enabled
        persistence.savePreferences(preferences)
        await sync()
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
        isConnected = true
    }

    /// Disconnect GitHub: end Live rank now. `AuthModel.signOut` is synchronous, so the ending
    /// runs in a task; `idle()` waits for it.
    func disconnected() {
        isConnected = false
        scheduleSync()
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
        await pending?.value
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
        let running = activities.current()
        guard isEnabled, isConnected else {
            for activity in running { await activities.end(id: activity.id) }
            latestState = nil
            persistence.saveLatestState(nil)
            status = isEnabled ? .waiting : .off
            return
        }
        // Connected but your board isn't here yet (first sync): leave any activity as it is.
        guard let me = store.selfCompetitor?.username else {
            status = .waiting
            return
        }

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
            return
        }
        guard enabledInSystem else {
            status = .disabledInSystem
            return
        }
        guard isForeground else {
            status = .waiting
            return
        }
        do {
            _ = try activities.start(selfLogin: me, state: state)
            status = .live
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
