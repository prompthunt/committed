import Testing
import Foundation
@testable import CommitStandings

/// The person view's content (`StandingsStore.person`): one Competitor's month day by day beside
/// last month, their streaks, active days and past finishes, from saved calendars. The iPhone sheet
/// or pane and the Mac window (#102) draw exactly this; the Windows core's `BoardCore::person`
/// follows the same rules.
@MainActor
struct PersonSummaryTests {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// Noon UTC on `day` ("YYYY-MM-DD").
    static func noon(_ day: String) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }

    static func store(owner: String = "me", rivals: [String], histories: [String: ContributionHistory])
        -> StandingsStore {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: owner, members: rivals)
        store.updateHistories(histories)
        return store
    }

    static func history(from first: String = "2026-09-14", through last: String, _ counts: [String: Int])
        -> ContributionHistory {
        FinalStandingsTests.history(from: first, through: last, counts)
    }

    /// November 22: Ana's November so far beside her whole October.
    static let ana = history(through: "2026-11-22", [
        "2026-10-01": 7, "2026-10-29": 1, "2026-10-30": 4, "2026-10-31": 5,
        "2026-11-01": 3, "2026-11-08": 41, "2026-11-20": 1, "2026-11-21": 2, "2026-11-22": 3,
    ])

    @Test func barsStreaksAndActiveDaysForThisMonth() throws {
        let store = Self.store(rivals: ["ana"], histories: ["me": Self.history(through: "2026-11-22", [:]), "ana": Self.ana])
        let person = try #require(store.person("ana", asOf: Self.noon("2026-11-22"), calendar: Self.utc))
        let days = try #require(person.days)

        #expect(person.month == CalendarMonth(year: 2026, month: 11))
        #expect(person.lastMonth == CalendarMonth(year: 2026, month: 10))
        #expect(person.dayOfMonth == 22)
        #expect(person.daysInMonth == 30)
        // The 1st through today: nothing after today.
        #expect(days.thisMonth == [3, 0, 0, 0, 0, 0, 0, 41, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3])
        // Every day of October, the 31st too, under a 30-day November.
        #expect(days.lastMonth.count == 31)
        #expect(days.lastMonth.first == 7)
        #expect(days.lastMonth.suffix(3) == [1, 4, 5])
        #expect(days.thisMonth.reduce(0, +) == 50) // the row's This month count
        #expect(days.lastMonth.reduce(0, +) == 17)
        #expect(days.currentStreak == 3)
        #expect(days.longestStreak == 4) // October 29 through November 1
        #expect(days.activeDays == 5)
        #expect(person.activeDaysText == "5 of 22")
        #expect(person.isYou == false)
        #expect(person.profileURL == URL(string: "https://github.com/ana"))
    }

    @Test func voiceOverSummarizesTheChartAndReadsEachBar() throws {
        let store = Self.store(rivals: ["ana"], histories: ["me": Self.history(through: "2026-11-22", [:]), "ana": Self.ana])
        let person = try #require(store.person("ana", asOf: Self.noon("2026-11-22"), calendar: Self.utc))
        #expect(person.chartSummary == "5 active days this month, most on November 8 with 41")
        #expect(person.bar(day: 8)?.label == "November 8")
        #expect(person.bar(day: 8)?.value == "41 contributions. October 8: 0")
        #expect(person.bar(day: 1)?.value == "3 contributions. October 1: 7")
        #expect(person.bar(day: 23) == nil) // after today
        #expect(person.selectedDayText(1) == "November 1 · 3 contributions")
        #expect(person.selectedDayComparison(1) == "October 1 · 7")

        let quiet = try #require(store.person("me", asOf: Self.noon("2026-11-22"), calendar: Self.utc))
        #expect(quiet.chartSummary == "No contributions yet this month")
        #expect(quiet.days?.activeDays == 0)
        #expect(quiet.isYou)
    }

    @Test func oneActiveDayReadsSingular() throws {
        let store = Self.store(rivals: [], histories: ["me": Self.history(through: "2026-11-03", ["2026-11-02": 1])])
        let person = try #require(store.person("me", asOf: Self.noon("2026-11-03"), calendar: Self.utc))
        #expect(person.chartSummary == "1 active day this month, most on November 2 with 1")
        #expect(person.bar(day: 2)?.value == "1 contribution. October 2: 0")
    }

    @Test func pastFinishesNewestFirstWithMedalsAndTheYearWhenItDiffers() throws {
        let store = Self.store(rivals: ["ana"], histories: [
            "me": Self.history(from: "2025-11-20", through: "2026-02-10", ["2025-12-05": 10, "2026-01-05": 5]),
            "ana": Self.history(from: "2025-11-20", through: "2026-02-10", ["2025-12-06": 20]),
        ])
        let me = try #require(store.person("me", asOf: Self.noon("2026-02-10"), calendar: Self.utc))
        let finishes = try #require(me.days?.finishes)
        #expect(finishes.map(\.month) == [CalendarMonth(year: 2026, month: 1), CalendarMonth(year: 2025, month: 12)])
        #expect(finishes.map { me.finishName($0) } == ["January", "December 2025"])
        #expect(finishes.map(\.rank) == [1, 2])
        #expect(finishes.map(\.of) == [2, 2])
        #expect(finishes.map(\.contributions) == [5, 10])
        #expect(finishes.map(\.medal) == [.gold, .silver])
        #expect(me.finishSpoken(finishes[1]) == "December 2025: #2 of 2, 10 contributions, silver medal")

        let ana = try #require(store.person("ana", asOf: Self.noon("2026-02-10"), calendar: Self.utc))
        // A zero month ranks but never earns a medal.
        #expect(ana.days?.finishes.map(\.medal) == [nil, .gold])
        #expect(ana.finishSpoken(try #require(ana.days?.finishes.first)) == "January: #2 of 2, 0 contributions")
    }

    @Test func waitsInsteadOfDrawingZerosBeforeTheCountLoads() throws {
        let store = Self.store(rivals: ["bo", "cy"], histories: ["me": Self.history(through: "2026-11-22", [:])])
        store.updateStanding(Standing(username: "cy", contributions: 0, window: store.selectedWindow,
                                      lastUpdated: .distantPast, state: .failed("offline")))
        let bo = try #require(store.person("bo", asOf: Self.noon("2026-11-22"), calendar: Self.utc))
        #expect(bo.days == nil)
        #expect(bo.chartSummary == nil)
        #expect(bo.status == .loading)
        #expect(bo.waitingTitle == "Waiting for bo’s count")
        #expect(bo.waitingDetail == "Their month appears once the next refresh loads it.")
        #expect(bo.dayOfMonth == 22)

        let cy = try #require(store.person("cy", asOf: Self.noon("2026-11-22"), calendar: Self.utc))
        #expect(cy.status == .failed)
        #expect(cy.waitingDetail == "GitHub didn’t answer the last refresh. Committed tries again on the next one.")
    }

    @Test func aFailedRefreshStillShowsTheSavedMonth() throws {
        let store = Self.store(rivals: ["ana"], histories: ["me": Self.history(through: "2026-11-22", [:]), "ana": Self.ana])
        store.updateStanding(Standing(username: "ana", contributions: 50, window: store.selectedWindow,
                                      lastUpdated: Self.noon("2026-11-21"), state: .failed("offline")))
        let person = try #require(store.person("ana", asOf: Self.noon("2026-11-22"), calendar: Self.utc))
        #expect(person.status == .failed)
        #expect(person.days?.currentStreak == 3)
    }

    @Test func nobodyHiddenOrOffTheBoardHasAPersonView() {
        let store = Self.store(rivals: ["ana"], histories: ["me": Self.history(through: "2026-11-22", [:]), "ana": Self.ana])
        store.setHidden(true, username: "ana")
        #expect(store.person("ana", asOf: Self.noon("2026-11-22"), calendar: Self.utc) == nil)
        #expect(store.person("zed", asOf: Self.noon("2026-11-22"), calendar: Self.utc) == nil)
    }

    @Test(arguments: [(0, "0 days"), (1, "1 day"), (12, "12 days"), (365, "365 days"), (366, "365+ days"), (371, "365+ days")])
    func streakStatsReadInDays(_ streak: Int, _ text: String) {
        #expect(PersonSummary.streakText(streak) == text)
    }

    // MARK: One streak tile

    @Test(arguments: [
        (14, 24, "14 days", "Best 24 days", "14 days, best 24 days"),
        (47, 47, "47 days", "Longest in the past year", "47 days, longest in the past year"),
        (0, 12, "None", "Best 12 days", "None, best 12 days"),
        (0, 0, "None", "No streaks in the past year", "None, no streaks in the past year"),
        (371, 371, "365+ days", "Longest in the past year", "365-plus days, longest in the past year"),
    ])
    func oneStreakTileNamesTheLongestOnlyWhenItDiffers(_ current: Int, _ longest: Int, _ value: String,
                                                      _ caption: String, _ spoken: String) {
        #expect(PersonSummary.streakValue(current) == value)
        #expect(PersonSummary.streakCaption(current: current, longest: longest) == caption)
        #expect(PersonSummary.streakSpoken(current: current, longest: longest) == spoken)
    }

    // MARK: The race with you

    /// Me and Odile on November 10: I lead the first week, she passes me on the 8th.
    static func raceStore() -> StandingsStore {
        let mine = [3, 6, 10, 4, 4, 6, 7, 3, 7, 7]
        let hers = [2, 4, 6, 3, 5, 4, 12, 9, 8, 9]
        func days(_ counts: [Int]) -> [String: Int] {
            Dictionary(uniqueKeysWithValues: counts.enumerated().map {
                (String(format: "2026-11-%02d", $0.offset + 1), $0.element)
            })
        }
        return store(rivals: ["odile"], histories: [
            "me": history(through: "2026-11-10", days(mine).merging(["2026-10-05": 4]) { a, _ in a }),
            "odile": history(through: "2026-11-10", days(hers).merging(["2026-10-06": 9]) { a, _ in a }),
        ])
    }

    @Test func aRivalsViewLeadsWithTheRaceThisMonth() throws {
        let person = try #require(Self.raceStore().person("odile", asOf: Self.noon("2026-11-10"), calendar: Self.utc))
        let race = try #require(person.race)
        #expect(race.month == CalendarMonth(year: 2026, month: 11))
        #expect(race.isFinal == false)
        #expect(race.yours == [3, 9, 19, 23, 27, 33, 40, 43, 50, 57])
        #expect(race.theirs == [2, 6, 12, 15, 20, 24, 36, 45, 53, 62])
        #expect(race.story == .passed(.them, day: 8, changes: 1))
        #expect(person.raceTitle == "You vs odile · November")
        #expect(person.raceHeadline == "5 to pass odile")
        #expect(person.raceHeadlineNumber == "5")
        #expect(person.raceStory == "odile passed you on November 8")
        #expect(person.raceSpoken == "You vs odile, November. 5 to pass odile. odile passed you on November 8. odile 62, you 57.")
    }

    @Test func yourOwnViewHasNoRace() throws {
        let me = try #require(Self.raceStore().person("me", asOf: Self.noon("2026-11-10"), calendar: Self.utc))
        #expect(me.race == nil)
        #expect(me.raceHeadline == nil)
    }

    @Test func noRaceUntilYourOwnCountLoads() throws {
        let store = Self.store(rivals: ["ana"], histories: ["ana": Self.ana])
        let ana = try #require(store.person("ana", asOf: Self.noon("2026-11-22"), calendar: Self.utc))
        #expect(ana.days != nil)
        #expect(ana.race == nil)
    }

    @Test func onTheFirstTheRaceIsLastMonthsFinishedOne() throws {
        let store = Self.store(rivals: ["ana"], histories: [
            "me": Self.history(through: "2026-11-01", ["2026-10-03": 10, "2026-10-20": 2]),
            "ana": Self.history(through: "2026-11-01", ["2026-10-10": 30, "2026-11-01": 4]),
        ])
        let ana = try #require(store.person("ana", asOf: Self.noon("2026-11-01"), calendar: Self.utc))
        let race = try #require(ana.race)
        #expect(race.month == CalendarMonth(year: 2026, month: 10))
        #expect(race.isFinal)
        #expect(race.yours.count == 31)
        #expect(race.yourTotal == 12)
        #expect(race.theirTotal == 30)
        #expect(race.story == .passed(.them, day: 10, changes: 1))
        #expect(ana.raceTitle == "You vs ana · October final")
        #expect(ana.raceHeadline == "ana beat you by 18")
        #expect(ana.raceHeadlineNumber == nil)
    }

    @Test(arguments: [
        // [yours], [theirs], story, headline, story line
        ([1, 2, 3], [1, 2, 3], PersonSummary.Story.level, "Level with ana", "Level all month"),
        ([2, 4, 6], [1, 2, 3], .led(.you), "3 ahead of ana", "You’ve led all month"),
        ([1, 2, 3], [2, 4, 6], .led(.them), "3 to pass ana", "ana has led all month"),
        ([0, 0, 1], [0, 2, 3], .pulledAhead(.them, day: 2), "2 to pass ana", "ana pulled ahead on November 2"),
        ([0, 3, 3], [1, 1, 5], .passed(.them, day: 3, changes: 2), "2 to pass ana",
         "ana passed you on November 3 · the lead changed 2 times"),
        ([1, 3, 6], [4, 5, 6], .caught(.you, day: 3), "Level with ana", "You caught ana on November 3"),
    ])
    func theStoryFollowsTheLead(_ yours: [Int], _ theirs: [Int], _ story: PersonSummary.Story,
                                _ headline: String, _ line: String) {
        let race = PersonSummary.Race(month: CalendarMonth(year: 2026, month: 11), isFinal: false,
                                      yours: yours, theirs: theirs)
        let person = PersonSummary(competitor: Competitor(username: "ana", isSelf: false), status: .loaded,
                                   month: CalendarMonth(year: 2026, month: 11), dayOfMonth: 3, days: nil, race: race)
        #expect(race.story == story)
        #expect(person.raceHeadline == headline)
        #expect(person.raceStory == line)
    }

    @Test func pastMonthsShowYourFinishBesideTheirs() throws {
        let store = Self.store(rivals: ["ana"], histories: [
            "me": Self.history(from: "2025-11-20", through: "2026-02-10", ["2025-12-05": 10, "2026-01-05": 5]),
            "ana": Self.history(from: "2025-11-20", through: "2026-02-10", ["2025-12-06": 20]),
        ])
        let ana = try #require(store.person("ana", asOf: Self.noon("2026-02-10"), calendar: Self.utc))
        let finishes = try #require(ana.days?.finishes)
        #expect(finishes.map(\.yourRank) == [1, 2])
        #expect(finishes.map(\.youWereAhead) == [true, false])
        #expect(ana.recordText == "ana 1 · you 1")
        #expect(ana.recordSpoken == "Months finished ahead: ana 1, you 1")
        #expect(ana.finishSpoken(finishes[1]) == "December 2025: #1 of 2, 20 contributions, gold medal, you finished #2")

        let me = try #require(store.person("me", asOf: Self.noon("2026-02-10"), calendar: Self.utc))
        #expect(me.days?.finishes.allSatisfy { $0.yourRank == nil } == true)
        #expect(me.recordText == nil)
    }
}
