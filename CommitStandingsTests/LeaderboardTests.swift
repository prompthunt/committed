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

    /// "🔥 12" beside the count from 2 days, capped at "365+" past GitHub's calendar, and read as
    /// "12-day streak" (never the emoji).
    @Test func streakLabelShowsFromTwoDaysAndCapsAtTheCalendar() {
        #expect(StreakLabel.text(nil) == nil)
        #expect(StreakLabel.text(0) == nil)
        #expect(StreakLabel.text(1) == nil)
        #expect(StreakLabel.text(2) == "🔥 2")
        #expect(StreakLabel.text(12) == "🔥 12")
        #expect(StreakLabel.text(365) == "🔥 365")
        #expect(StreakLabel.text(366) == "🔥 365+")
        #expect(StreakLabel.spoken(1) == nil)
        #expect(StreakLabel.spoken(12) == "12-day streak")
        #expect(StreakLabel.spoken(371) == "365-plus-day streak")
    }

    @Test func rowReadsItsStreakOnlyWhenTheCountHasLoaded() {
        let competitor = Competitor(username: "ada", isSelf: false)
        let loaded = Standing(username: "ada", contributions: 4, window: .daily, lastUpdated: .now, state: .loaded)
        let row = StandingRow(rank: 1, competitor: competitor, standing: loaded, window: .daily,
                              rankDelta: 1, streak: 12)
        #expect(row.accessibilityDescription == "rank 1, ada, 4 contributions for today, 12-day streak, up 1 place today")

        let oneDay = StandingRow(rank: 1, competitor: competitor, standing: loaded, window: .daily, streak: 1)
        #expect(!oneDay.accessibilityDescription.contains("streak"))

        let failed = Standing(username: "ada", contributions: 0, window: .daily,
                              lastUpdated: .distantPast, state: .failed("Offline"))
        let noCount = StandingRow(rank: 1, competitor: competitor, standing: failed, window: .daily, streak: 12)
        #expect(!noCount.accessibilityDescription.contains("streak"))
        #expect(noCount.streakText == nil)

        let loading = Standing(username: "ada", contributions: 0, window: .daily,
                               lastUpdated: .distantPast, state: .loading)
        #expect(StandingRow(rank: 1, competitor: competitor, standing: loading, window: .daily, streak: 12)
            .streakText == nil)
        #expect(row.streakText == "🔥 12")
    }

    @Test func heroCardReadsYourStreakBesideALoadedCount() {
        #expect(HeroCard.accessibilityLabel(username: "me", contributions: 7, window: .daily, streak: 12)
            == "@me, 7 contributions for today, 12-day streak")
        #expect(HeroCard.accessibilityLabel(username: "me", contributions: 7, window: .daily, streak: 1)
            == "@me, 7 contributions for today")
        #expect(HeroCard.accessibilityLabel(username: "me", contributions: nil, window: .daily, streak: 12)
            == "@me, no contributions data yet")
    }
}
