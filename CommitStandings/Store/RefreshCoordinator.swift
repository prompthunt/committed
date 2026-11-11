import Foundation
import Observation

enum RefreshReason: String {
    case menuOpened
    case timer
    case manual
    case windowChanged
    case competitorAdded
    case competitorRenamed
    case visibilityChanged
    /// iPhone: the app became active (foreground) with stale data.
    case becameActive
    /// iPhone: a background app refresh (`BGAppRefreshTask`).
    case background
}

@Observable
@MainActor
final class RefreshCoordinator {
    private(set) var isRefreshing: Bool = false
    private(set) var lastReason: RefreshReason?

    /// How old a count can be before a refresh fetches it again: opening the menu, switching
    /// Window, or keeping another Window fresh all skip data newer than this.
    static let staleAfter: TimeInterval = 120

    /// Opening the menu should only refresh if the data is actually stale. Otherwise
    /// every open flashed "updating…" with nothing changing. The background timer keeps
    /// things current while the menu is closed; this just catches up after a longer gap.
    var shouldRefreshOnOpen: Bool {
        guard let last = store.lastUpdated else { return true }
        return now().timeIntervalSince(last) > Self.staleAfter
    }

    /// Whether switching to `window` needs a network refresh: only if a tracked
    /// competitor is missing recent data for it. Switching back to a window we already
    /// loaded just shows the cached numbers instead of flashing "updating…" every time.
    func needsRefresh(for window: ContributionWindow) -> Bool {
        let usernames = store.visibleCompetitors.map(\.username)
        guard !usernames.isEmpty else { return false }
        let now = now()
        return usernames.contains { username in
            guard let standing = store.standing(for: username, window: window) else { return true }
            return standing.lastUpdated == .distantPast || now.timeIntervalSince(standing.lastUpdated) > Self.staleAfter
        }
    }

    private let beforeRefresh: @MainActor (RefreshReason) async -> Void
    /// Windows to keep fresh alongside the board's (iPhone: Live rank's Window, which can differ
    /// from the one on screen). Each is fetched in the same refresh when `needsRefresh(for:)`.
    /// Counts and today's movement only: crossing notifications follow the board's Window.
    /// The Mac leaves this empty.
    var additionalWindows: @MainActor () -> [ContributionWindow] = { [] }
    /// Runs after every completed `refreshAll` and `refreshOne`, once the new counts are in the
    /// store. iPhone updates Live rank here; the Mac leaves it empty.
    var didRefresh: @MainActor (RefreshReason) async -> Void = { _ in }
    private let store: StandingsStore
    private let client: ContributionsFetching
    private let interval: TimeInterval
    private let now: @Sendable () -> Date
    private var generation = UUID()
    private var baselineVisibilityRevision = 0
    private var timerTask: Task<Void, Never>?
    /// Optional sink for relative-rank crossings, fired after each refresh. Default nil (no
    /// notifications) keeps existing call sites and tests unaffected.
    private let notifier: RankChangeNotifying?
    /// Per-window in-memory snapshot of the last ranking (its reference date + username →
    /// contributions), used to detect crossings. Not persisted, so the first refresh after launch
    /// never notifies. The date lets us re-baseline across a window's reset boundary (e.g. the
    /// daily count zeroing at midnight) instead of reporting the reset as a flurry of crossings.
    private var previousRanking: [ContributionWindow: (date: Date, counts: [String: Int])] = [:]

    /// Each tracked username's placement change since the start of today (+ moved up, − moved
    /// down), for the Today board's small rank-shift chevrons. Observable so rows update live.
    private(set) var dailyRankDeltas: [String: Int] = [:]
    /// The daily ranking captured at the day's first refresh — the baseline today's deltas measure
    /// against. Reset when a new calendar day's first refresh lands.
    private var dailyBaselineRanks: [String: Int] = [:]
    private var dailyBaselineDate: Date?

    init(
        store: StandingsStore,
        client: ContributionsFetching,
        interval: TimeInterval = 300,
        now: @Sendable @escaping () -> Date = { Date() },
        notifier: RankChangeNotifying? = nil,
        beforeRefresh: @escaping @MainActor (RefreshReason) async -> Void = { _ in }
    ) {
        self.beforeRefresh = beforeRefresh
        self.store = store
        self.client = client
        self.interval = interval
        self.now = now
        self.notifier = notifier
        startTimer()
    }

    /// Prevent a signed-out account's in-flight counts or notification baselines leaking
    /// into a later account, even when it shares some of the same people.
    func invalidate() {
        generation = UUID()
        isRefreshing = false
        previousRanking = [:]
        dailyBaselineRanks = [:]
        dailyBaselineDate = nil
        dailyRankDeltas = [:]
    }

    func refreshAll(reason: RefreshReason) async {
        if isRefreshing { return }
        isRefreshing = true
        let requestGeneration = generation
        defer { if generation == requestGeneration { isRefreshing = false } }
        await beforeRefresh(reason)
        guard !Task.isCancelled, generation == requestGeneration else { return }
        let usernames = store.visibleCompetitors.map(\.username)
        guard !usernames.isEmpty else { return }
        let window = store.selectedWindow
        lastReason = reason
        let reference = now()
        let extras = staleAdditionalWindows(excluding: window)
        await fetch(usernames, window: window, reference: reference)
        guard !Task.isCancelled, generation == requestGeneration else { return }

        if baselineVisibilityRevision != store.visibilityRevision {
            previousRanking = [:]
            dailyBaselineRanks = [:]
            dailyBaselineDate = nil
            dailyRankDeltas = [:]
            baselineVisibilityRevision = store.visibilityRevision
        }
        notifyPositionChanges(window: window, reference: reference)
        updateDailyRankDeltas(window: window, reference: reference)

        for extra in extras {
            await fetch(usernames, window: extra, reference: reference)
            guard !Task.isCancelled, generation == requestGeneration else { return }
            updateDailyRankDeltas(window: extra, reference: reference)
        }
        store.markRefreshComplete(at: reference)
        await didRefresh(reason)
    }

    /// The additional Windows other than `window` that have missing or old counts.
    private func staleAdditionalWindows(excluding window: ContributionWindow) -> [ContributionWindow] {
        var windows: [ContributionWindow] = []
        for extra in additionalWindows() where extra != window && !windows.contains(extra) && needsRefresh(for: extra) {
            windows.append(extra)
        }
        return windows
    }

    /// Fetch `window`'s counts for `usernames` (six at a time) and apply them, keeping prior good
    /// numbers on failure. Results that arrive after a sign-out are dropped.
    private func fetch(_ usernames: [String], window: ContributionWindow, reference: Date) async {
        let requestGeneration = generation
        // Snapshot prior good standings *before* markLoading flips state to
        // .loading. Without this, a competitor whose last successful counts were
        // legitimate zeroes (state == .loaded) would be
        // indistinguishable from "never fetched" after markLoading, and the
        // failure branch would overwrite its lastUpdated.
        var priorStandings: [String: Standing] = [:]
        for username in usernames {
            priorStandings[username] = store.standing(for: username, window: window)
        }
        for username in usernames {
            store.markLoading(username: username, window: window)
        }
        let client = self.client

        let results = await withTaskGroup(of: (String, Result<StandingCounts, ContributionsError>).self) { group in
            var pending = usernames.makeIterator()
            for username in usernames.prefix(6) {
                _ = pending.next()
                group.addTask {
                    let result = await client.standingCounts(for: username, window: window, asOf: reference)
                    return (username, result)
                }
            }
            var collected: [(String, Result<StandingCounts, ContributionsError>)] = []
            for await item in group {
                collected.append(item)
                if let username = pending.next(), !Task.isCancelled {
                    group.addTask {
                        (username, await client.standingCounts(for: username, window: window, asOf: reference))
                    }
                }
            }
            return collected
        }

        guard !Task.isCancelled, generation == requestGeneration else { return }
        for (username, result) in results {
            applyResult(
                result,
                username: username,
                window: window,
                reference: reference,
                prior: priorStandings[username]
            )
        }
    }

    /// The signed-in user (or anyone's) placement change since the start of today, or nil when the
    /// position held / there's nothing to show. Drives the Today board's rank-shift chevrons.
    func rankDelta(for username: String) -> Int? {
        guard baselineVisibilityRevision == store.visibilityRevision, !store.isHidden(username) else { return nil }
        let delta = dailyRankDeltas[username] ?? 0
        return delta == 0 ? nil : delta
    }

    /// After a Today-window refresh, recompute each competitor's movement vs the start-of-day
    /// baseline. The first refresh of a new day (re)sets the baseline and reports no movement yet.
    private func updateDailyRankDeltas(window: ContributionWindow, reference: Date) {
        guard window == .daily else { return }
        let ordered = Ranking.order(
            competitors: store.visibleCompetitors,
            standings: store.standings(for: .daily),
            window: .daily
        )
        // Only rank rows that actually have data; a never-loaded row shouldn't generate movement.
        var currentRanks: [String: Int] = [:]
        for entry in ordered {
            if let standing = store.standing(for: entry.competitor.username, window: .daily),
               standing.lastUpdated != .distantPast {
                currentRanks[entry.competitor.username] = entry.rank
            }
        }
        // New day (or first capture this session): re-baseline, no movement yet.
        if dailyBaselineDate == nil || !Calendar.current.isDate(dailyBaselineDate!, inSameDayAs: reference) {
            dailyBaselineRanks = currentRanks
            dailyBaselineDate = reference
            dailyRankDeltas = [:]
            return
        }
        var deltas: [String: Int] = [:]
        for (username, rank) in currentRanks {
            if let baseline = dailyBaselineRanks[username] {
                deltas[username] = baseline - rank   // + = climbed (lower rank number)
            }
        }
        dailyRankDeltas = deltas
    }

    /// After a full refresh, diff the just-updated window's ranking against the prior in-memory
    /// snapshot and fire notifications for any rival that crossed the signed-in user. Stores the
    /// new snapshot for next time. No-op without a notifier or a known self.
    private func notifyPositionChanges(window: ContributionWindow, reference: Date) {
        guard let notifier, let selfUsername = store.selfCompetitor?.username else { return }
        var current: [String: Int] = [:]
        for competitor in store.visibleCompetitors {
            if let standing = store.standing(for: competitor.username, window: window),
               standing.lastUpdated != .distantPast {
                current[competitor.username] = standing.contributions
            }
        }
        // Re-baseline across the window's reset boundary: a prior snapshot from an earlier period
        // (yesterday for .daily, last week/month for .weekly/.monthly) is comparing pre-reset
        // counts to post-reset ones, which would report the reset itself as crossings. Treat it
        // as a first snapshot instead.
        let prior = previousRanking[window]
        let previousCounts = prior.flatMap {
            Self.sameResetPeriod(window, $0.date, reference) ? $0.counts : nil
        }
        let events = RankChangeDetector.crossings(
            previous: previousCounts,
            current: current,
            selfUsername: selfUsername
        )
        if !events.isEmpty { notifier.post(events) }
        // Only re-baseline when self is present this cycle; otherwise keep the last good snapshot
        // so a transient self-fetch failure doesn't drop self and swallow the next real crossing.
        if current[selfUsername] != nil {
            previousRanking[window] = (reference, current)
        }
    }

    /// Whether two dates fall in the same reset period for `window` — so a snapshot taken in one
    /// period isn't diffed against counts that reset at the boundary.
    private static func sameResetPeriod(_ window: ContributionWindow, _ a: Date, _ b: Date) -> Bool {
        let calendar = Calendar.current
        switch window {
        case .daily: return calendar.isDate(a, inSameDayAs: b)
        case .weekly: return calendar.isDate(a, equalTo: b, toGranularity: .weekOfYear)
        case .monthly: return calendar.isDate(a, equalTo: b, toGranularity: .month)
        }
    }

    func refreshOne(username: String, reason: RefreshReason) async {
        guard store.visibleCompetitors.contains(where: { $0.username == username }) else { return }
        let requestGeneration = generation
        let window = store.selectedWindow
        // Live rank's Window too, when this person has no recent count for it.
        let windows = [window] + staleAdditionalWindows(excluding: window).filter { extra in
            store.standing(for: username, window: extra).map {
                $0.lastUpdated == .distantPast || now().timeIntervalSince($0.lastUpdated) > Self.staleAfter
            } ?? true
        }
        let reference = now()
        for window in windows {
            let prior = store.standing(for: username, window: window)
            store.markLoading(username: username, window: window)
            let result = await client.standingCounts(for: username, window: window, asOf: reference)
            guard !Task.isCancelled, generation == requestGeneration, !store.isHidden(username) else { return }
            applyResult(result, username: username, window: window, reference: reference, prior: prior)
        }
        lastReason = reason
        await didRefresh(reason)
    }

    /// Single failure-handling policy shared by `refreshAll` and `refreshOne`:
    /// on success, write the new counts; on failure, preserve any prior loaded
    /// counts and `lastUpdated` so the UI shows stale data with a `.failed`
    /// badge rather than blanking the row.
    private func applyResult(
        _ result: Result<StandingCounts, ContributionsError>,
        username: String,
        window: ContributionWindow,
        reference: Date,
        prior: Standing?
    ) {
        switch result {
        case .success(let counts):
            store.updateStanding(Standing(
                username: username,
                contributions: counts.contributions,
                window: window,
                lastUpdated: reference,
                state: .loaded,
                burst: counts.burst
            ))
        case .failure(let error):
            if let prior, prior.window == window, case .loaded = prior.state {
                // Preserve the prior good count + timestamp; flag it stale rather than blank.
                store.updateStanding(Standing(
                    username: username,
                    contributions: prior.contributions,
                    window: window,
                    lastUpdated: prior.lastUpdated,
                    state: .failed(message(for: error)),
                    burst: prior.burst
                ))
            } else {
                store.updateStanding(Standing(
                    username: username,
                    contributions: 0,
                    window: window,
                    lastUpdated: .distantPast,
                    state: .failed(message(for: error))
                ))
            }
        }
    }

    /// Whether the periodic refresh timer is scheduled. The Mac never pauses it; iPhone pauses it
    /// while the app is in the background and resumes it on becoming active.
    var isTimerRunning: Bool { timerTask != nil }

    /// Stop the periodic refresh (iPhone: entering the background).
    func pauseTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Restart the periodic refresh if it's paused (iPhone: becoming active). The next timer
    /// refresh comes one full interval later; becoming active refreshes separately when stale.
    func resumeTimer() {
        guard timerTask == nil else { return }
        startTimer()
    }

    private func startTimer() {
        timerTask?.cancel()
        let interval = self.interval
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                await self?.refreshAll(reason: .timer)
            }
        }
    }

    private func message(for error: ContributionsError) -> String {
        switch error {
        case .userNotFound: return "Not found"
        case .network(let m): return m
        case .parseFailed(let m): return "Parse failed: \(m)"
        }
    }
}
