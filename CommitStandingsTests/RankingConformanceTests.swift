import Testing
import Foundation
@testable import CommitStandings

/// Runs the shared ranking conformance cases in `fixtures/ranking-conformance.json` against
/// `Ranking.order`. The Committed relay's TypeScript port (`relay/src/ranking.ts`) runs the same
/// file, so the two orderings can't drift. Each case also carries the expected `LiveRankState`;
/// the Swift derivation lands in #43, which extends this test to check it.
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

    @Test(arguments: try RankingConformanceTests.loadFixture().cases.map(\.name))
    func rankingOrderMatchesFixture(caseName: String) throws {
        let fixtureCase = try #require(try Self.loadFixture().cases.first { $0.name == caseName })
        let input = fixtureCase.input
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

        let ranked = Ranking.order(competitors: competitors, standings: standings, window: input.window)

        #expect(ranked.map { RankedLogin(login: $0.competitor.username, rank: $0.rank) } == fixtureCase.expected.order)
    }
}
