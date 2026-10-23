import Testing
import Foundation
@testable import CommitStandings

struct StandingMetricsTests {

    @Test func standing_holdsContributions() {
        let s = Standing(username: "addisonk", contributions: 42, window: .weekly, lastUpdated: .distantPast, state: .loaded)
        #expect(s.contributions == 42)
    }

    @Test func standing_zeroIsAValidContributionCount() {
        let zero = Standing(username: "a", contributions: 0, window: .daily, lastUpdated: .now, state: .loaded)
        let five = Standing(username: "a", contributions: 5, window: .daily, lastUpdated: .now, state: .loaded)
        #expect(zero != five)
    }

    @Test func standingCounts_equality() {
        #expect(StandingCounts(contributions: 7) == StandingCounts(contributions: 7))
        #expect(StandingCounts(contributions: 7) != StandingCounts(contributions: 8))
    }

    /// Regression: a persisted snapshot written by an older multi-metric build still carries
    /// `commits`/`mergedPRs`/`locChanged`/`locApproximate`. Decoding it into the slimmed
    /// `Standing` must NOT throw (extra keys are ignored) — otherwise updating crashes the board.
    @Test func standing_decodesLegacyMultiMetricSnapshot() throws {
        let legacy = """
        [{"username":"addisonk","contributions":18,"commits":5,"mergedPRs":2,"locChanged":3600,"locApproximate":false,"window":"daily","lastUpdated":0,"state":{"loaded":{}}}]
        """
        let data = Data(legacy.utf8)
        let decoded = try JSONDecoder().decode([Standing].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded.first?.contributions == 18)
        #expect(decoded.first?.username == "addisonk")
    }
}
