import Foundation
import Testing
@testable import CommitStandingsiOS

struct PlaceholderBoardTests {
    @Test func freshInstallShowsTheSampleBoardRankedByContributions() {
        let board = PlaceholderBoard.make(competitors: [], standings: [:], window: .daily)

        #expect(board.isSample)
        #expect(board.rows.map(\.rank) == [1, 2, 3, 4, 5])
        #expect(board.rows.map(\.competitor.username) == [
            "Maya R.", "Priya S.", "Your name", "Devon K.", "Sam L."
        ])
        #expect(board.rows.map { $0.standing?.contributions } == [12, 9, 7, 4, 0])
        #expect(board.rows.filter(\.competitor.isSelf).map(\.competitor.username) == ["Your name"])
        #expect(board.maxContributions == 12)
    }

    @Test func sampleNamesCanNeverBeRealGitHubAccounts() {
        // Rows load avatars from github.com/<username>.png, so a sample name that is a valid
        // login would show a stranger's avatar.
        let board = PlaceholderBoard.make(competitors: [], standings: [:], window: .monthly)

        #expect(!board.rows.isEmpty)
        for row in board.rows {
            #expect(UsernameNormalization.normalize(row.competitor.username) == nil)
        }
    }

    @Test func savedStandingsReplaceTheSampleAndMissingDataStaysAPlaceholder() {
        let me = Competitor(username: "addisonk", isSelf: true)
        let ada = Competitor(username: "ada", isSelf: false)
        let lin = Competitor(username: "lin", isSelf: false)
        let saved = [
            "addisonk": Standing(username: "addisonk", contributions: 3, window: .weekly,
                                 lastUpdated: Date(timeIntervalSince1970: 1_000), state: .loaded),
            "ada": Standing(username: "ada", contributions: 20, window: .weekly,
                            lastUpdated: Date(timeIntervalSince1970: 1_000), state: .loaded),
        ]

        let board = PlaceholderBoard.make(competitors: [me, ada, lin], standings: saved, window: .weekly)

        #expect(!board.isSample)
        #expect(board.rows.map(\.competitor.username) == ["ada", "addisonk", "lin"])
        #expect(board.rows.map(\.rank) == [1, 2, 3])
        #expect(board.rows.map { $0.standing?.contributions } == [20, 3, nil])
        #expect(board.maxContributions == 20)
    }
}
