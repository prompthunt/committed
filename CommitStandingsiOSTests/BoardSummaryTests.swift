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
        displayName: String? = "Addison Kowalski", deltas: [String: Int] = [:]
    ) -> BoardSummary? {
        BoardSummary.make(
            competitors: competitors,
            standings: Dictionary(uniqueKeysWithValues: standings.map { ($0.username, $0) }),
            window: window, displayName: displayName,
            rankDelta: { deltas[$0] }, lastUpdated: loadedAt
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

    /// Someone loading for the first time has no count yet, so there's no gap to them.
    @Test func noGapToSomeoneWithoutACount() {
        let result = summary([ada, me], [standing("ada", 0, loaded: false), standing("me", 0)])
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

    @Test func noProfileNameFallsBackToTheHandle() {
        #expect(summary([me], [], displayName: nil)?.firstName == nil)
    }

    @Test func noSummaryUntilYouAreOnTheBoard() {
        #expect(summary([], []) == nil)
        #expect(summary([ada], [standing("ada", 1)]) == nil)
    }
}
