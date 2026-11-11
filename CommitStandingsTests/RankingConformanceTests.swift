import Testing
import Foundation
@testable import CommitStandings

/// Runs the shared ranking conformance cases in `fixtures/ranking-conformance.json` against
/// `Ranking.order`. The Committed relay's TypeScript port (`relay/src/ranking.ts`) runs the same
/// file, so the orderings can't drift. Each case also carries the expected `LiveRankState`, which
/// both `LiveRankState.derive` and the relay's `deriveLiveRankState` must produce. Cases with
/// calendars (`days`) rank by totals `ContributionHistory` works out from them, and carry everyone's
/// current streak.
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
        /// Counts, or `days` (calendars) with `timeZone` and `asOf`; never both.
        let standings: [String: FixtureStanding]?
        let days: [String: [String: Int]]?
        let timeZone: String?
        /// The local day (`YYYY-MM-DD`) at `now` in `timeZone`.
        let asOf: String?
        let rankDeltas: [String: Int]
        let now: Int

        enum CodingKeys: String, CodingKey {
            case selfLogin = "self"
            case competitors, window, standings, days, timeZone, asOf, rankDeltas, now
        }

        var date: Date { Date(timeIntervalSince1970: TimeInterval(now)) }

        /// Each person's calendar, read in the case's time zone.
        var histories: [String: ContributionHistory] {
            guard let days, let timeZone, let zone = TimeZone(identifier: timeZone) else { return [:] }
            return days.mapValues { ContributionHistory(days: $0, timeZone: zone) }
        }
    }

    struct FixtureStanding: Decodable {
        let contributions: Int
        let window: ContributionWindow
    }

    struct Expected: Decodable {
        let order: [RankedLogin]
        /// Everyone in `days`, raw (`currentStreak`).
        let streaks: [String: Int]?
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

    /// A case gives counts or calendars, never both, so nothing worked out from days is overridden.
    @Test func everyCaseGivesStandingsOrDays() throws {
        for fixtureCase in try Self.loadFixture().cases {
            let input = fixtureCase.input
            #expect((input.standings == nil) == (input.days != nil), "\(fixtureCase.name)")
            if input.days != nil {
                #expect(input.timeZone.flatMap(TimeZone.init(identifier:)) != nil, "\(fixtureCase.name)")
                #expect(input.asOf != nil, "\(fixtureCase.name)")
                #expect(fixtureCase.expected.streaks != nil, "\(fixtureCase.name)")
            }
        }
        #expect(try Self.loadFixture().cases.contains { $0.input.days != nil })
    }

    static func board(_ input: Input) -> (competitors: [Competitor], standings: [String: Standing]) {
        let competitors = input.competitors.map { Competitor(username: $0, isSelf: $0 == input.selfLogin) }
        var counts: [String: (Int, ContributionWindow)] = [:]
        for (login, standing) in input.standings ?? [:] {
            counts[login] = (standing.contributions, standing.window)
        }
        for (login, history) in input.histories {
            counts[login] = (history.total(for: input.window, asOf: input.date), input.window)
        }
        var standings: [String: Standing] = [:]
        for (login, (contributions, window)) in counts {
            standings[login] = Standing(
                username: login,
                contributions: contributions,
                window: window,
                lastUpdated: input.date,
                state: .loaded
            )
        }
        return (competitors, standings)
    }

    static func streaks(_ input: Input) -> [String: Int] {
        input.histories.mapValues { $0.currentStreak(asOf: input.date) }
    }

    @Test(arguments: try RankingConformanceTests.loadFixture().cases.filter { $0.input.days != nil }.map(\.name))
    func localDayMatchesFixture(caseName: String) throws {
        let input = try #require(try Self.loadFixture().cases.first { $0.name == caseName }).input
        let history = try #require(input.histories.values.first)

        #expect(ContributionHistory.key(for: input.date, in: history.calendar) == input.asOf)
    }

    @Test(arguments: try RankingConformanceTests.loadFixture().cases.filter { $0.input.days != nil }.map(\.name))
    func streaksMatchFixture(caseName: String) throws {
        let fixtureCase = try #require(try Self.loadFixture().cases.first { $0.name == caseName })

        #expect(Self.streaks(fixtureCase.input) == fixtureCase.expected.streaks)
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
            streaks: Self.streaks(input),
            now: input.date
        )

        #expect(state == fixtureCase.expected.liveRankState)
    }
}
