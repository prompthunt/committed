import Foundation
import Testing
@testable import CommitStandingsiOS

struct BoardSummaryTests {
    private let me = Competitor(username: "me", isSelf: true)
    private let ada = Competitor(username: "ada", isSelf: false)
    private let lin = Competitor(username: "lin", isSelf: false)
    private let loadedAt = Date(timeIntervalSince1970: 1_000)

    private func standing(_ username: String, _ count: Int, _ window: ContributionWindow = .daily,
                          loaded: Bool = true) -> Standing {
        Standing(username: username, contributions: count, window: window,
                 lastUpdated: loaded ? loadedAt : .distantPast, state: loaded ? .loaded : .loading)
    }

    private func summary(
        _ competitors: [Competitor], _ standings: [Standing], window: ContributionWindow = .daily,
        displayName: String? = "Addison Kowalski", deltas: [String: Int] = [:], streaks: [String: Int] = [:]
    ) -> BoardSummary? {
        BoardSummary.make(
            competitors: competitors,
            standings: Dictionary(uniqueKeysWithValues: standings.map { ($0.username, $0) }),
            window: window, displayName: displayName,
            rankDelta: { deltas[$0] }, streak: { streaks[$0] }, lastUpdated: loadedAt
        )
    }

    @Test func showsYourRankAmongEveryoneAndYourContributions() {
        let result = summary([me, ada, lin], [standing("me", 7), standing("ada", 12), standing("lin", 2)])
        #expect(result?.rank == 2)
        #expect(result?.competitorCount == 3)
        #expect(result?.contributions == 7)
        #expect(result?.firstName == "Addison")
        #expect(result?.username == "me")
        #expect(result?.accessibilityDescription == "You, @me, rank 2 of 3, 7 contributions for today, 5 to pass ada")
    }

    /// The same line Live rank shows: the gap to the person directly above you.
    @Test func saysHowManyToPassThePersonAhead() {
        let result = summary([me, ada, lin], [standing("me", 7), standing("ada", 12), standing("lin", 2)])
        #expect(result?.passLine == "5 to pass ada")
    }

    @Test func nobodyToPassInFirst() {
        let result = summary([me, ada], [standing("me", 12), standing("ada", 7)])
        #expect(result?.rank == 1)
        #expect(result?.passLine == nil)
    }

    /// Someone loading for the first time has no count yet, so they never rank above you, even
    /// against your real zero, and there's no gap to them.
    @Test func noGapToSomeoneWithoutACount() {
        let result = summary([me, ada], [standing("ada", 0, loaded: false), standing("me", 0)])
        #expect(result?.rank == 1)
        #expect(result?.passLine == nil)
    }

    @Test func tiesKeepRosterOrderLikeTheRows() {
        let result = summary([me, ada], [standing("me", 5), standing("ada", 5)])
        #expect(result?.rank == 1)
    }

    @Test func noRankOrFakeZeroBeforeYourContributionsLoad() {
        let result = summary([me, ada], [standing("ada", 4), standing("me", 0, loaded: false)])
        #expect(result?.rank == nil)
        #expect(result?.contributions == nil)
        #expect(result?.accessibilityDescription == "You, @me, contributions not loaded yet")
    }

    @Test func standingsFromAnotherWindowDontCount() {
        let result = summary([me, ada], [standing("me", 9, .weekly), standing("ada", 4, .weekly)], window: .daily)
        #expect(result?.contributions == nil)
        #expect(result?.rank == nil)
    }

    @Test func aloneOnTheBoardShowsContributionsWithoutARank() {
        let result = summary([me], [standing("me", 3)])
        #expect(result?.rank == nil)
        #expect(result?.contributions == 3)
    }

    @Test func movementShowsOnlyOnToday() {
        let today = summary([me, ada], [standing("me", 9), standing("ada", 4)], deltas: ["me": 1])
        #expect(today?.movementToday == 1)
        #expect(today?.accessibilityDescription.hasSuffix("up 1 place today") == true)
        let week = summary([me, ada], [standing("me", 9, .weekly), standing("ada", 4, .weekly)],
                           window: .weekly, deltas: ["me": 1])
        #expect(week?.movementToday == nil)
    }

    /// This month gets Today's chevrons and says which day of the month it is (local calendar).
    @Test func thisMonthShowsMovementAndWhichDayItIs() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        // 03:00 UTC on December 1 is still November 30 in Los Angeles.
        let today = Date(timeIntervalSince1970: 1_796_094_000)
        let result = BoardSummary.make(
            competitors: [me, ada],
            standings: ["me": standing("me", 9, .month), "ada": standing("ada", 4, .month)],
            window: .month, displayName: nil, rankDelta: { ["me": 1][$0] }, lastUpdated: loadedAt,
            today: today, calendar: calendar
        )
        #expect(result?.movementToday == 1)
        #expect(result?.dayOfMonth == "Day 30 of 30")
        #expect(result?.accessibilityDescription
            == "You, @me, rank 1 of 2, 9 contributions for this month, day 30 of 30, up 1 place today")
        #expect(summary([me], [standing("me", 3)])?.dayOfMonth == nil)
    }

    @Test func noProfileNameFallsBackToTheHandle() {
        #expect(summary([me], [], displayName: nil)?.firstName == nil)
    }

    @Test func noSummaryUntilYouAreOnTheBoard() {
        #expect(summary([], []) == nil)
        #expect(summary([ada], [standing("ada", 1)]) == nil)
    }

    @Test func showsYourStreakOnEveryWindow() {
        let today = summary([me, ada], [standing("me", 9), standing("ada", 4)], deltas: ["me": 1], streaks: ["me": 12])
        #expect(today?.streak == 12)
        #expect(today?.accessibilityDescription == "You, @me, rank 1 of 2, 9 contributions for today, 12-day streak, up 1 place today")
        let week = summary([me, ada], [standing("me", 9, .weekly), standing("ada", 4, .weekly)],
                           window: .weekly, streaks: ["me": 400])
        #expect(week?.streak == 400)
        #expect(week?.accessibilityDescription.contains("365-plus-day streak") == true)
    }

    @Test func aOneDayStreakIsNotRead() {
        let result = summary([me], [standing("me", 3)], streaks: ["me": 1])
        #expect(result?.accessibilityDescription.contains("streak") == false)
    }

    /// A failed or first load is no count, so it can't say anything about your streak.
    @Test func noStreakBeforeYourContributionsLoad() {
        let result = summary([me, ada], [standing("ada", 4), standing("me", 0, loaded: false)], streaks: ["me": 12])
        #expect(result?.streak == nil)
        #expect(result?.accessibilityDescription == "You, @me, contributions not loaded yet")
    }

    /// On Final standings the card matches the Mac's: your total and where you finished in the
    /// finished month, with your streak, and no movement or gap (the month is over).
    @Test func finalStandingsShowYourTotalAndResultForTheMonth() {
        let october = CalendarMonth(year: 2026, month: 10)
        func history(_ total: Int) -> ContributionHistory {
            ContributionHistory(days: ["2026-09-30": 0, "2026-10-01": 0, "2026-10-15": total, "2026-11-01": 4],
                                timeZone: .gmt)
        }
        let finals = FinalStandings(month: october, competitors: [me, ada, lin],
                                    histories: ["me": history(30), "ada": history(51), "lin": history(10)])
        let result = BoardSummary.make(finals: finals, displayName: "Addison Kowalski", streak: { ["me": 12][$0] },
                                       lastUpdated: loadedAt)
        #expect(result?.rank == 2)
        #expect(result?.competitorCount == 3)
        #expect(result?.contributions == 30)
        #expect(result?.period == "October")
        #expect(result?.streak == 12)
        #expect(result?.movementToday == nil)
        #expect(result?.passLine == nil)
        #expect(result?.dayOfMonth == nil)
        #expect(result?.accessibilityDescription
            == "You, @me, finished 2 of 3 in October, 30 contributions in October, 12-day streak")
    }
}

