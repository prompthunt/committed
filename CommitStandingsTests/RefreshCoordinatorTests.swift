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
