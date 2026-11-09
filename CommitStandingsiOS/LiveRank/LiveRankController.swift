import Foundation
import Observation

/// Live rank on this iPhone (phase 1): keeps one Live Activity in step with the board.
///
/// Every trigger funnels into `sync()`: after each refresh (foreground, timer, pull-to-refresh,
/// and background app refresh, through `RefreshCoordinator.didRefresh`), on becoming active, on a
/// visibility change, on Disconnect, and on a settings change. `sync()` derives the state, ends
/// strays, updates the kept activity only when its state changed, and starts one when none is
/// showing and the app is in the foreground (iOS refuses to start one from the background).
/// `sync()` never refreshes; `AppModel` fetches a stale Live rank Window first.
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
        /// Live Activities are off for Committed in iOS Settings.
        case disabledInSystem
        /// iOS refused to start it.
        case failed(String)
    }

    private(set) var isEnabled: Bool
    private(set) var window: ContributionWindow
    private(set) var status: Status

    private let store: StandingsStore
    private let activities: any LiveRankActivities
    private let relay: any LiveRankRegistrar
    private let preferenceStore: any LiveRankPreferenceStoring
    private let isSignedIn: @MainActor () -> Bool
    private let rankDelta: @MainActor (String) -> Int?
    private let now: @Sendable () -> Date
    /// The Sample board's Live rank: its activity tells the extension to show initials only.
    private let isSampleBoard: Bool
    private var preferences: LiveRankPreferences
    private var isForeground = false
    private var isSyncing = false
    private var syncAgain = false
    private var lastConfiguration: LiveRankConfiguration??
    private var pending: Task<Void, Never>?

    init(
        store: StandingsStore,
        activities: any LiveRankActivities,
        relay: any LiveRankRegistrar,
        preferences: any LiveRankPreferenceStoring,
        isSignedIn: @escaping @MainActor () -> Bool,
        rankDelta: @escaping @MainActor (String) -> Int?,
        now: @escaping @Sendable () -> Date,
        isSampleBoard: Bool = false
    ) {
        self.isSampleBoard = isSampleBoard
        self.store = store
        self.activities = activities
        self.relay = relay
        self.preferenceStore = preferences
        self.isSignedIn = isSignedIn
        self.rankDelta = rankDelta
        self.now = now
        let saved = preferences.load()
        self.preferences = saved
        let enabled = Self.isEnabled(saved, relayConfigured: relay.pushUpdates == .token)
        isEnabled = enabled
        window = saved.window
        status = enabled ? .waiting : .off
    }

    /// Phase 1 treats "never chosen" as on. With the relay, Live rank stays off until the person
    /// has accepted the disclosure of what the relay receives.
    private static func isEnabled(_ preferences: LiveRankPreferences, relayConfigured: Bool) -> Bool {
        guard preferences.isEnabled ?? true else { return false }
        return !relayConfigured || preferences.relayDisclosureAccepted
    }

    /// The Committed relay keeps Live rank current with the app closed (phase 2).
    var isRelayConfigured: Bool { relay.pushUpdates == .token }

    /// Turning Live rank on needs the relay disclosure first.
    var requiresRelayDisclosure: Bool {
        isRelayConfigured && !preferences.relayDisclosureAccepted
    }

    /// Offer the disclosure without being asked: the person hasn't chosen yet (first connect), or
    /// turned Live rank on in a build without the relay. Never after they declined.
    var offersRelayDisclosure: Bool {
        requiresRelayDisclosure && preferences.isEnabled != false
    }

    /// The person read what the relay receives and turned Live rank on.
    func acceptRelayDisclosure() async {
        preferences.relayDisclosureAccepted = true
        await setEnabled(true)
    }

    /// "Not Now": Live rank stays off, and the disclosure isn't offered again until the switch is
    /// turned on.
    func declineRelayDisclosure() async {
        await setEnabled(false)
    }

    /// Try again whatever the relay couldn't send earlier.
    func retryRelay() async {
        await relay.retryPendingWork()
    }

    /// The Window to keep fresh for Live rank: none when it's off, disconnected, or when iOS won't
    /// show Live Activities, so no fetch is wasted on an activity nobody can see.
    var windowsToRefresh: [ContributionWindow] {
        isEnabled && isSignedIn() && activities.areActivitiesEnabled ? [window] : []
    }

    // MARK: - Settings

    func setEnabled(_ enabled: Bool) async {
        // With the relay, only the disclosure's "Turn On" can turn it on the first time.
        if enabled && requiresRelayDisclosure { return }
        preferences.isEnabled = enabled
        isEnabled = Self.isEnabled(preferences, relayConfigured: isRelayConfigured)
        preferenceStore.save(preferences)
        await sync()
    }

    /// A different Window ends the current activity and starts one for the new Window.
    func setWindow(_ newWindow: ContributionWindow) async {
        guard newWindow != window else { return }
        preferences.window = newWindow
        window = newWindow
        preferenceStore.save(preferences)
        await sync()
    }

    // MARK: - App lifecycle

    func enteredForeground() async {
        isForeground = true
        await sync()
    }

    func enteredBackground() {
        isForeground = false
    }

    /// Disconnect GitHub: end Live rank now. Sign-out is synchronous, so the ending runs in a
    /// task; `idle()` waits for it.
    func disconnected() {
        pending = Task { await sync() }
    }

    /// Wait for work started by `disconnected()`.
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
        guard isEnabled, isSignedIn() else {
            for activity in running { await activities.end(id: activity.id) }
            await tellRelay(nil)
            status = isEnabled ? .waiting : .off
            return
        }
        // Connected, but your board hasn't loaded yet: leave any activity as it is.
        guard let me = store.selfCompetitor?.username else {
            status = .waiting
            return
        }

        let state = LiveRankState.board(store, window: window, rankDelta: rankDelta, now: now())
        let kept = running.first { $0.selfLogin == me && $0.state.window == state.window }
        for stray in running where stray.id != kept?.id {
            await activities.end(id: stray.id)
        }
        await tellRelay(LiveRankConfiguration(
            selfLogin: me, competitors: store.visibleCompetitors.map(\.username), window: window
        ))

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
        let attributes = LiveRankAttributes(selfLogin: me, isSampleBoard: isSampleBoard ? true : nil)
        do {
            _ = try activities.start(attributes, state: state, pushUpdates: relay.pushUpdates)
            status = .live
        } catch where relay.pushUpdates == .token {
            // iOS refused a push-token activity (for example, no Push Notifications entitlement):
            // fall back to phase 1, updated by the app's own refreshes.
            do {
                _ = try activities.start(attributes, state: state, pushUpdates: .none)
                status = .live
            } catch {
                status = .failed(error.localizedDescription)
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func tellRelay(_ configuration: LiveRankConfiguration?) async {
        guard lastConfiguration != .some(configuration) else { return }
        lastConfiguration = .some(configuration)
        await relay.liveRankDidChange(configuration)
    }
}
