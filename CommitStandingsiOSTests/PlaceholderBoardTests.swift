import Testing
import Foundation
@testable import CommitStandingsiOS

@MainActor
struct PlaceholderBoardTests {

    @Test func withNoSavedPeopleTheBoardShowsSampleStandingsRankedByContributions() {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())

        let board = PlaceholderBoard.make(store: store, window: .daily)

        #expect(board.isSample)
        #expect(board.rows.map(\.competitor.username) == ["mona", "octocat", "hubot", "defunkt"])
        #expect(board.rows.map(\.rank) == [1, 2, 3, 4])
        #expect(board.rows.map { $0.standing?.contributions } == [14, 9, 6, 2])
        #expect(board.rows.filter(\.competitor.isSelf).map(\.competitor.username) == ["octocat"])
        #expect(board.maxContributions == 14)
    }

    @Test func withSavedPeopleTheBoardRanksTheirSavedStandingsNotTheSample() {
        let snapshot = InMemoryStandingsSnapshotPersistence()
        snapshot.save([
            Standing(username: "friend", contributions: 3, window: .weekly, lastUpdated: .now, state: .loaded),
            Standing(username: "me", contributions: 8, window: .weekly, lastUpdated: .now, state: .loaded),
            Standing(username: "friend", contributions: 50, window: .daily, lastUpdated: .now, state: .loaded),
        ])
        let people = InMemoryCompetitorPersistence()
        people.save([
            Competitor(username: "me", isSelf: true),
            Competitor(username: "friend", isSelf: false),
            Competitor(username: "never-loaded", isSelf: false),
        ])
        let store = StandingsStore(persistence: people, snapshotPersistence: snapshot)

        let board = PlaceholderBoard.make(store: store, window: .weekly)

        #expect(!board.isSample)
        #expect(board.rows.map(\.competitor.username) == ["me", "friend", "never-loaded"])
        #expect(board.rows.map(\.rank) == [1, 2, 3])
        #expect(board.rows.map { $0.standing?.contributions } == [8, 3, nil])
        #expect(board.maxContributions == 8)
    }
}
