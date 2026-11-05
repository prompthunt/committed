import Testing
import Foundation
@testable import CommitStandings

@MainActor
struct LeaderboardRankingTests {

    private func standing(_ name: String, contributions: Int, window: ContributionWindow) -> Standing {
        Standing(username: name, contributions: contributions, window: window, lastUpdated: .now, state: .loaded)
    }

    @Test func descendingOrder_byContributions() {
        let me = Competitor(username: "addisonk", isSelf: true)
        let a = Competitor(username: "alice", isSelf: false)
        let b = Competitor(username: "bob", isSelf: false)
        let standings: [String: Standing] = [
            "addisonk": standing("addisonk", contributions: 50, window: .daily),
            "alice":    standing("alice",    contributions: 90, window: .daily),
            "bob":      standing("bob",      contributions: 20, window: .daily)
        ]
        let ranked = Ranking.order(competitors: [me, a, b], standings: standings, window: .daily)
        #expect(ranked.map(\.competitor.username) == ["alice", "addisonk", "bob"])
        #expect(ranked.map(\.rank) == [1, 2, 3])
    }

    @Test func ties_preserveOriginalOrder() {
        let me = Competitor(username: "addisonk", isSelf: true)
        let a = Competitor(username: "alice", isSelf: false)
        let b = Competitor(username: "bob", isSelf: false)
        let standings: [String: Standing] = [
            "addisonk": standing("addisonk", contributions: 40, window: .weekly),
            "alice":    standing("alice",    contributions: 40, window: .weekly),
            "bob":      standing("bob",      contributions: 40, window: .weekly)
        ]
        let ranked = Ranking.order(competitors: [me, a, b], standings: standings, window: .weekly)
        #expect(ranked.map(\.competitor.username) == ["addisonk", "alice", "bob"])
    }

    @Test func noStanding_sortsLast_belowRealZero() {
        let me = Competitor(username: "addisonk", isSelf: true)
        let a = Competitor(username: "alice", isSelf: false)
        let standings: [String: Standing] = [
            // addisonk has no standing → -1 sentinel; alice has a real 0 → sorts ahead.
            "alice": standing("alice", contributions: 0, window: .weekly)
        ]
        let ranked = Ranking.order(competitors: [me, a], standings: standings, window: .weekly)
        #expect(ranked.map(\.competitor.username) == ["alice", "addisonk"])
    }

    @Test func contributionsFromOtherWindows_doNotAffectCurrentRanking() {
        let me = Competitor(username: "addisonk", isSelf: true)
        let a = Competitor(username: "alice", isSelf: false)
        let standings: [String: Standing] = [
            "addisonk": standing("addisonk", contributions: 10,   window: .daily),
            "alice":    standing("alice",    contributions: 9999, window: .monthly)
        ]
        let ranked = Ranking.order(competitors: [me, a], standings: standings, window: .daily)
        #expect(ranked.map(\.competitor.username) == ["addisonk", "alice"])
    }

    @Test func relativeTime_formatting() {
        let now = Date(timeIntervalSince1970: 10_000)
        let oneMinAgo = now.addingTimeInterval(-90)
        let oneHourAgo = now.addingTimeInterval(-90 * 60)
        #expect(RelativeTimeFormatter.short(from: now.addingTimeInterval(-10), to: now) == "just now")
        #expect(RelativeTimeFormatter.short(from: oneMinAgo, to: now) == "1m ago")
        #expect(RelativeTimeFormatter.short(from: oneHourAgo, to: now) == "1h ago")
    }

    @Test func rankingIdentitySurvivesPositionChanges() {
        let me = Competitor(username: "me", isSelf: true)
        let rival = Competitor(username: "rival", isSelf: false)
        let before = Ranking.order(competitors: [me, rival], standings: [
            "me": standing("me", contributions: 1, window: .daily),
            "rival": standing("rival", contributions: 2, window: .daily)
        ], window: .daily)
        let after = Ranking.order(competitors: [me, rival], standings: [
            "me": standing("me", contributions: 3, window: .daily),
            "rival": standing("rival", contributions: 2, window: .daily)
        ], window: .daily)

        #expect(before.first?.id == rival.id)
        #expect(after.first?.id == me.id)
        #expect(before.last?.id == after.first?.id)
        #expect(before.first?.id == after.last?.id)
    }

    /// The shared conformance fixture (`shared/fixtures/ranking-conformance.json`) is binding for
    /// both this app and the Committed relay's TypeScript port, so the two orderings can't drift.
    /// A login with no entry in `standings` has no data.
    @Test func rankingOrder_matchesSharedConformanceFixture() throws {
        let fixture = try RankingConformanceFixture.load()
        #expect(!fixture.cases.isEmpty)
        for testCase in fixture.cases {
            let competitors = testCase.input.competitors.map {
                Competitor(username: $0.login, isSelf: $0.isSelf)
            }
            var standings: [String: Standing] = [:]
            for (login, entry) in testCase.input.standings {
                let window = try #require(ContributionWindow(rawValue: entry.window), "\(testCase.name)")
                standings[login] = Standing(
                    username: login,
                    contributions: entry.contributions,
                    window: window,
                    lastUpdated: Date(timeIntervalSince1970: entry.lastUpdated),
                    state: .loaded
                )
            }
            let window = try #require(ContributionWindow(rawValue: testCase.input.window), "\(testCase.name)")
            let ranked = Ranking.order(competitors: competitors, standings: standings, window: window)
            let actual = ranked.map { RankingConformanceFixture.Ranked(login: $0.competitor.username, rank: $0.rank) }
            #expect(actual == testCase.expected.order, "\(testCase.name)")
        }
    }

    @Test func rowAccessibilityIncludesRankMovementAndStaleData() {
        let competitor = Competitor(username: "me", isSelf: true)
        let cached = Standing(username: "me", contributions: 12, window: .daily,
                              lastUpdated: .now, state: .failed("Offline"))
        let row = StandingRow(rank: 2, competitor: competitor, standing: cached,
                              window: .daily, rankDelta: -1)
        #expect(row.accessibilityDescription.contains("stale, 12 contributions"))
        #expect(row.accessibilityDescription.contains("Refresh failed: Offline"))
        #expect(row.accessibilityDescription.hasSuffix("down 1 place today"))

        let unchanged = StandingRow(rank: 2, competitor: competitor, standing: cached,
                                    window: .daily, rankDelta: 0)
        #expect(!unchanged.accessibilityDescription.contains("places today"))
    }
}

/// Decodes `shared/fixtures/ranking-conformance.json`, found relative to this source file so the
/// test needs no bundle resource (and no project change). The LiveRankState expectations in the
/// same file are checked by the LiveRankState tests.
struct RankingConformanceFixture: Decodable {
    struct Ranked: Decodable, Equatable {
        let login: String
        let rank: Int
    }
    struct Person: Decodable {
        let login: String
        let isSelf: Bool
    }
    struct Entry: Decodable {
        let contributions: Int
        let window: String
        let lastUpdated: Double
    }
    struct Input: Decodable {
        let competitors: [Person]
        let standings: [String: Entry]
        let window: String
        let rankDeltas: [String: Int]
        let now: Double
    }
    struct Expected: Decodable {
        let order: [Ranked]
        let liveRankState: LiveRankState
    }
    struct Case: Decodable {
        let name: String
        let input: Input
        let expected: Expected
    }
    let cases: [Case]

    static func url(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()      // CommitStandingsTests/
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("shared/fixtures/ranking-conformance.json")
    }

    static func load() throws -> RankingConformanceFixture {
        try JSONDecoder().decode(RankingConformanceFixture.self, from: Data(contentsOf: url()))
    }
}

extension RankingConformanceFixture.Case {
    /// The case's input as the app's own types. A login with no entry in `standings` has no data.
    func appInput() throws -> (competitors: [Competitor], standings: [String: Standing], window: ContributionWindow) {
        let competitors = input.competitors.map { Competitor(username: $0.login, isSelf: $0.isSelf) }
        var standings: [String: Standing] = [:]
        for (login, entry) in input.standings {
            let window = try #require(ContributionWindow(rawValue: entry.window), "\(name)")
            standings[login] = Standing(
                username: login,
                contributions: entry.contributions,
                window: window,
                lastUpdated: Date(timeIntervalSince1970: entry.lastUpdated),
                state: .loaded
            )
        }
        let window = try #require(ContributionWindow(rawValue: input.window), "\(name)")
        return (competitors, standings, window)
    }
}

/// Live rank's content state comes from one pure derivation. The shared fixture is binding (the
/// relay derives the same state); the cases below it cover what only the device can produce.
@MainActor
struct LiveRankStateTests {

    @Test func derivation_matchesSharedConformanceFixture() throws {
        let fixture = try RankingConformanceFixture.load()
        #expect(fixture.cases.count >= 17)
        for testCase in fixture.cases {
            let (competitors, standings, window) = try testCase.appInput()
            let state = LiveRankState.derive(
                competitors: competitors,
                standings: standings,
                window: window,
                rankDeltas: testCase.input.rankDeltas,
                now: Date(timeIntervalSince1970: testCase.input.now)
            )
            #expect(state == testCase.expected.liveRankState, "\(testCase.name)")
        }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_300)

    private func loaded(_ login: String, _ count: Int, _ window: ContributionWindow = .daily,
                        at seconds: TimeInterval = 1_800_000_000) -> Standing {
        Standing(username: login, contributions: count, window: window,
                 lastUpdated: Date(timeIntervalSince1970: seconds), state: .loaded)
    }

    /// The board's projection of the store: what Live rank ranks.
    private func store(_ people: [String], hidden: [String] = [], standings: [Standing]) -> StandingsStore {
        let store = StandingsStore()
        store.replaceRoster(owner: people[0], members: Array(people.dropFirst()))
        for standing in standings { store.updateStanding(standing) }
        for login in hidden { store.setHidden(true, username: login) }
        return store
    }

    @Test func hiddenRivalsAreLeftOutOfRankNeighborsAndCount() {
        let store = store(["me", "alice", "bob"], hidden: ["alice"],
                          standings: [loaded("me", 5), loaded("alice", 9), loaded("bob", 3)])

        let state = LiveRankState(store: store, window: .daily, rankDelta: { _ in nil }, now: now)

        #expect(state.rank == 1)
        #expect(state.competitorCount == 2)
        #expect(state.above == nil)
        #expect(state.below == .init(login: "bob", contributions: 3))
    }

    /// A failed fetch with nothing cached (and an in-flight first load) is stored as a zero count
    /// dated `.distantPast`. Live rank treats it as no data, like the relay, never as a real 0.
    @Test func placeholderRowsCountAsNoData() {
        let failed = Standing(username: "alice", contributions: 0, window: .daily,
                              lastUpdated: .distantPast, state: .failed("Offline"))
        let store = store(["me", "alice"], standings: [loaded("me", 0), failed])

        let state = LiveRankState(store: store, window: .daily, rankDelta: { _ in nil }, now: now)

        #expect(state.rank == 1, "a real zero ranks above no data")
        #expect(state.below == nil)
        #expect(state.updatedAt == 1_800_000_000)
    }

    @Test func storeDerivationReadsTheLiveRankWindowAndTodaysMovement() {
        let store = store(["me", "alice"], standings: [
            loaded("me", 5), loaded("alice", 9),
            loaded("me", 40, .weekly, at: 1_800_000_100), loaded("alice", 30, .weekly, at: 1_800_000_100),
        ])
        store.selectedWindow = .daily

        let weekly = LiveRankState(store: store, window: .weekly, rankDelta: { _ in 1 }, now: now)
        let daily = LiveRankState(store: store, window: .daily, rankDelta: { $0 == "me" ? -1 : nil }, now: now)

        #expect(weekly.window == "weekly")
        #expect(weekly.rank == 1)
        #expect(weekly.movementToday == 0, "movement is a Today thing")
        #expect(weekly.updatedAt == 1_800_000_100)
        #expect(daily.rank == 2)
        #expect(daily.movementToday == -1)
        #expect(daily.above == .init(login: "alice", contributions: 9))
    }

    @Test func encodesTheSpecShapeWithIntegerSecondsAndNoNilKeys() throws {
        let state = LiveRankState(window: "daily", rank: nil, competitorCount: 1, contributions: 4,
                                  above: nil, below: nil, movementToday: 0, updatedAt: 1_800_000_000)

        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])

        #expect(Set(json.keys) == ["window", "competitorCount", "contributions", "movementToday", "updatedAt"])
        #expect(json["updatedAt"] as? Int == 1_800_000_000)
        let relayPayload = #"{"window":"weekly","rank":2,"competitorCount":3,"contributions":null,"#
            + #""above":{"login":"alice","contributions":9},"below":null,"movementToday":0,"updatedAt":1800000000}"#
        let decoded = try JSONDecoder().decode(LiveRankState.self, from: Data(relayPayload.utf8))
        #expect(decoded.contributions == nil)
        #expect(decoded.above == .init(login: "alice", contributions: 9))
        #expect(decoded.below == nil)
    }

    @Test func gapToPassCountsWhatItTakesToMoveAheadIncludingATie() {
        var state = LiveRankState(window: "daily", rank: 2, competitorCount: 3, contributions: 5,
                                  above: .init(login: "alice", contributions: 8), below: nil,
                                  movementToday: 0, updatedAt: 0)
        #expect(state.gapToPass == 4)
        state.above = .init(login: "alice", contributions: 5)
        #expect(state.gapToPass == 1, "tied but ranked above: one more passes them")
        state.above = nil
        #expect(state.gapToPass == nil)
    }

    @Test func goesStaleTwentyMinutesAfterTheData() {
        let state = LiveRankState(window: "monthly", rank: nil, competitorCount: 1, contributions: nil,
                                  above: nil, below: nil, movementToday: 0, updatedAt: 1_800_000_000)
        #expect(state.updatedDate == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(state.staleDate == Date(timeIntervalSince1970: 1_800_001_200))
    }

    @Test func tappingOpensTheBoardOnTheLiveRankWindow() {
        let state = LiveRankState(window: "weekly", rank: 1, competitorCount: 2, contributions: 3,
                                  above: nil, below: nil, movementToday: 0, updatedAt: 0)
        #expect(state.boardURL == URL(string: "committed://board?window=weekly"))
        #expect(state.contributionWindow == .weekly)
    }
}
