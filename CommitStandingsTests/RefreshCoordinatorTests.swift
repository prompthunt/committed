import Testing
import Foundation
@testable import CommitStandings

actor StubFetcher: ContributionsFetching {
    var responses: [String: Result<StandingCounts, ContributionsError>] = [:]
    var callCount: [String: Int] = [:]
    var delayNanos: UInt64 = 0

    init(responses: [String: Result<StandingCounts, ContributionsError>] = [:], delayNanos: UInt64 = 0) {
        self.responses = responses
        self.delayNanos = delayNanos
    }

    func setResponse(_ result: Result<StandingCounts, ContributionsError>, for username: String) {
        responses[username] = result
    }

    func setSuccess(contributions: Int, for username: String) {
        responses[username] = .success(StandingCounts(contributions: contributions))
    }

    func calls(for username: String) -> Int { callCount[username] ?? 0 }

    func standingCounts(
        for username: String,
        window: ContributionWindow,
        asOf reference: Date
    ) async -> Result<StandingCounts, ContributionsError> {
        callCount[username, default: 0] += 1
        if delayNanos > 0 {
            try? await Task.sleep(nanoseconds: delayNanos)
        }
        return responses[username] ?? .failure(.network("no stub"))
    }
}

/// Captures the events the coordinator would notify on, so the snapshot/diff wiring is testable
/// without the real UNUserNotificationCenter.
@MainActor
final class SpyNotifier: RankChangeNotifying {
    var posted: [[RankChangeEvent]] = []
    var allEvents: [RankChangeEvent] { posted.flatMap { $0 } }
    func post(_ events: [RankChangeEvent]) { posted.append(events) }
    func postMonthFinal(id: String, title: String, body: String) -> Bool { true }
}

/// A mutable clock so a single coordinator can be driven across a day boundary in one test.
final class MutableClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor
struct RefreshCoordinatorTests {

    @Test func hiddenPeopleAreNotFetchedOrConsideredStale() async {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: ["hidden-person", "friend"])
        store.setHidden(true, username: "hidden-person")
        let client = StubFetcher()
        await client.setSuccess(contributions: 3, for: "me")
        await client.setSuccess(contributions: 7, for: "friend")
        let refresh = RefreshCoordinator(store: store, client: client, interval: 99999)
        await refresh.refreshAll(reason: .manual)
        #expect(await client.calls(for: "hidden-person") == 0)
        #expect(await client.calls(for: "friend") == 1)
        #expect(!refresh.needsRefresh(for: .daily))
        await refresh.refreshOne(username: "hidden-person", reason: .visibilityChanged)
        #expect(await client.calls(for: "hidden-person") == 0)
        store.setHidden(false, username: "hidden-person")
        #expect(refresh.needsRefresh(for: .daily))
        await client.setSuccess(contributions: 9, for: "hidden-person")
        await refresh.refreshOne(username: "hidden-person", reason: .visibilityChanged)
        #expect(await client.calls(for: "hidden-person") == 1)
        #expect(store.standing(for: "hidden-person", window: .daily)?.contributions == 9)
    }

    @Test func visibilityChangesDoNotGenerateCrossingNotificationsOrRankMovement() async {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: ["contractor", "friend"])
        let client = StubFetcher()
        let spy = SpyNotifier()
        let refresh = RefreshCoordinator(store: store, client: client, interval: 99999, notifier: spy)
        await client.setSuccess(contributions: 5, for: "me")
        await client.setSuccess(contributions: 3, for: "contractor")
        await client.setSuccess(contributions: 2, for: "friend")
        await refresh.refreshAll(reason: .manual)
        store.setHidden(true, username: "contractor")
        await client.setSuccess(contributions: 10, for: "contractor")
        await refresh.refreshAll(reason: .timer)
        #expect(spy.allEvents.isEmpty)
        #expect(refresh.rankDelta(for: "me") == nil)
        // Reappearing after hidden activity must establish a fresh baseline, even if
        // hide/show both happened between full refreshes.
        store.setHidden(false, username: "contractor")
        await refresh.refreshAll(reason: .timer)
        #expect(spy.allEvents.isEmpty)
        #expect(refresh.rankDelta(for: "me") == nil)
        store.setHidden(true, username: "contractor")
        store.setHidden(false, username: "contractor")
        await client.setSuccess(contributions: 1, for: "contractor")
        await refresh.refreshAll(reason: .timer)
        #expect(spy.allEvents.isEmpty)
    }

    @Test func refreshAllLoadsAutomaticPeopleBeforeFetchingCounts() async {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        let client = StubFetcher()
        await client.setSuccess(contributions: 12, for: "octocat")
        await client.setSuccess(contributions: 6, for: "hubot")
        let refresh = RefreshCoordinator(store: store, client: client, interval: 99999, beforeRefresh: { _ in
            store.replaceRoster(owner: "octocat", members: ["hubot"])
        })
        await refresh.refreshAll(reason: .manual)
        #expect(store.standing(for: "octocat", window: .daily)?.contributions == 12)
        #expect(store.standing(for: "hubot", window: .daily)?.contributions == 6)
    }

    @Test func largeAutomaticRosterFetchesEveryPersonWithBoundedConcurrency() async {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "octocat", members: (1...105).map { "person-\($0)" })
        let client = ConcurrencyCountingFetcher()
        let refresh = RefreshCoordinator(store: store, client: client, interval: 99999)
        await refresh.refreshAll(reason: .manual)
        #expect(await client.peak <= 6)
        #expect(await client.total == 106)
        #expect(store.standings(for: .daily).count == 106)
        #expect(store.standing(for: "person-105", window: .daily)?.contributions == 1)
    }

    @Test func invalidatedRefreshCannotWriteIntoNewAccount() async {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "old-user", members: ["shared-friend"])
        let client = StubFetcher(delayNanos: 60_000_000)
        await client.setSuccess(contributions: 100, for: "shared-friend")
        let refresh = RefreshCoordinator(store: store, client: client, interval: 99999)
        let task = Task { await refresh.refreshAll(reason: .manual) }
        while await client.calls(for: "shared-friend") == 0 { await Task.yield() }
        refresh.invalidate()
        store.reset()
        store.replaceRoster(owner: "new-user", members: ["shared-friend"])
        await task.value
        #expect(store.standings.isEmpty)
        #expect(store.lastUpdated == nil)
    }

    @Test func refreshAll_populatesStandingForEveryCompetitor() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        _ = try store.addRival(username: "octocat")
        let fetcher = StubFetcher()
        await fetcher.setSuccess(contributions: 12, for: "addisonk")
        await fetcher.setSuccess(contributions: 5, for: "octocat")
        let coord = RefreshCoordinator(store: store, client: fetcher, interval: 9_999, now: { Date(timeIntervalSince1970: 1_000) })
        await coord.refreshAll(reason: .manual)
        #expect(store.standing(for: "addisonk", window: .daily)?.contributions == 12)
        #expect(store.standing(for: "addisonk", window: .daily)?.window == .daily)
        #expect(store.standing(for: "octocat", window: .daily)?.contributions == 5)
        #expect(store.lastUpdated == Date(timeIntervalSince1970: 1_000))
    }

    @Test func oneFailure_leavesOthersIntact_andKeepsCachedValue() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        _ = try store.addRival(username: "octocat")
        let fetcher = StubFetcher()
        await fetcher.setSuccess(contributions: 8, for: "addisonk")
        await fetcher.setSuccess(contributions: 3, for: "octocat")
        let coord = RefreshCoordinator(store: store, client: fetcher, interval: 9_999)
        await coord.refreshAll(reason: .manual)
        #expect(store.standing(for: "octocat", window: .daily)?.contributions == 3)

        await fetcher.setResponse(.failure(.network("boom")), for: "octocat")
        await fetcher.setSuccess(contributions: 9, for: "addisonk")
        await coord.refreshAll(reason: .timer)
        #expect(store.standing(for: "addisonk", window: .daily)?.contributions == 9)
        #expect(store.standing(for: "octocat", window: .daily)?.contributions == 3, "cached contributions preserved on transient failure")
        if case .failed = store.standing(for: "octocat", window: .daily)?.state {
            // expected
        } else {
            Issue.record("expected failed state")
        }
    }

    @Test func overlappingRefresh_isSkipped() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        let fetcher = StubFetcher(delayNanos: 50_000_000) // 50 ms
        await fetcher.setSuccess(contributions: 1, for: "addisonk")
        let coord = RefreshCoordinator(store: store, client: fetcher, interval: 9_999)
        async let a: Void = coord.refreshAll(reason: .manual)
        async let b: Void = coord.refreshAll(reason: .timer)
        _ = await (a, b)
        let calls = await fetcher.calls(for: "addisonk")
        #expect(calls == 1, "second refresh should be skipped while one is in flight")
    }

    @Test func refreshOne_failure_preservesCachedCount() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        let fetcher = StubFetcher()
        await fetcher.setSuccess(contributions: 11, for: "addisonk")
        let coord = RefreshCoordinator(store: store, client: fetcher, interval: 9_999)
        await coord.refreshOne(username: "addisonk", reason: .manual)
        #expect(store.standing(for: "addisonk", window: .daily)?.contributions == 11)

        await fetcher.setResponse(.failure(.network("flaky")), for: "addisonk")
        await coord.refreshOne(username: "addisonk", reason: .manual)
        #expect(store.standing(for: "addisonk", window: .daily)?.contributions == 11, "refreshOne should preserve cached contributions on failure")
        if case .failed = store.standing(for: "addisonk", window: .daily)?.state {
            // expected
        } else {
            Issue.record("expected failed state")
        }
    }

    @Test func refreshAll_firstFetchFailure_writesZeroFailed() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        let fetcher = StubFetcher()
        await fetcher.setResponse(.failure(.userNotFound), for: "addisonk")
        let coord = RefreshCoordinator(store: store, client: fetcher, interval: 9_999)
        await coord.refreshAll(reason: .manual)
        let standing = store.standing(for: "addisonk", window: .daily)
        #expect(standing?.contributions == 0)
        if case .failed = standing?.state {
            // expected
        } else {
            Issue.record("expected failed state on first-fetch failure")
        }
    }

    // MARK: - Position-change notifications

    @Test func positionChange_firstRefreshSilent_thenPostsRivalCrossing() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        _ = try store.addRival(username: "octocat")
        let fetcher = StubFetcher()
        let spy = SpyNotifier()
        let coord = RefreshCoordinator(store: store, client: fetcher, interval: 9_999,
                                       now: { Date(timeIntervalSince1970: 1_000_000) }, notifier: spy)

        // First refresh: octocat below me. No prior snapshot → no notification.
        await fetcher.setSuccess(contributions: 5, for: "addisonk")
        await fetcher.setSuccess(contributions: 3, for: "octocat")
        await coord.refreshAll(reason: .manual)
        #expect(spy.allEvents.isEmpty, "first refresh has no baseline to diff against")

        // Second refresh: octocat passes me → one rivalPassedMe event.
        await fetcher.setSuccess(contributions: 9, for: "octocat")
        await coord.refreshAll(reason: .timer)
        #expect(spy.allEvents == [RankChangeEvent(
            rivalUsername: "octocat", direction: .rivalPassedMe,
            rivalContributions: 9, myContributions: 5)])
    }

    @Test func positionChange_noRelativeChange_postsNothing() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        _ = try store.addRival(username: "octocat")
        let fetcher = StubFetcher()
        let spy = SpyNotifier()
        let coord = RefreshCoordinator(store: store, client: fetcher, interval: 9_999,
                                       now: { Date(timeIntervalSince1970: 1_000_000) }, notifier: spy)
        await fetcher.setSuccess(contributions: 5, for: "addisonk")
        await fetcher.setSuccess(contributions: 3, for: "octocat")
        await coord.refreshAll(reason: .manual)
        // Both climb but order relative to me is unchanged.
        await fetcher.setSuccess(contributions: 6, for: "addisonk")
        await fetcher.setSuccess(contributions: 4, for: "octocat")
        await coord.refreshAll(reason: .timer)
        #expect(spy.allEvents.isEmpty)
    }

    @Test func positionChange_dailyReset_reBaselines_noSpuriousPost() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        _ = try store.addRival(username: "octocat")
        let fetcher = StubFetcher()
        let spy = SpyNotifier()
        let day1 = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableClock(day1)
        let coord = RefreshCoordinator(store: store, client: fetcher, interval: 9_999,
                                       now: { clock.date }, notifier: spy)

        // End of day 1: octocat ahead of me.
        await fetcher.setSuccess(contributions: 18, for: "addisonk")
        await fetcher.setSuccess(contributions: 20, for: "octocat")
        await coord.refreshAll(reason: .manual)

        // Next calendar day: the .daily window has reset toward zero. octocat now below me, which
        // a naive diff would report as "you passed octocat". The day-boundary re-baseline must
        // suppress it.
        clock.date = day1.addingTimeInterval(48 * 3_600)
        await fetcher.setSuccess(contributions: 2, for: "addisonk")
        await fetcher.setSuccess(contributions: 1, for: "octocat")
        await coord.refreshAll(reason: .timer)
        #expect(spy.allEvents.isEmpty, "a daily-window reset must not be reported as a crossing")
    }

    // MARK: - Daily rank delta (Today board chevrons)

    @Test func rankDelta_movementSinceStartOfDay() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        _ = try store.addRival(username: "octocat")
        let fetcher = StubFetcher()
        let coord = RefreshCoordinator(store: store, client: fetcher, interval: 9_999,
                                       now: { Date(timeIntervalSince1970: 1_000_000) })

        // Start of day: octocat ahead → addisonk #2, octocat #1. Baseline captured, no movement.
        await fetcher.setSuccess(contributions: 5, for: "addisonk")
        await fetcher.setSuccess(contributions: 10, for: "octocat")
        await coord.refreshAll(reason: .manual)
        #expect(coord.rankDelta(for: "addisonk") == nil)
        #expect(coord.rankDelta(for: "octocat") == nil)

        // Later same day: addisonk surges past → #2→#1 (+1), octocat #1→#2 (−1).
        await fetcher.setSuccess(contributions: 20, for: "addisonk")
        await coord.refreshAll(reason: .timer)
        #expect(coord.rankDelta(for: "addisonk") == 1)
        #expect(coord.rankDelta(for: "octocat") == -1)
    }

    @Test func rankDelta_resetsOnNewDay() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        _ = try store.addRival(username: "octocat")
        let fetcher = StubFetcher()
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let coord = RefreshCoordinator(store: store, client: fetcher, interval: 9_999,
                                       now: { clock.date })
        await fetcher.setSuccess(contributions: 5, for: "addisonk")
        await fetcher.setSuccess(contributions: 10, for: "octocat")
        await coord.refreshAll(reason: .manual)
        await fetcher.setSuccess(contributions: 20, for: "addisonk")
        await coord.refreshAll(reason: .timer)
        #expect(coord.rankDelta(for: "addisonk") == 1)

        // New day: today's climb starts fresh — the baseline resets, so no movement yet.
        clock.date = Date(timeIntervalSince1970: 1_000_000 + 48 * 3_600)
        await coord.refreshAll(reason: .timer)
        #expect(coord.rankDelta(for: "addisonk") == nil)
        #expect(coord.rankDelta(for: "octocat") == nil)
    }

    @Test func removedCompetitor_midCycle_doesNotResurrectRow() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        let rival = try store.addRival(username: "octocat")
        let fetcher = StubFetcher(delayNanos: 30_000_000)
        await fetcher.setSuccess(contributions: 7, for: "addisonk")
        await fetcher.setSuccess(contributions: 99, for: "octocat")
        let coord = RefreshCoordinator(store: store, client: fetcher, interval: 9_999)
        let task = Task { await coord.refreshAll(reason: .manual) }
        // Remove the rival while the refresh is in flight.
        try? await Task.sleep(nanoseconds: 5_000_000)
        try store.remove(id: rival.id)
        await task.value
        #expect(store.standing(for: "octocat", window: .daily) == nil, "removed competitor's standing should not be written")
    }
}

private actor ConcurrencyCountingFetcher: ContributionsFetching {
    private var active = 0
    var peak = 0
    var total = 0
    func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date) async -> Result<StandingCounts, ContributionsError> {
        active += 1
        total += 1
        peak = max(peak, active)
        try? await Task.sleep(for: .milliseconds(2))
        active -= 1
        return .success(StandingCounts(contributions: 1))
    }
}

/// iPhone pauses the 5-minute timer in the background and resumes it on becoming active.
@MainActor
struct RefreshTimerTests {
    private func makeCoordinator(_ fetcher: StubFetcher) throws -> RefreshCoordinator {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        return RefreshCoordinator(store: store, client: fetcher, interval: 0.05)
    }

    @Test func timerRefreshesWhileActive() async throws {
        let fetcher = StubFetcher()
        await fetcher.setSuccess(contributions: 1, for: "addisonk")
        let coordinator = try makeCoordinator(fetcher)
        try await Task.sleep(for: .milliseconds(400))
        #expect(await fetcher.calls(for: "addisonk") >= 1)
        withExtendedLifetime(coordinator) {}
    }

    @Test func pausedTimerDoesNotRefreshUntilResumed() async throws {
        let fetcher = StubFetcher()
        await fetcher.setSuccess(contributions: 1, for: "addisonk")
        let coordinator = try makeCoordinator(fetcher)
        coordinator.pauseTimer()
        #expect(!coordinator.isTimerRunning)
        try await Task.sleep(for: .milliseconds(400))
        #expect(await fetcher.calls(for: "addisonk") == 0)

        coordinator.resumeTimer()
        #expect(coordinator.isTimerRunning)
        try await Task.sleep(for: .milliseconds(400))
        #expect(await fetcher.calls(for: "addisonk") >= 1)
    }

    @Test func resumingARunningTimerKeepsOneTimer() async throws {
        let fetcher = StubFetcher()
        await fetcher.setSuccess(contributions: 1, for: "addisonk")
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        let coordinator = RefreshCoordinator(store: store, client: fetcher, interval: 9_999)
        coordinator.resumeTimer()
        coordinator.resumeTimer()
        #expect(coordinator.isTimerRunning)
        coordinator.pauseTimer()
        #expect(!coordinator.isTimerRunning)
    }
}

/// Counts per window, so a test can tell which Windows a refresh fetched.
actor WindowFetcher: ContributionsFetching {
    private let counts: [ContributionWindow: [String: Int]]
    private(set) var fetched: [ContributionWindow: [String]] = [:]

    init(_ counts: [ContributionWindow: [String: Int]]) { self.counts = counts }

    func calls(_ window: ContributionWindow) -> [String] { fetched[window] ?? [] }

    func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date)
        async -> Result<StandingCounts, ContributionsError> {
        fetched[window, default: []].append(username)
        guard let count = counts[window]?[username] else { return .failure(.network("no stub")) }
        return .success(StandingCounts(contributions: count))
    }
}

/// Mutable counts per window for multi-refresh tests.
final class WindowCounts: @unchecked Sendable {
    var counts: [ContributionWindow: [String: Int]]
    init(_ counts: [ContributionWindow: [String: Int]]) { self.counts = counts }
}

actor MutableWindowFetcher: ContributionsFetching {
    let source: WindowCounts
    init(_ source: WindowCounts) { self.source = source }
    func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date)
        async -> Result<StandingCounts, ContributionsError> {
        guard let count = source.counts[window]?[username] else { return .failure(.network("no stub")) }
        return .success(StandingCounts(contributions: count))
    }
}

/// iPhone hooks: Live rank's Window is refreshed alongside the board's, and Live rank hears about
/// every completed refresh. The Mac sets neither.
@MainActor
struct RefreshCompanionTests {
    private let clock = MutableClock(Date(timeIntervalSince1970: 1_793_800_000))

    private func makeStore() -> StandingsStore {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: ["alice"])
        return store
    }

    @Test func staleAdditionalWindowIsFetchedInTheSameRefresh() async {
        let store = makeStore()
        store.selectedWindow = .weekly
        let fetcher = WindowFetcher([.weekly: ["me": 30, "alice": 40], .daily: ["me": 3, "alice": 1]])
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: fetcher, interval: 99999, now: { clock.date })
        refresh.additionalWindows = { [.daily] }

        await refresh.refreshAll(reason: .manual)

        #expect(Set(await fetcher.calls(.daily)) == ["me", "alice"])
        #expect(store.standing(for: "me", window: .daily)?.contributions == 3)
        #expect(store.standing(for: "me", window: .weekly)?.contributions == 30)
    }

    @Test func freshAdditionalWindowIsNotFetchedAgain() async {
        let store = makeStore()
        let fetcher = WindowFetcher([.daily: ["me": 3, "alice": 1], .weekly: ["me": 30, "alice": 40]])
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: fetcher, interval: 99999, now: { clock.date })
        refresh.additionalWindows = { [.weekly] }
        await refresh.refreshAll(reason: .manual)

        clock.date = clock.date.addingTimeInterval(60)
        await refresh.refreshAll(reason: .timer)

        #expect(await fetcher.calls(.weekly).count == 2)   // once per person, first refresh only
        #expect(await fetcher.calls(.daily).count == 4)    // the board's Window, every refresh
    }

    @Test func boardWindowIsNotFetchedTwice() async {
        let store = makeStore()
        let fetcher = WindowFetcher([.daily: ["me": 3, "alice": 1]])
        let refresh = RefreshCoordinator(store: store, client: fetcher, interval: 99999)
        refresh.additionalWindows = { [.daily] }

        await refresh.refreshAll(reason: .manual)

        #expect(await fetcher.calls(.daily).count == 2)
    }

    @Test func todaysMovementTracksWhileTheBoardShowsAnotherWindow() async {
        let store = makeStore()
        store.selectedWindow = .monthly
        let counts = WindowCounts([.monthly: ["me": 1, "alice": 2], .daily: ["me": 1, "alice": 2]])
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: MutableWindowFetcher(counts), interval: 99999,
                                         now: { clock.date })
        refresh.additionalWindows = { [.daily] }
        await refresh.refreshAll(reason: .manual)

        counts.counts[.daily] = ["me": 5, "alice": 2]
        clock.date = clock.date.addingTimeInterval(180)
        await refresh.refreshAll(reason: .timer)

        #expect(refresh.rankDelta(for: "me") == 1)
    }

    /// This month's chevrons measure the This month ranking against its own first ranking of the
    /// day, not Today's: here you climb on This month while dropping on Today.
    @Test func thisMonthHasItsOwnMovementSinceTheStartOfToday() async {
        let store = makeStore()
        store.selectedWindow = .month
        let counts = WindowCounts([.month: ["me": 10, "alice": 20], .daily: ["me": 1, "alice": 0]])
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: MutableWindowFetcher(counts), interval: 99999,
                                         now: { clock.date })
        refresh.additionalWindows = { [.daily] }
        await refresh.refreshAll(reason: .manual)
        #expect(refresh.rankDelta(for: "me", in: .month) == nil)

        counts.counts = [.month: ["me": 25, "alice": 20], .daily: ["me": 1, "alice": 3]]
        clock.date = clock.date.addingTimeInterval(180)
        await refresh.refreshAll(reason: .timer)

        #expect(refresh.rankDelta(for: "me", in: .month) == 1)
        #expect(refresh.rankDelta(for: "alice", in: .month) == -1)
        #expect(refresh.rankDelta(for: "me", in: .daily) == -1)
        #expect(refresh.rankDelta(for: "me", in: .monthly) == nil)
    }

    /// The first ranking of a new day, here the 1st of a new month, is the new baseline: last
    /// month's climb doesn't carry into it.
    @Test func thisMonthsMovementStartsAgainOnTheFirst() async throws {
        let store = makeStore()
        store.selectedWindow = .month
        let lastDay = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12)))
        let counts = WindowCounts([.month: ["me": 10, "alice": 20]])
        let clock = MutableClock(lastDay)
        let refresh = RefreshCoordinator(store: store, client: MutableWindowFetcher(counts), interval: 99999,
                                         now: { clock.date })
        await refresh.refreshAll(reason: .manual)
        counts.counts = [.month: ["me": 25, "alice": 20]]
        clock.date = lastDay.addingTimeInterval(180)
        await refresh.refreshAll(reason: .timer)
        #expect(refresh.rankDelta(for: "me", in: .month) == 1)

        counts.counts = [.month: ["me": 0, "alice": 2]]
        clock.date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9)))
        await refresh.refreshAll(reason: .timer)
        #expect(refresh.rankDelta(for: "me", in: .month) == nil)
        #expect(refresh.rankDelta(for: "alice", in: .month) == nil)
    }

    @Test func didRefreshRunsAfterEveryRefresh() async {
        let store = makeStore()
        let fetcher = WindowFetcher([.daily: ["me": 3, "alice": 1]])
        let refresh = RefreshCoordinator(store: store, client: fetcher, interval: 99999)
        var reasons: [RefreshReason] = []
        refresh.didRefresh = { reason in
            // Counts are in place by the time Live rank hears about the refresh.
            #expect(store.standing(for: "me", window: .daily)?.state == .loaded)
            reasons.append(reason)
        }

        await refresh.refreshAll(reason: .manual)
        await refresh.refreshOne(username: "alice", reason: .visibilityChanged)

        #expect(reasons == [.manual, .visibilityChanged])
    }

    @Test func showingSomeoneAlsoFetchesTheAdditionalWindow() async {
        let store = makeStore()
        let fetcher = WindowFetcher([.daily: ["me": 3, "alice": 1], .weekly: ["me": 30, "alice": 40]])
        let refresh = RefreshCoordinator(store: store, client: fetcher, interval: 99999)
        refresh.additionalWindows = { [.weekly] }

        await refresh.refreshOne(username: "alice", reason: .visibilityChanged)

        #expect(store.standing(for: "alice", window: .weekly)?.contributions == 40)
        #expect(store.standing(for: "alice", window: .daily)?.contributions == 1)
    }
}

/// Returns each person's whole calendar, as the real client does, and records which Window each
/// page was fetched for. The Window total is worked out from the days.
actor CalendarFetcher: ContributionsFetching {
    private var histories: [String: ContributionHistory]
    private(set) var fetched: [ContributionWindow: [String]] = [:]

    init(_ histories: [String: ContributionHistory]) { self.histories = histories }

    func set(_ history: ContributionHistory?, for login: String) { histories[login] = history }
    func calls(_ window: ContributionWindow) -> [String] { fetched[window] ?? [] }
    var pages: Int { fetched.values.map(\.count).reduce(0, +) }

    func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date)
        async -> Result<StandingCounts, ContributionsError> {
        fetched[window, default: []].append(username)
        guard let history = histories[username] else { return .failure(.network("offline")) }
        return .success(StandingCounts(contributions: history.total(for: window, asOf: reference), history: history))
    }
}

/// A Refresh keeps each person's days, and works out every Window from one page per person.
@MainActor
struct RefreshDailyCountsTests {
    private let clock = MutableClock(Date(timeIntervalSince1970: 1_779_969_600)) // 2026-05-28 12:00 UTC
    private static let utc = TimeZone(identifier: "UTC")!
    private let me = ContributionHistory(days: ["2026-05-22": 4, "2026-05-28": 1], timeZone: utc)
    private let alice = ContributionHistory(days: ["2026-05-27": 6, "2026-05-28": 2], timeZone: utc)

    private func makeStore() -> StandingsStore {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: ["alice"])
        return store
    }

    @Test func aRefreshKeepsEachPersonsDays() async {
        let store = makeStore()
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: CalendarFetcher(["me": me, "alice": alice]),
                                         interval: 99999, now: { clock.date })

        await refresh.refreshAll(reason: .manual)

        #expect(store.history(for: "me") == me)
        #expect(store.history(for: "alice") == alice)
        #expect(store.standing(for: "alice", window: .daily)?.contributions == 2)
    }

    @Test func aFailedFetchKeepsTheLastDays() async {
        let store = makeStore()
        let fetcher = CalendarFetcher(["me": me, "alice": alice])
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: fetcher, interval: 99999, now: { clock.date })
        await refresh.refreshAll(reason: .manual)

        await fetcher.set(nil, for: "alice")
        clock.date = clock.date.addingTimeInterval(600)
        await refresh.refreshAll(reason: .timer)

        #expect(store.history(for: "alice") == alice)
    }

    /// Live rank's Window on iPhone comes from the same page as the board's: one page per person
    /// per Refresh, and the numbers match what a separate fetch would have given.
    @Test func anotherWindowComesFromTheSameDaysWithoutAnotherPage() async {
        let store = makeStore()
        let fetcher = CalendarFetcher(["me": me, "alice": alice])
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: fetcher, interval: 99999, now: { clock.date })
        refresh.additionalWindows = { [.weekly, .monthly] }

        await refresh.refreshAll(reason: .manual)

        #expect(await fetcher.pages == 2)
        #expect(await fetcher.calls(.weekly).isEmpty)
        #expect(store.standing(for: "me", window: .daily)?.contributions == 1)
        #expect(store.standing(for: "me", window: .weekly)?.contributions == 5)
        #expect(store.standing(for: "alice", window: .weekly)?.contributions == 8)
        #expect(store.standing(for: "alice", window: .monthly)?.contributions == 8)
        #expect(store.standing(for: "alice", window: .weekly)?.state == .loaded)
    }

    @Test func showingSomeoneFetchesOnePageForEveryWindow() async {
        let store = makeStore()
        let fetcher = CalendarFetcher(["me": me, "alice": alice])
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: fetcher, interval: 99999, now: { clock.date })
        refresh.additionalWindows = { [.weekly] }

        await refresh.refreshOne(username: "alice", reason: .visibilityChanged)

        #expect(await fetcher.pages == 1)
        #expect(store.history(for: "alice") == alice)
        #expect(store.standing(for: "alice", window: .weekly)?.contributions == 8)
    }

    /// This month on the board, read in Los Angeles: 03:00 UTC on March 1 is still February 28
    /// there, so This month is February (28 days) until local midnight, then resets to the 1st.
    @Test func thisMonthTotalsFollowTheLocalMonthAndResetOnTheFirst() async throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let days = ["2026-01-31": 50, "2026-02-01": 3, "2026-02-28": 4, "2026-03-01": 6]
        let store = makeStore()
        store.selectedWindow = .month
        let clock = MutableClock(Date(timeIntervalSince1970: 1_772_334_000)) // 2026-03-01 03:00 UTC
        let fetcher = CalendarFetcher([
            "me": ContributionHistory(days: days, timeZone: losAngeles),
            "alice": ContributionHistory(days: ["2026-02-28": 1, "2026-03-01": 9], timeZone: losAngeles),
        ])
        let refresh = RefreshCoordinator(store: store, client: fetcher, interval: 99999, now: { clock.date })
        refresh.additionalWindows = { [.monthly] }

        await refresh.refreshAll(reason: .manual)
        #expect(store.standing(for: "me", window: .month)?.contributions == 7)
        #expect(store.standing(for: "alice", window: .month)?.contributions == 1)
        #expect(store.standing(for: "me", window: .monthly)?.contributions == 57) // 30 days unchanged

        clock.date = Date(timeIntervalSince1970: 1_772_380_800) // 2026-03-01 08:00 PST
        await refresh.refreshAll(reason: .timer)
        #expect(store.standing(for: "me", window: .month)?.contributions == 6)
        #expect(store.standing(for: "alice", window: .month)?.contributions == 9)
    }
}

/// Each person's streak comes from the days their last page brought back, as of the clock.
@MainActor
struct RefreshStreakTests {
    private let clock = MutableClock(Date(timeIntervalSince1970: 1_779_969_600)) // 2026-05-28 12:00 UTC
    private static let utc = TimeZone(identifier: "UTC")!
    /// Contributed the last three days, today included.
    private let me = ContributionHistory(days: ["2026-05-25": 0, "2026-05-26": 2, "2026-05-27": 1, "2026-05-28": 3], timeZone: utc)
    /// Nothing yet today, but every day of the week before.
    private let alice = ContributionHistory(
        days: ["2026-05-21": 1, "2026-05-22": 1, "2026-05-23": 4, "2026-05-24": 1, "2026-05-25": 2,
               "2026-05-26": 1, "2026-05-27": 5, "2026-05-28": 0],
        timeZone: utc)

    private func makeStore() -> StandingsStore {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: ["alice", "bob"])
        return store
    }

    @Test func rowsGetStreaksFromTheFetchedCalendars() async {
        let store = makeStore()
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: CalendarFetcher(["me": me, "alice": alice]),
                                         interval: 99999, now: { clock.date })
        #expect(refresh.streak(for: "me") == nil) // nothing fetched yet

        await refresh.refreshAll(reason: .manual)

        #expect(refresh.streak(for: "me") == 3)
        #expect(refresh.streak(for: "alice") == 7) // alive through today
        #expect(refresh.streak(for: "bob") == nil) // failed with nothing cached: no streak, not 0
    }

    @Test func aStreakBreaksAtMidnightAfterAnEmptyDay() async {
        let store = makeStore()
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: CalendarFetcher(["me": me, "alice": alice]),
                                         interval: 99999, now: { clock.date })
        await refresh.refreshAll(reason: .manual)

        clock.date = clock.date.addingTimeInterval(13 * 3600) // 2026-05-29 01:00 UTC
        #expect(refresh.streak(for: "me") == 3) // the 28th had contributions: still alive
        #expect(refresh.streak(for: "alice") == 0) // the 28th ended empty
    }

    @Test func aFailedRefreshKeepsTheLastStreak() async {
        let store = makeStore()
        let fetcher = CalendarFetcher(["me": me, "alice": alice])
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: fetcher, interval: 99999, now: { clock.date })
        await refresh.refreshAll(reason: .manual)

        await fetcher.set(nil, for: "alice")
        clock.date = clock.date.addingTimeInterval(600)
        await refresh.refreshAll(reason: .timer)

        #expect(refresh.streak(for: "alice") == 7)
    }

    @Test func savedCalendarsShowStreaksBeforeTheFirstRefresh() {
        let people = InMemoryCompetitorPersistence()
        people.save([Competitor(username: "me", isSelf: true)])
        let saved = InMemoryContributionHistoryPersistence()
        saved.save(["me": me])
        let store = StandingsStore(persistence: people, historyPersistence: saved)
        let clock = clock
        let refresh = RefreshCoordinator(store: store, client: CalendarFetcher([:]), interval: 99999, now: { clock.date })
        #expect(refresh.streak(for: "me") == 3)
    }
}

