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
