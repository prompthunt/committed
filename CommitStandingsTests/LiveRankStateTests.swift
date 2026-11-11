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
        deltas: [String: Int] = [:], streaks: [String: Int] = [:], now: Date? = nil
    ) -> LiveRankState {
        LiveRankState.derive(
            competitors: board(logins), standings: standings, window: window, rankDeltas: deltas,
            streaks: streaks, now: now ?? data
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

    /// The island's rows show each neighbor's chevron, like the board's rows.
    @Test func neighborsCarryTheirOwnMovementOnToday() {
        let state = derive(["me", "alice", "bob"], counts(["me": 5, "alice": 9, "bob": 2]),
                           deltas: ["me": 1, "alice": -2])

        #expect(state.above?.movementToday == -2)
        #expect(state.below?.movementToday == 0)
    }

    @Test func neighborsHaveNoMovementOutsideToday() {
        let state = derive(["me", "alice"], counts(["me": 5, "alice": 9], window: .weekly), window: .weekly,
                           deltas: ["alice": 3])

        #expect(state.above?.movementToday == 0)
    }

    @Test func neighborEncodesItsMovement() throws {
        let state = derive(["me", "alice"], counts(["me": 5, "alice": 9]), deltas: ["alice": 1])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]

        #expect((json?["above"] as? [String: Any])?["movementToday"] as? Int == 1)
    }

    /// Pushes from a relay without the field, and states persisted by an older build, still decode.
    @Test func neighborDecodesWithoutMovementAsZero() throws {
        let json = #"""
        {"window":"daily","rank":2,"competitorCount":3,"contributions":5,
         "above":{"login":"alice","contributions":9},"below":{"login":"bob","contributions":1},
         "movementToday":1,"updatedAt":1793800000}
        """#
        let state = try JSONDecoder().decode(LiveRankState.self, from: Data(json.utf8))

        #expect(state.above == LiveRankState.Neighbor(login: "alice", contributions: 9, movementToday: 0))
        #expect(state.below?.movementToday == 0)
        #expect(state.movementToday == 1)
    }

    @Test func neighborDecodesItsMovement() throws {
        let json = #"""
        {"window":"daily","rank":2,"competitorCount":3,"contributions":5,
         "above":{"login":"alice","contributions":9,"movementToday":-1},"below":null,
         "movementToday":1,"updatedAt":1793800000}
        """#
        let state = try JSONDecoder().decode(LiveRankState.self, from: Data(json.utf8))

        #expect(state.above == LiveRankState.Neighbor(login: "alice", contributions: 9, movementToday: -1))
    }

    // MARK: Streaks

    @Test func streaksForYouAndYourNeighbors() {
        let state = derive(["me", "alice", "bob"], counts(["me": 5, "alice": 9, "bob": 1]),
                           streaks: ["me": 4, "alice": 12, "bob": 0])

        #expect(state.streak == 4)
        #expect(state.above?.streak == 12)
        #expect(state.below?.streak == 0)
    }

    /// A streak follows its count: none beside a count that hasn't loaded, and none without a calendar.
    @Test func noStreakWithoutACountOrACalendar() {
        let missingCount = derive(["me", "alice"], counts(["alice": 9]), streaks: ["me": 4, "alice": 2])
        #expect(missingCount.streak == nil)

        let noCalendar = derive(["me", "alice"], counts(["me": 5, "alice": 9]), streaks: ["me": 4])
        #expect(noCalendar.streak == 4)
        #expect(noCalendar.above?.streak == nil)
    }

    /// Pushes from a relay without streaks, and states saved by an older build, still decode.
    @Test func decodesWithoutStreaks() throws {
        let json = #"""
        {"window":"daily","rank":2,"competitorCount":3,"contributions":5,
         "above":{"login":"alice","contributions":9,"movementToday":0},"below":null,
         "movementToday":1,"updatedAt":1793800000}
        """#
        let state = try JSONDecoder().decode(LiveRankState.self, from: Data(json.utf8))

        #expect(state.streak == nil)
        #expect(state.above?.streak == nil)
    }

    /// The neighbor's hand-written decoder reads its streak too.
    @Test func decodesStreaksForYouAndYourNeighbors() throws {
        let json = #"""
        {"window":"daily","rank":2,"competitorCount":3,"contributions":5,"streak":7,
         "above":{"login":"alice","contributions":9,"movementToday":0,"streak":12},
         "below":{"login":"bob","contributions":1,"streak":0},
         "movementToday":1,"updatedAt":1793800000}
        """#
        let state = try JSONDecoder().decode(LiveRankState.self, from: Data(json.utf8))

        #expect(state.streak == 7)
        #expect(state.above == LiveRankState.Neighbor(login: "alice", contributions: 9, movementToday: 0, streak: 12))
        #expect(state.below?.streak == 0)
    }

    /// Like the relay, a streak that isn't known is left out of the JSON, not written as null.
    @Test func encodesStreaksOnlyWhenKnown() throws {
        let state = derive(["me", "alice"], counts(["me": 5, "alice": 9]), streaks: ["me": 3])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]

        #expect(json?["streak"] as? Int == 3)
        #expect((json?["above"] as? [String: Any])?.keys.contains("streak") == false)
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

    @Test func passLineNamesWhoIsAhead() {
        #expect(derive(["me", "alice"], counts(["me": 5, "alice": 8])).passLine == "3 to pass alice")
        #expect(derive(["me", "alice"], counts(["me": 9, "alice": 8])).passLine == nil)
    }

    /// Live rank never shows a row of placeholders without saying why.
    @Test func emptyStatesSayWhatTheyreWaitingFor() {
        #expect(derive(["me"], counts(["me": 4])).emptyStateLine == "Just you so far")
        #expect(derive(["me", "alice"], counts(["alice": 8])).emptyStateLine == "Waiting for your first count")
        #expect(derive(["me", "alice"], counts(["me": 5, "alice": 8])).emptyStateLine == nil)
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

    @Test func todaysMovementOfTheNeighborsToo() {
        let store = store(["me": 5, "alice": 9, "bob": 2])

        let deltas = ["me": -1, "alice": 1, "bob": 2]

        let state = LiveRankState.board(store, window: .daily, rankDelta: { deltas[$0] }, now: data)

        #expect(state.above?.movementToday == 1)
        #expect(state.below?.movementToday == 2)
    }

    /// Streaks from each person's saved calendar, as of the clock (not the data's date), like the
    /// Board's rows.
    @Test func streaksFromSavedCalendarsAsOfNow() {
        let store = store(["me": 5, "alice": 9])
        let utc = TimeZone(identifier: "UTC")!
        // The data is from Nov 4; it's now Nov 5. Alice's run ended on Nov 3.
        store.updateHistories([
            "me": ContributionHistory(days: ["2026-11-03": 1, "2026-11-04": 2], timeZone: utc),
            "alice": ContributionHistory(days: ["2026-11-03": 3, "2026-11-04": 0], timeZone: utc),
        ])

        let state = LiveRankState.board(store, window: .daily, rankDelta: { _ in nil },
                                        now: data.addingTimeInterval(24 * 3600))

        #expect(state.streak == 2)
        #expect(state.above?.streak == 0)
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
