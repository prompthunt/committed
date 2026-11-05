import Testing
import Foundation
@testable import CommitStandings

/// Live rank's state derivation: the board (competitors, counts, Window, today's movement, time)
/// in, the Dynamic Island's content state out. The shared conformance fixture runs the same rules
/// against the relay; these cases name each rule in the spec.
struct LiveRankStateTests {
    private let data = Date(timeIntervalSince1970: 1_793_800_000)

    private func board(_ logins: [String]) -> [Competitor] {
        logins.enumerated().map { Competitor(username: $1, isSelf: $0 == 0) }
    }

    private func counts(_ counts: [String: Int], window: ContributionWindow = .daily) -> [String: Standing] {
        counts.reduce(into: [:]) { result, entry in
            result[entry.key] = Standing(
                username: entry.key, contributions: entry.value, window: window, lastUpdated: data, state: .loaded
            )
        }
    }

    private func derive(
        _ logins: [String], _ standings: [String: Standing], window: ContributionWindow = .daily,
        deltas: [String: Int] = [:], now: Date? = nil
    ) -> LiveRankState {
        LiveRankState.derive(
            competitors: board(logins), standings: standings, window: window, rankDeltas: deltas, now: now ?? data
        )
    }

    @Test func rankAndNeighbors() {
        let state = derive(["me", "alice", "bob", "cy"], counts(["me": 50, "alice": 90, "bob": 20, "cy": 95]))

        #expect(state.rank == 3)
        #expect(state.competitorCount == 4)
        #expect(state.contributions == 50)
        #expect(state.above == .init(login: "alice", contributions: 90))
        #expect(state.below == .init(login: "bob", contributions: 20))
    }

    @Test func youWinTiesAsFirstOnYourBoard() {
        let state = derive(["me", "alice", "bob"], counts(["me": 40, "alice": 40, "bob": 40]))

        #expect(state.rank == 1)
        #expect(state.above == nil)
        #expect(state.below == .init(login: "alice", contributions: 40))
    }

    @Test func missingDataIsNilNeverZero() {
        let state = derive(["me", "alice"], counts(["alice": 3]))

        #expect(state.rank == nil)
        #expect(state.contributions == nil)
        #expect(state.above == nil)
        #expect(state.competitorCount == 2)
    }

    @Test func neighborWithoutDataIsLeftOut() {
        let state = derive(["me", "alice"], counts(["me": 3]))

        #expect(state.rank == 1)
        #expect(state.below == nil)
    }

    @Test func noRivalsShowsContributionsWithoutRank() {
        let state = derive(["me"], counts(["me": 7]))

        #expect(state.rank == nil)
        #expect(state.contributions == 7)
        #expect(state.competitorCount == 1)
    }

    @Test func countsForAnotherWindowAreMissing() {
        var standings = counts(["me": 10])
        standings.merge(counts(["alice": 9_999], window: .monthly)) { $1 }

        let state = derive(["me", "alice"], standings)

        #expect(state.window == "daily")
        #expect(state.rank == 1)
        #expect(state.below == nil)
    }

    @Test func movementOnlyOnToday() {
        let today = derive(["me", "alice"], counts(["me": 1, "alice": 2]), deltas: ["me": -1, "alice": 1])
        let week = derive(["me", "alice"], counts(["me": 1, "alice": 2], window: .weekly), window: .weekly,
                          deltas: ["me": -1])

        #expect(today.movementToday == -1)
        #expect(week.movementToday == 0)
    }

    @Test func updatedAtIsWholeUnixSecondsOfTheData() {
        let state = derive(["me"], counts(["me": 1]), now: Date(timeIntervalSince1970: 1_793_800_123.9))

        #expect(state.updatedAt == 1_793_800_123)
    }

    @Test func encodesTheSpecJSONShape() throws {
        let state = derive(["me", "alice"], counts(["me": 5, "alice": 9]), deltas: ["me": 1])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]

        #expect(Set(json?.keys.map { $0 } ?? []) ==
                ["window", "rank", "competitorCount", "contributions", "above", "movementToday", "updatedAt"])
        #expect((json?["above"] as? [String: Any])?["login"] as? String == "alice")
        #expect(json?["updatedAt"] as? Int == 1_793_800_000)
    }

    // MARK: - Presentation helpers

    @Test func gapToPassThePersonAhead() {
        let state = derive(["me", "alice"], counts(["me": 5, "alice": 8]))

        // You're first on your own board, so drawing level with alice passes her.
        #expect(state.gapToPass == 3)
    }

    @Test func noGapWhenNobodyIsAhead() {
        #expect(derive(["me", "alice"], counts(["me": 9, "alice": 8])).gapToPass == nil)
    }

    @Test func staleTwentyMinutesAfterTheData() {
        let state = derive(["me"], counts(["me": 1]))

        #expect(state.staleDate == data.addingTimeInterval(20 * 60))
    }

    @Test func tapOpensTheBoardOnTheWindow() {
        let state = derive(["me"], counts(["me": 1], window: .weekly), window: .weekly)

        #expect(state.boardURL == URL(string: "committed://board?window=weekly"))
    }
}

/// Live rank from the board as the store holds it: only visible people, and a row that's still
/// loading for the first time (or failed with nothing cached) is no data, not a zero.
@MainActor
struct LiveRankBoardTests {
    private let data = Date(timeIntervalSince1970: 1_793_800_000)

    private func store(_ counts: [String: Int], window: ContributionWindow = .daily) -> StandingsStore {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: Array(counts.keys))
        for (login, count) in counts {
            store.updateStanding(Standing(
                username: login, contributions: count, window: window, lastUpdated: data, state: .loaded
            ))
        }
        return store
    }

    @Test func hiddenCompetitorsAreExcluded() {
        let store = store(["me": 5, "alice": 9, "bob": 3])
        store.setHidden(true, username: "alice")

        let state = LiveRankState.board(store, window: .daily, rankDelta: { _ in nil }, now: data)

        #expect(state.rank == 1)
        #expect(state.competitorCount == 2)
        #expect(state.below == .init(login: "bob", contributions: 3))
    }

    @Test func firstLoadPlaceholderIsNoData() {
        let store = store(["alice": 9])
        store.markLoading(username: "me", window: .daily)

        let state = LiveRankState.board(store, window: .daily, rankDelta: { _ in nil }, now: data)

        #expect(state.contributions == nil)
        #expect(state.rank == nil)
    }

    @Test func cachedCountsStayWhileRefreshing() {
        let store = store(["me": 5, "alice": 9])
        store.markLoading(username: "me", window: .daily)

        let state = LiveRankState.board(store, window: .daily, rankDelta: { _ in nil }, now: data)

        #expect(state.contributions == 5)
        #expect(state.rank == 2)
    }

    @Test func usesTheLiveRankWindowNotTheBoards() {
        let store = store(["me": 50, "alice": 10], window: .weekly)
        store.selectedWindow = .daily

        let state = LiveRankState.board(store, window: .weekly, rankDelta: { _ in nil }, now: data)

        #expect(state.window == "weekly")
        #expect(state.contributions == 50)
    }

    @Test func todaysMovementIsYours() {
        let store = store(["me": 5, "alice": 9])

        let state = LiveRankState.board(store, window: .daily, rankDelta: { $0 == "me" ? -1 : 3 }, now: data)

        #expect(state.movementToday == -1)
    }

    @Test func updatedAtIsTheNewestDataNotTheClock() {
        let store = store(["me": 5])

        let state = LiveRankState.board(store, window: .daily, rankDelta: { _ in nil },
                                        now: data.addingTimeInterval(600))

        #expect(state.updatedAt == 1_793_800_000)
    }

    @Test func updatedAtFallsBackToNowWithoutData() {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: [])

        let state = LiveRankState.board(store, window: .daily, rankDelta: { _ in nil }, now: data)

        #expect(state.updatedAt == 1_793_800_000)
    }
}
