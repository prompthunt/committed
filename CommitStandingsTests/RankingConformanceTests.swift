import Testing
import Foundation
@testable import CommitStandings

/// Runs the shared ranking conformance cases in `fixtures/ranking-conformance.json` against
/// `Ranking.order`. The Committed relay's TypeScript port (`relay/src/ranking.ts`) runs the same
/// file, so the orderings can't drift. Each case also carries the expected `LiveRankState`, which
/// both `LiveRankState.derive` and the relay's `deriveLiveRankState` must produce.
struct RankingConformanceTests {

    struct Fixture: Decodable {
        let cases: [Case]
    }

    struct Case: Decodable {
        let name: String
        let input: Input
        let expected: Expected
    }

    struct Input: Decodable {
        let selfLogin: String
        let competitors: [String]
        let window: ContributionWindow
        let standings: [String: FixtureStanding]
        let rankDeltas: [String: Int]
        let now: Int

        enum CodingKeys: String, CodingKey {
            case selfLogin = "self"
            case competitors, window, standings, rankDeltas, now
        }
    }

    struct FixtureStanding: Decodable {
        let contributions: Int
        let window: ContributionWindow
    }

    struct Expected: Decodable {
        let order: [RankedLogin]
        let liveRankState: LiveRankState
    }

    struct RankedLogin: Decodable, Equatable {
        let login: String
        let rank: Int
    }

    /// The fixture lives at the repo root, found from this source file so no bundle resource is needed.
    static func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/ranking-conformance.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureHasCases() throws {
        #expect(!(try Self.loadFixture().cases.isEmpty))
    }

    /// You're first on your own board on every surface (and the relay enforces it), so `gapToPass`
    /// can treat a tie as yours. A case with you later would test a board that can't exist.
    @Test func everyCaseListsYouFirst() throws {
        for fixtureCase in try Self.loadFixture().cases {
            #expect(fixtureCase.input.competitors.first == fixtureCase.input.selfLogin, "\(fixtureCase.name)")
        }
    }

    static func board(_ input: Input) -> (competitors: [Competitor], standings: [String: Standing]) {
        let competitors = input.competitors.map { Competitor(username: $0, isSelf: $0 == input.selfLogin) }
        var standings: [String: Standing] = [:]
        for (login, standing) in input.standings {
            standings[login] = Standing(
                username: login,
                contributions: standing.contributions,
                window: standing.window,
                lastUpdated: Date(timeIntervalSince1970: TimeInterval(input.now)),
                state: .loaded
            )
        }
        return (competitors, standings)
    }

    @Test(arguments: try RankingConformanceTests.loadFixture().cases.map(\.name))
    func rankingOrderMatchesFixture(caseName: String) throws {
        let fixtureCase = try #require(try Self.loadFixture().cases.first { $0.name == caseName })
        let (competitors, standings) = Self.board(fixtureCase.input)

        let ranked = Ranking.order(competitors: competitors, standings: standings, window: fixtureCase.input.window)

        #expect(ranked.map { RankedLogin(login: $0.competitor.username, rank: $0.rank) } == fixtureCase.expected.order)
    }

    @Test(arguments: try RankingConformanceTests.loadFixture().cases.map(\.name))
    func liveRankStateMatchesFixture(caseName: String) throws {
        let fixtureCase = try #require(try Self.loadFixture().cases.first { $0.name == caseName })
        let input = fixtureCase.input
        let (competitors, standings) = Self.board(input)

        let state = LiveRankState.derive(
            competitors: competitors,
            standings: standings,
            window: input.window,
            rankDeltas: input.rankDeltas,
            now: Date(timeIntervalSince1970: TimeInterval(input.now))
        )

        #expect(state == fixtureCase.expected.liveRankState)
    }
}
