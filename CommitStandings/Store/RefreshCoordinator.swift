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

    /// Per Window that shows movement (Today, This month): each tracked username's placement
    /// change since the start of today (+ moved up, − moved down), for the board's small rank-shift
    /// chevrons. Observable so rows update live.
    private(set) var todaysRankDeltas: [ContributionWindow: [String: Int]] = [:]
    /// Each such Window's ranking captured at the day's first refresh of it — the baseline today's
    /// deltas measure against. Reset when a new calendar day's first refresh lands (which on the
    /// 1st is also This month's reset).
    private var todaysBaselines: [ContributionWindow: (date: Date, ranks: [String: Int])] = [:]

    /// The device's calendar, which decides when a month ends and which day is the 1st.
    private let calendar: Calendar
    /// The last finished month announced, per account, so each is announced once on this device.
    private let announcedMonths: any AnnouncedMonthPersistence
    /// The finished month whose Final standings the person put away (by picking a Window); the
    /// Board opens on the next one again.
    private(set) var dismissedFinalStandings: CalendarMonth?

    init(
        store: StandingsStore,
        client: ContributionsFetching,
        interval: TimeInterval = 300,
        now: @Sendable @escaping () -> Date = { Date() },
        notifier: RankChangeNotifying? = nil,
        calendar: Calendar = .current,
        announcedMonths: any AnnouncedMonthPersistence = InMemoryAnnouncedMonthPersistence(),
        beforeRefresh: @escaping @MainActor (RefreshReason) async -> Void = { _ in }
    ) {
        self.calendar = calendar
        self.announcedMonths = announcedMonths
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
        todaysBaselines = [:]
        todaysRankDeltas = [:]
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
        let histories = await fetch(usernames, window: window, reference: reference)
        guard !Task.isCancelled, generation == requestGeneration else { return }

        if baselineVisibilityRevision != store.visibilityRevision {
            previousRanking = [:]
            todaysBaselines = [:]
            todaysRankDeltas = [:]
            baselineVisibilityRevision = store.visibilityRevision
        }
        notifyPositionChanges(window: window, reference: reference)
        announceMonthFinal(window: window, reference: reference)
        updateTodaysRankDeltas(window: window, reference: reference)

        for extra in extras {
            // Every Window comes from the same page: work it out from the days just fetched, and
            // fetch only for anyone whose page didn't carry them.
            for username in usernames {
                guard let history = histories[username] else { continue }
                applyDerived(history, username: username, window: extra, reference: reference)
            }
            let missing = usernames.filter { histories[$0] == nil }
            if !missing.isEmpty {
                await fetch(missing, window: extra, reference: reference)
            }
            guard !Task.isCancelled, generation == requestGeneration else { return }
            updateTodaysRankDeltas(window: extra, reference: reference)
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
    /// numbers on failure. Results that arrive after a sign-out are dropped. Returns the daily
    /// counts that came back, which the store also keeps (once for the whole batch).
    @discardableResult
    private func fetch(_ usernames: [String], window: ContributionWindow, reference: Date) async
        -> [String: ContributionHistory] {
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

        guard !Task.isCancelled, generation == requestGeneration else { return [:] }
        var histories: [String: ContributionHistory] = [:]
        for (username, result) in results {
            if case .success(let counts) = result, let history = counts.history {
                histories[username] = history
            }
            applyResult(
                result,
                username: username,
                window: window,
                reference: reference,
                prior: priorStandings[username]
            )
        }
        store.updateHistories(histories)
        return histories
    }

    /// `window`'s count worked out from days already fetched in this refresh: no page needed.
    private func applyDerived(_ history: ContributionHistory, username: String, window: ContributionWindow, reference: Date) {
        applyResult(
            .success(StandingCounts(contributions: history.total(for: window, asOf: reference), history: history)),
            username: username,
            window: window,
            reference: reference,
            prior: nil
        )
    }

    /// Anyone's placement change on `window` since the start of today, or nil when the position
    /// held, there's nothing to show, or `window` doesn't show movement. Drives the rank-shift
    /// chevrons on Today and This month.
    func rankDelta(for username: String, in window: ContributionWindow = .daily) -> Int? {
        guard window.showsTodaysMovement, baselineVisibilityRevision == store.visibilityRevision,
              !store.isHidden(username) else { return nil }
        let delta = todaysRankDeltas[window]?[username] ?? 0
        return delta == 0 ? nil : delta
    }

    /// After refreshing a Window that shows movement, recompute each competitor's movement on it
    /// vs that Window's start-of-day baseline. The first refresh of a new day (re)sets the baseline
    /// and reports no movement yet.
    private func updateTodaysRankDeltas(window: ContributionWindow, reference: Date) {
        guard window.showsTodaysMovement else { return }
        let ordered = Ranking.order(
            competitors: store.visibleCompetitors,
            standings: store.standings(for: window),
            window: window
        )
        // Only rank rows that actually have data; a never-loaded row shouldn't generate movement.
        var currentRanks: [String: Int] = [:]
        for entry in ordered {
            if let standing = store.standing(for: entry.competitor.username, window: window),
               standing.lastUpdated != .distantPast {
                currentRanks[entry.competitor.username] = entry.rank
            }
        }
        // New day (or first capture this session): re-baseline, no movement yet.
        guard let baseline = todaysBaselines[window],
              Calendar.current.isDate(baseline.date, inSameDayAs: reference) else {
            todaysBaselines[window] = (reference, currentRanks)
            todaysRankDeltas[window] = [:]
            return
        }
        var deltas: [String: Int] = [:]
        for (username, rank) in currentRanks {
            if let start = baseline.ranks[username] {
                deltas[username] = start - rank   // + = climbed (lower rank number)
            }
        }
        todaysRankDeltas[window] = deltas
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
        // (yesterday for .daily, last week/month for .weekly/.monthly/.month) is comparing pre-reset
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

    // MARK: - Final standings

    /// Last month's Final standings, offered on the Board all day on the 1st (in the device's
    /// calendar) so the result isn't hidden behind an empty new month. nil on other days, or when
    /// your saved calendar doesn't cover last month.
    var offeredFinalStandings: FinalStandings? {
        let today = now()
        guard calendar.component(.day, from: today) == 1 else { return nil }
        return store.finalStandings(for: CalendarMonth(containing: today, in: calendar).previous)
    }

    /// Whether the Board shows the offered Final standings instead of the live board: it opens on
    /// them each 1st, until a Window is picked or they're switched off.
    var showsFinalStandings: Bool {
        guard let month = offeredFinalStandings?.month else { return false }
        return dismissedFinalStandings != month
    }

    /// The Final standings switch; picking a Window passes false.
    func showFinalStandings(_ show: Bool) {
        if show {
            dismissedFinalStandings = nil
        } else if let month = offeredFinalStandings?.month {
            dismissedFinalStandings = month
        }
    }

    /// The month-final Leaderboard Notification ("October final" / "You finished #2 of 8"), on the
    /// first successful refresh after a month ends, once per month per account on this device. The
    /// month counts as announced even when notifications are off (only posting needs them on), so
    /// switching them on later doesn't bring up old news; an account never announced anything
    /// starts quietly, its first successful refresh recording last month without a notice. It waits while
    /// anyone with a saved calendar failed this refresh, so it never reports a place from stale
    /// numbers. The Windows core's `month_final` follows the same rules.
    private func announceMonthFinal(window: ContributionWindow, reference: Date) {
        guard let owner = store.selfCompetitor?.username else { return }
        let month = CalendarMonth(containing: reference, in: calendar).previous
        var announced = announcedMonths.load()
        guard let last = announced[owner].flatMap(CalendarMonth.init(key:)) else {
            // Once your own calendar has loaded: the first successful refresh.
            guard store.history(for: owner) != nil else { return }
            announced[owner] = month.key
            announcedMonths.save(announced)
            return
        }
        if last >= month { return }
        let stale = store.visibleCompetitors.contains { person in
            guard store.history(for: person.username) != nil,
                  case .failed = store.standing(for: person.username, window: window)?.state else { return false }
            return true
        }
        guard !stale, let finals = store.finalStandings(for: month), let result = finals.result else { return }
        announced[owner] = month.key
        announcedMonths.save(announced)
        notifier?.postMonthFinal(id: "monthfinal.\(month.key)", title: result.title, body: result.body)
    }

    /// Whether two dates fall in the same reset period for `window` — so a snapshot taken in one
    /// period isn't diffed against counts that reset at the boundary.
    private static func sameResetPeriod(_ window: ContributionWindow, _ a: Date, _ b: Date) -> Bool {
        let calendar = Calendar.current
        switch window {
        case .daily: return calendar.isDate(a, inSameDayAs: b)
        case .weekly: return calendar.isDate(a, equalTo: b, toGranularity: .weekOfYear)
        case .monthly, .month: return calendar.isDate(a, equalTo: b, toGranularity: .month)
        }
    }

    /// `username`'s current streak from the days their last successful page brought back (saved
    /// across relaunches), as of now; nil before any page has. A row shows it only beside a loaded
    /// count (`StandingRow.streakText`), and only from 2 days.
    func streak(for username: String) -> Int? {
        store.history(for: username)?.currentStreak(asOf: now())
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
        var fetched: ContributionHistory?
        for window in windows {
            // One page: later Windows come from the days the first one brought back.
            if let fetched {
                applyDerived(fetched, username: username, window: window, reference: reference)
                continue
            }
            let prior = store.standing(for: username, window: window)
            store.markLoading(username: username, window: window)
            let result = await client.standingCounts(for: username, window: window, asOf: reference)
            guard !Task.isCancelled, generation == requestGeneration, !store.isHidden(username) else { return }
            applyResult(result, username: username, window: window, reference: reference, prior: prior)
            if case .success(let counts) = result, let history = counts.history {
                fetched = history
                store.updateHistories([username: history])
            }
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
