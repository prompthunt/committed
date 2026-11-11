import Testing
import Foundation
@testable import CommitStandings

struct ContributionsParserTests {

    // MARK: - Modern format (tooltip-linked)

    @Test func modernFormat_extractsPerDayCounts() throws {
        let html = """
        <table>
          <td data-date="2026-05-22" id="cd-0"></td>
          <td data-date="2026-05-23" id="cd-1"></td>
          <td data-date="2026-05-28" id="cd-2"></td>
        </table>
        <tool-tip for="cd-0" popover="manual">3 contributions on Friday May 22, 2026</tool-tip>
        <tool-tip for="cd-1">No contributions on Saturday May 23, 2026</tool-tip>
        <tool-tip for="cd-2">12 contributions on Thursday May 28, 2026</tool-tip>
        """
        let days = try ContributionsParser.parseDays(html: html)
        #expect(days["2026-05-22"] == 3)
        #expect(days["2026-05-23"] == 0)
        #expect(days["2026-05-28"] == 12)
    }

    @Test func legacyAriaLabel_extractsCount() throws {
        let html = """
        <td data-date="2026-05-28" aria-label="7 contributions on Thursday, May 28, 2026"></td>
        <td data-date="2026-05-27" aria-label="No contributions on Wednesday, May 27, 2026"></td>
        """
        let days = try ContributionsParser.parseDays(html: html)
        #expect(days["2026-05-28"] == 7)
        #expect(days["2026-05-27"] == 0)
    }

    @Test func legacyDataCount_extractsCount() throws {
        let html = #"<td data-date="2026-05-28" data-count="9"></td>"#
        let days = try ContributionsParser.parseDays(html: html)
        #expect(days["2026-05-28"] == 9)
    }

    @Test func parsesCommaSeparatedCount() throws {
        let html = """
        <td data-date="2026-05-28" id="cd-x"></td>
        <tool-tip for="cd-x">1,234 contributions on Thursday May 28, 2026</tool-tip>
        """
        let days = try ContributionsParser.parseDays(html: html)
        #expect(days["2026-05-28"] == 1234)
    }

    @Test func emptyHTML_throwsParseFailed() {
        #expect(throws: ContributionsError.parseFailed("No day cells found")) {
            _ = try ContributionsParser.parseDays(html: "<html></html>")
        }
    }

    @Test func zeroActivity_returnsZeroNotError() throws {
        let html = """
        <td data-date="2026-05-28" id="cd-z"></td>
        <tool-tip for="cd-z">No contributions on Thursday May 28, 2026</tool-tip>
        """
        let utc = TimeZone(identifier: "UTC")!
        let history = try ContributionsParser.parseHistory(html: html, timeZone: utc)
        #expect(history.days == ["2026-05-28": 0])
        let asOf = Date(timeIntervalSince1970: 1_779_969_600) // 2026-05-28 12:00 UTC
        #expect(history.total(for: .weekly, asOf: asOf) == 0)
    }

    /// GitHub's days are civil dates: they're kept as written, whatever the reading time zone,
    /// and the history records the zone so its Windows know which day is today.
    @Test func parseHistory_keepsCivilDaysAndRecordsTheTimeZone() throws {
        let html = #"<td data-date="2026-05-28" data-count="9"></td><td data-date="2026-01-01" data-count="1"></td>"#
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let history = try ContributionsParser.parseHistory(html: html, timeZone: tokyo)
        #expect(history.days == ["2026-05-28": 9, "2026-01-01": 1])
        #expect(history.timeZone == tokyo)
    }

    // MARK: - Trolling

    private static let utc = TimeZone(identifier: "UTC")!

    /// Sixty days before May 28 at a steady 20 a day, so their usual big day is 20, plus `extra`.
    private func steadyHistory(_ count: Int = 20, _ extra: [String: Int] = [:]) -> ContributionHistory {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        var days: [String: Int] = [:]
        for offset in 1...60 {
            days[ContributionHistory.key(for: calendar.date(byAdding: .day, value: -offset, to: ymd(2026, 5, 28))!,
                                         in: calendar)] = count
        }
        days.merge(extra) { $1 }
        return ContributionHistory(days: days, timeZone: Self.utc)
    }

    @Test func trolling_flagsADayFarAboveTheirUsualBigDay() {
        let history = steadyHistory(20, ["2026-05-28": 784])
        let burst = history.burst(for: .daily, asOf: ymd(2026, 5, 28))
        #expect(burst == Burst(day: ymd(2026, 5, 28), count: 784, usual: 20))
        #expect(burst?.multiple == 39)
        #expect(StandingCounts(history: history, window: .daily, asOf: ymd(2026, 5, 28)).burst == burst)
    }

    @Test func trolling_ignoresABusyDayUnderFiveTimesTheirUsual() {
        let history = steadyHistory(40, ["2026-05-28": 200]) // exactly 5×: not over the line
        #expect(history.burst(for: .daily, asOf: ymd(2026, 5, 28)) == nil)
    }

    @Test func trolling_needsMoreThanAHundred() {
        // 50× a quiet account's usual, but not over the floor
        #expect(steadyHistory(2, ["2026-05-28": 100]).burst(for: .daily, asOf: ymd(2026, 5, 28)) == nil)
        #expect(steadyHistory(2, ["2026-05-28": 101]).burst(for: .daily, asOf: ymd(2026, 5, 28))?.count == 101)
    }

    @Test func trolling_newAccountOverTheFloorIsTrolling() {
        let history = ContributionHistory(days: ["2026-05-28": 150], timeZone: Self.utc)
        let burst = history.burst(for: .daily, asOf: ymd(2026, 5, 28))
        #expect(burst == Burst(day: ymd(2026, 5, 28), count: 150, usual: 0))
        #expect(burst?.multiple == nil)
    }

    @Test func trolling_staysInLongerWindowsUntilTheDayLeaves() {
        let history = steadyHistory(20, ["2026-05-25": 500, "2026-05-28": 20])
        let asOf = ymd(2026, 5, 28)
        #expect(history.burst(for: .daily, asOf: asOf) == nil)
        #expect(history.burst(for: .weekly, asOf: asOf)?.count == 500)
        #expect(history.burst(for: .monthly, asOf: asOf)?.day == ymd(2026, 5, 25))
    }

    @Test func trolling_judgesEachDayOnlyAgainstTheDaysBeforeIt() {
        let history = steadyHistory(20, ["2026-05-27": 300, "2026-05-28": 5_000])
        // The later huge day doesn't raise the bar for the earlier one…
        #expect(history.burst(for: .daily, asOf: ymd(2026, 5, 27))
            == Burst(day: ymd(2026, 5, 27), count: 300, usual: 20))
        // …and a window with two reports the bigger.
        #expect(history.burst(for: .weekly, asOf: ymd(2026, 5, 28))
            == Burst(day: ymd(2026, 5, 28), count: 5_000, usual: 20))
    }

    @Test func usualBigDay_isTheNinetiethPercentileOfActiveDays() {
        #expect(TrollCheck.usualBigDay([]) == 0)
        #expect(TrollCheck.usualBigDay([0, 0]) == 0)
        #expect(TrollCheck.usualBigDay(Array(1...10)) == 10)
        #expect(TrollCheck.usualBigDay([0] + Array(1...20)) == 19)
    }

    /// Midnight UTC on that day.
    func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        return calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }
}
