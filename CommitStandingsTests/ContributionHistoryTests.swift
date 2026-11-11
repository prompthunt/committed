import Testing
import Foundation
@testable import CommitStandings

/// `ContributionHistory`: one person's daily counts and the time zone they were read in. Window
/// totals come from it alone, as of an injected date in its own time zone, never the machine's.
/// The Windows core runs the same cases in `windows/core/tests/history.rs`.
struct ContributionHistoryTests {

    /// A calendar spanning a year end, a 28-day February, a US DST weekend and a leap day.
    static let calendar: [String: Int] = [
        "2025-12-31": 4,
        "2026-01-01": 1,
        "2026-01-31": 7,
        "2026-02-01": 2,
        "2026-02-28": 3,
        "2026-03-01": 5,
        "2026-03-07": 10,
        "2026-03-08": 20, // US DST starts
        "2026-03-09": 40,
        "2026-05-21": 100, // outside 7 days of 05-28
        "2026-05-22": 1,
        "2026-05-23": 2,
        "2026-05-24": 3,
        "2026-05-25": 4,
        "2026-05-26": 5,
        "2026-05-27": 6,
        "2026-05-28": 7,
        "2026-05-29": 100, // after today: never counted
        "2028-02-29": 9, // leap day
        "2028-03-01": 1,
    ]

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let window: ContributionWindow
        /// Local wall-clock time in `zone`.
        let local: (Int, Int, Int, Int, Int)
        let zone: String
        let expected: Int
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "today only", window: .daily, local: (2026, 5, 28, 12, 0), zone: "UTC", expected: 7),
        Case(name: "today with nothing yet is 0", window: .daily, local: (2026, 5, 30, 9, 0), zone: "UTC", expected: 0),
        Case(name: "7 days inclusive, future ignored", window: .weekly, local: (2026, 5, 28, 12, 0), zone: "UTC", expected: 28),
        Case(name: "30 days spans the month end", window: .monthly, local: (2026, 5, 28, 12, 0), zone: "UTC", expected: 128),
        Case(name: "a minute before midnight is still today", window: .daily, local: (2026, 5, 28, 23, 59), zone: "America/Los_Angeles", expected: 7),
        Case(name: "midnight starts the next day", window: .daily, local: (2026, 5, 29, 0, 0), zone: "America/Los_Angeles", expected: 100),
        Case(name: "new year's day: today", window: .daily, local: (2026, 1, 1, 8, 0), zone: "Asia/Tokyo", expected: 1),
        Case(name: "new year's day: 7 days reaches back into December", window: .weekly, local: (2026, 1, 1, 8, 0), zone: "Asia/Tokyo", expected: 5),
        Case(name: "Jan 31 to Feb 1: 7 days", window: .weekly, local: (2026, 2, 1, 12, 0), zone: "Europe/Berlin", expected: 9),
        Case(name: "Mar 1 after a 28-day February: 7 days", window: .weekly, local: (2026, 3, 1, 12, 0), zone: "UTC", expected: 8),
        Case(name: "Mar 1 after a 28-day February: 30 days reaches Jan 31", window: .monthly, local: (2026, 3, 1, 12, 0), zone: "UTC", expected: 17),
        Case(name: "late on the DST day", window: .daily, local: (2026, 3, 8, 23, 30), zone: "America/Los_Angeles", expected: 20),
        Case(name: "just after midnight following the DST day", window: .weekly, local: (2026, 3, 9, 0, 30), zone: "America/Los_Angeles", expected: 70),
        Case(name: "leap day", window: .daily, local: (2028, 2, 29, 12, 0), zone: "Australia/Adelaide", expected: 9),
        Case(name: "7 days across a leap day", window: .weekly, local: (2028, 3, 1, 12, 0), zone: "UTC", expected: 10),
    ]

    @Test(arguments: cases)
    func windowTotal(_ c: Case) throws {
        let zone = try #require(TimeZone(identifier: c.zone))
        let history = ContributionHistory(days: Self.calendar, timeZone: zone)
        let asOf = try Self.instant(c.local, in: zone)
        #expect(history.total(for: c.window, asOf: asOf) == c.expected)
    }

    /// The same instant is a different day in Tokyo and Los Angeles: each history uses the zone
    /// it was read in, so Today differs.
    @Test func sameInstantIsADifferentDayInEachHistorysOwnTimeZone() throws {
        let instant = try Self.instant((2026, 5, 28, 15, 30), in: TimeZone(identifier: "UTC")!)
        let tokyo = ContributionHistory(days: Self.calendar, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let losAngeles = ContributionHistory(days: Self.calendar, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(tokyo.total(for: .daily, asOf: instant) == 100)
        #expect(losAngeles.total(for: .daily, asOf: instant) == 7)
    }

    @Test func aCalendarShorterThanTheWindowSumsWhatItHas() {
        let utc = TimeZone(identifier: "UTC")!
        let short = ContributionHistory(days: ["2026-05-27": 2, "2026-05-28": 3], timeZone: utc)
        let asOf = Date(timeIntervalSince1970: 1_779_969_600) // 2026-05-28 12:00 UTC
        #expect(short.total(for: .monthly, asOf: asOf) == 5)
        #expect(ContributionHistory(days: [:], timeZone: utc).total(for: .weekly, asOf: asOf) == 0)
    }

    // MARK: This month

    /// 31-, 30-, 28- and 29-day months, each one's 1st, and a US DST weekend.
    static let months: [String: Int] = [
        "2025-12-31": 4,
        "2026-01-01": 1,
        "2026-01-31": 7,
        "2026-02-01": 2,
        "2026-02-28": 3,
        "2026-03-01": 5,
        "2026-03-08": 20, // US DST starts
        "2026-03-09": 40,
        "2026-03-31": 8,
        "2026-04-01": 3,
        "2026-04-30": 6,
        "2026-05-01": 50,
        "2028-02-01": 1,
        "2028-02-29": 9, // leap day
        "2028-03-01": 1,
    ]

    static let monthCases: [Case] = [
        Case(name: "the 1st counts only the 1st", window: .month, local: (2026, 4, 1, 12, 0), zone: "UTC", expected: 3),
        Case(name: "later days in the month never count", window: .month, local: (2026, 3, 8, 12, 0), zone: "UTC", expected: 25),
        Case(name: "31-day month, last day, not December's", window: .month, local: (2026, 1, 31, 20, 0), zone: "Asia/Tokyo", expected: 8),
        Case(name: "28-day February, last day", window: .month, local: (2026, 2, 28, 12, 0), zone: "Europe/Berlin", expected: 5),
        Case(name: "29-day February in a leap year", window: .month, local: (2028, 2, 29, 12, 0), zone: "Australia/Adelaide", expected: 10),
        Case(name: "the 1st after a leap day", window: .month, local: (2028, 3, 1, 12, 0), zone: "UTC", expected: 1),
        Case(name: "30-day month, a minute before midnight", window: .month, local: (2026, 4, 30, 23, 59), zone: "America/Los_Angeles", expected: 9),
        Case(name: "midnight on the 1st resets to zero plus the 1st", window: .month, local: (2026, 5, 1, 0, 0), zone: "America/Los_Angeles", expected: 50),
        Case(name: "the month across a DST change", window: .month, local: (2026, 3, 9, 0, 30), zone: "America/Los_Angeles", expected: 65),
    ]

    @Test(arguments: monthCases)
    func thisMonthTotal(_ c: Case) throws {
        let zone = try #require(TimeZone(identifier: c.zone))
        let history = ContributionHistory(days: Self.months, timeZone: zone)
        #expect(history.total(for: c.window, asOf: try Self.instant(c.local, in: zone)) == c.expected)
    }

    /// 03:00 UTC on February 1 is still January 31 in Los Angeles: This month is January there and
    /// February in Tokyo.
    @Test func thisMonthIsTheMonthInTheHistorysOwnTimeZone() throws {
        let instant = try Self.instant((2026, 2, 1, 3, 0), in: TimeZone(identifier: "UTC")!)
        let losAngeles = ContributionHistory(days: Self.months, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let tokyo = ContributionHistory(days: Self.months, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(losAngeles.total(for: .month, asOf: instant) == 8)
        #expect(tokyo.total(for: .month, asOf: instant) == 2)
    }

    struct DayCase: CustomTestStringConvertible, Sendable {
        let local: (Int, Int, Int, Int, Int)
        let zone: String
        let expected: String
        var testDescription: String { expected }
    }

    /// "Day 10 of 30" beside This month: the day of the local month and how many days it has.
    @Test(arguments: [
        DayCase(local: (2026, 11, 10, 9, 0), zone: "UTC", expected: "Day 10 of 30"),
        DayCase(local: (2026, 2, 1, 0, 0), zone: "Europe/Berlin", expected: "Day 1 of 28"),
        DayCase(local: (2028, 2, 29, 12, 0), zone: "Australia/Adelaide", expected: "Day 29 of 29"),
        DayCase(local: (2026, 1, 31, 23, 59), zone: "Asia/Tokyo", expected: "Day 31 of 31"),
        DayCase(local: (2026, 11, 30, 19, 0), zone: "America/Los_Angeles", expected: "Day 30 of 30"),
    ])
    func thisMonthSaysWhichDayItIs(_ c: DayCase) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: c.zone))
        let asOf = try Self.instant(c.local, in: calendar.timeZone)
        #expect(ContributionWindow.month.dayOfMonth(asOf: asOf, calendar: calendar) == c.expected)
    }

    @Test func onlyThisMonthSaysWhichDayItIs() {
        for window in [ContributionWindow.daily, .weekly, .monthly] {
            #expect(window.dayOfMonth(asOf: Date(timeIntervalSince1970: 1_794_000_000), calendar: .current) == nil)
        }
    }

    @Test func thirtyDaysKeepsItsSavedRawValueAndThisMonthHasItsOwn() {
        #expect(ContributionWindow(rawValue: "monthly") == .monthly)
        #expect(ContributionWindow.monthly.shortTitle == "30 days")
        #expect(ContributionWindow(rawValue: "month") == .month)
        #expect(ContributionWindow.month.shortTitle == "This month")
        #expect(ContributionWindow.allCases == [.daily, .weekly, .monthly, .month])
    }

    @Test func roundTripsThroughJSONWithItsTimeZone() throws {
        let history = ContributionHistory(days: ["2026-05-28": 7], timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let decoded = try JSONDecoder().decode(ContributionHistory.self, from: JSONEncoder().encode(history))
        #expect(decoded == history)
        #expect(decoded.timeZone.identifier == "Asia/Tokyo")
    }

    // MARK: Current streak

    /// Days in a row with at least one contribution, counted back from today, or from yesterday
    /// while today has none yet (a day not on the calendar yet counts as none).
    struct StreakCase: CustomTestStringConvertible, Sendable {
        let name: String
        let days: [String: Int]
        /// Local wall-clock time in `zone`.
        let local: (Int, Int, Int, Int, Int)
        let zone: String
        let expected: Int
        var testDescription: String { name }
    }

    /// `count` consecutive days ending on `last` ("YYYY-MM-DD"), each with `value` contributions.
    static func run(_ count: Int, endingOn last: String, value: Int = 1) -> [String: Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = last.split(separator: "-").compactMap { Int($0) }
        let end = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
        var days: [String: Int] = [:]
        for offset in 0..<count {
            let day = calendar.date(byAdding: .day, value: -offset, to: end)!
            days[ContributionHistory.key(for: day, in: calendar)] = value
        }
        return days
    }

    static func merged(_ parts: [String: Int]...) -> [String: Int] {
        parts.reduce(into: [:]) { result, part in result.merge(part) { _, new in new } }
    }

    static let streakCases: [StreakCase] = [
        StreakCase(name: "today counts once you've contributed",
                   days: run(3, endingOn: "2026-05-28"), local: (2026, 5, 28, 12, 0), zone: "UTC", expected: 3),
        StreakCase(name: "alive through today while today is still zero",
                   days: merged(run(2, endingOn: "2026-05-27"), ["2026-05-28": 0]),
                   local: (2026, 5, 28, 12, 0), zone: "UTC", expected: 2),
        StreakCase(name: "alive through today when the calendar doesn't reach today yet",
                   days: run(2, endingOn: "2026-05-27"), local: (2026, 5, 28, 8, 0), zone: "UTC", expected: 2),
        StreakCase(name: "broken when yesterday and today are both empty",
                   days: merged(run(4, endingOn: "2026-05-26"), ["2026-05-27": 0, "2026-05-28": 0]),
                   local: (2026, 5, 28, 12, 0), zone: "UTC", expected: 0),
        StreakCase(name: "an empty day ends it",
                   days: merged(run(3, endingOn: "2026-05-22", value: 9), ["2026-05-23": 0], run(5, endingOn: "2026-05-28")),
                   local: (2026, 5, 28, 12, 0), zone: "UTC", expected: 5),
        StreakCase(name: "a minute before midnight it's still alive",
                   days: merged(run(2, endingOn: "2026-05-27"), ["2026-05-28": 0]),
                   local: (2026, 5, 28, 23, 59), zone: "America/Los_Angeles", expected: 2),
        StreakCase(name: "midnight breaks it when the day ended empty",
                   days: merged(run(2, endingOn: "2026-05-27"), ["2026-05-28": 0]),
                   local: (2026, 5, 29, 0, 0), zone: "America/Los_Angeles", expected: 0),
        StreakCase(name: "midnight keeps it when the day ended with a contribution",
                   days: run(3, endingOn: "2026-05-28"),
                   local: (2026, 5, 29, 0, 1), zone: "America/Los_Angeles", expected: 3),
        StreakCase(name: "across the day the clocks go forward",
                   days: run(3, endingOn: "2026-03-09"), local: (2026, 3, 9, 0, 30), zone: "America/Los_Angeles", expected: 3),
        StreakCase(name: "across the day the clocks go back",
                   days: run(3, endingOn: "2026-11-02"), local: (2026, 11, 2, 23, 30), zone: "America/Los_Angeles", expected: 3),
        StreakCase(name: "across a leap day",
                   days: run(3, endingOn: "2028-03-01"), local: (2028, 3, 1, 12, 0), zone: "Australia/Adelaide", expected: 3),
        StreakCase(name: "across a 28-day February",
                   days: run(3, endingOn: "2026-03-01"), local: (2026, 3, 1, 12, 0), zone: "UTC", expected: 3),
        StreakCase(name: "across the new year",
                   days: run(4, endingOn: "2026-01-02"), local: (2026, 1, 2, 9, 0), zone: "Asia/Tokyo", expected: 4),
        StreakCase(name: "days after today never count",
                   days: run(5, endingOn: "2026-05-30"), local: (2026, 5, 28, 12, 0), zone: "UTC", expected: 3),
        StreakCase(name: "a calendar shorter than a year counts what it has",
                   days: run(2, endingOn: "2026-05-28"), local: (2026, 5, 28, 12, 0), zone: "UTC", expected: 2),
        StreakCase(name: "every day of GitHub's calendar",
                   days: run(371, endingOn: "2026-05-28"), local: (2026, 5, 28, 12, 0), zone: "UTC", expected: 371),
        StreakCase(name: "no days at all",
                   days: [:], local: (2026, 5, 28, 12, 0), zone: "UTC", expected: 0),
    ]

    @Test(arguments: streakCases)
    func currentStreak(_ c: StreakCase) throws {
        let zone = try #require(TimeZone(identifier: c.zone))
        let history = ContributionHistory(days: c.days, timeZone: zone)
        #expect(history.currentStreak(asOf: try Self.instant(c.local, in: zone)) == c.expected)
    }

    /// The same instant is Thursday evening in Los Angeles and already Friday in Tokyo: each
    /// history's own day decides whether today is still to come.
    @Test func streakUsesEachHistorysOwnDay() throws {
        let instant = try Self.instant((2026, 5, 29, 3, 0), in: TimeZone(identifier: "UTC")!)
        let days = Self.merged(Self.run(3, endingOn: "2026-05-27"), ["2026-05-28": 0])
        let losAngeles = ContributionHistory(days: days, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let tokyo = ContributionHistory(days: days, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(losAngeles.currentStreak(asOf: instant) == 3) // still the 28th: alive
        #expect(tokyo.currentStreak(asOf: instant) == 0) // the 29th: the 28th ended empty
    }

    static func instant(_ local: (Int, Int, Int, Int, Int), in zone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: local.0, month: local.1, day: local.2, hour: local.3, minute: local.4)
        return try #require(calendar.date(from: components))
    }
}
