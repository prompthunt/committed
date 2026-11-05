import Testing
import Foundation
@testable import CommitStandingsiOS

/// The Board tab's rows and summary for the selected Window.
@MainActor
struct BoardTests {

    private let loadedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func store(owner: String = "me", members: [String], counts: [String: Int],
                       window: ContributionWindow = .daily) -> StandingsStore {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: owner, members: members)
        for (username, contributions) in counts {
            store.updateStanding(Standing(username: username, contributions: contributions, window: window,
                                          lastUpdated: loadedAt, state: .loaded))
        }
        store.selectedWindow = window
        return store
    }

    private func refresh(_ store: StandingsStore) -> RefreshCoordinator {
        RefreshCoordinator(store: store, client: StubContributions(), interval: 99_999)
    }

    @Test func rowsRankByContributionsWithTiesInRosterOrderAndMissingDataLast() {
        // Roster order is you first, then everyone alphabetically.
        let store = store(members: ["dana", "bo", "cy", "al"], counts: ["me": 4, "al": 4, "bo": 9, "cy": 0])

        let board = Board(store: store, refresh: refresh(store))

        #expect(board.rows.map(\.competitor.username) == ["bo", "me", "al", "cy", "dana"])
        #expect(board.rows.map(\.rank) == [1, 2, 3, 4, 5])
        #expect(board.rows.map { $0.standing?.contributions } == [9, 4, 4, 0, nil])
        #expect(board.maxContributions == 9)
    }

    @Test func hiddenPeopleAreLeftOffTheBoard() {
        let store = store(members: ["al", "bo"], counts: ["me": 1, "al": 5, "bo": 3])
        store.setHidden(true, username: "al")

        let board = Board(store: store, refresh: refresh(store))

        #expect(board.rows.map(\.competitor.username) == ["bo", "me"])
    }

    @Test func theSummaryShowsYourRankOutOfEveryoneAndYourContributions() {
        let store = store(members: ["al", "bo"], counts: ["me": 4, "al": 9, "bo": 1], window: .weekly)

        let summary = Board(store: store, refresh: refresh(store)).summary

        #expect(summary?.username == "me")
        #expect(summary?.rank == 2)
        #expect(summary?.competitorCount == 3)
        #expect(summary?.contributions == 4)
        #expect(summary?.window == .weekly)
    }

    @Test func beforeYourNumbersLoadTheSummaryShowsNoRankOrCount() {
        let store = store(members: ["al"], counts: ["al": 9])

        let summary = Board(store: store, refresh: refresh(store)).summary

        #expect(summary?.rank == nil)
        #expect(summary?.contributions == nil, "a placeholder, never zero")
    }

    @Test func withNoVisibleRivalsTheSummaryHasContributionsButNoRank() {
        let store = store(members: ["al"], counts: ["me": 3, "al": 9])
        store.setHidden(true, username: "al")

        let summary = Board(store: store, refresh: refresh(store)).summary

        #expect(summary?.rank == nil)
        #expect(summary?.contributions == 3)
    }

    @Test func beforePeopleSyncThereIsNoSummary() {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())

        let board = Board(store: store, refresh: refresh(store))

        #expect(board.summary == nil)
        #expect(board.rows.isEmpty)
    }

    @Test func todaysMovementShowsOnTheTodayBoardOnly() async {
        let store = store(members: ["al"], counts: [:])
        let contributions = StubContributions(["me": 1, "al": 5])
        let refresh = RefreshCoordinator(store: store, client: contributions, interval: 99_999,
                                         now: { [loadedAt] in loadedAt })
        await refresh.refreshAll(reason: .manual)  // the day's baseline: al #1, me #2
        await contributions.set("me", 8)
        await refresh.refreshAll(reason: .timer)   // me passes al

        let today = Board(store: store, refresh: refresh)
        #expect(today.rows.map(\.competitor.username) == ["me", "al"])
        #expect(today.rows.map(\.rankDelta) == [1, -1])
        #expect(today.summary?.movementToday == 1)

        store.selectedWindow = .weekly
        let week = Board(store: store, refresh: refresh)
        #expect(week.rows.allSatisfy { $0.rankDelta == nil })
        #expect(week.summary?.movementToday == nil)
    }
}
