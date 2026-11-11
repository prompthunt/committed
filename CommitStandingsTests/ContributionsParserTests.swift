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
        #expect(days[ymd(2026, 5, 22)] == 3)
        #expect(days[ymd(2026, 5, 23)] == 0)
        #expect(days[ymd(2026, 5, 28)] == 12)
    }

    @Test func legacyAriaLabel_extractsCount() throws {
        let html = """
        <td data-date="2026-05-28" aria-label="7 contributions on Thursday, May 28, 2026"></td>
        <td data-date="2026-05-27" aria-label="No contributions on Wednesday, May 27, 2026"></td>
        """
        let days = try ContributionsParser.parseDays(html: html)
        #expect(days[ymd(2026, 5, 28)] == 7)
        #expect(days[ymd(2026, 5, 27)] == 0)
    }

    @Test func legacyDataCount_extractsCount() throws {
        let html = #"<td data-date="2026-05-28" data-count="9"></td>"#
        let days = try ContributionsParser.parseDays(html: html)
        #expect(days[ymd(2026, 5, 28)] == 9)
    }

    @Test func parsesCommaSeparatedCount() throws {
        let html = """
        <td data-date="2026-05-28" id="cd-x"></td>
        <tool-tip for="cd-x">1,234 contributions on Thursday May 28, 2026</tool-tip>
        """
        let days = try ContributionsParser.parseDays(html: html)
        #expect(days[ymd(2026, 5, 28)] == 1234)
    }

    @Test func emptyHTML_throwsParseFailed() {
        #expect(throws: ContributionsError.parseFailed("No day cells found")) {
            _ = try ContributionsParser.parseDays(html: "<html></html>")
        }
    }

    // MARK: - Windows

    @Test func dailyWindow_includesOnlyToday() {
        let days: [Date: Int] = [
            ymd(2026, 5, 27): 100,
            ymd(2026, 5, 28): 7
        ]
        let asOf = ymd(2026, 5, 28)
        #expect(ContributionsParser.sum(days: days, window: .daily, asOf: asOf) == 7)
    }

    @Test func weeklyWindow_includesTodayAndPriorSix() {
        // asOf 2026-05-28; window is 05-22..05-28 inclusive.
        let days: [Date: Int] = [
            ymd(2026, 5, 21): 100, // outside window (day 8)
            ymd(2026, 5, 22): 1,
            ymd(2026, 5, 23): 2,
            ymd(2026, 5, 24): 3,
            ymd(2026, 5, 25): 4,
            ymd(2026, 5, 26): 5,
            ymd(2026, 5, 27): 6,
            ymd(2026, 5, 28): 7,
            ymd(2026, 5, 29): 100 // outside window (future)
        ]
        let asOf = ymd(2026, 5, 28)
        #expect(ContributionsParser.sum(days: days, window: .weekly, asOf: asOf) == 28)
    }

    @Test func monthlyWindow_includesTodayAndPriorTwentyNine() {
        let asOf = ymd(2026, 5, 30)
        let days: [Date: Int] = [
            ymd(2026, 4, 30): 100, // outside 30-day trailing window
            ymd(2026, 5, 1): 1,
            ymd(2026, 5, 15): 2,
            ymd(2026, 5, 30): 3,
            ymd(2026, 5, 31): 100
        ]
        #expect(ContributionsParser.sum(days: days, window: .monthly, asOf: asOf) == 6)
    }

    @Test func zeroActivity_returnsZeroNotError() throws {
        let html = """
        <td data-date="2026-05-28" id="cd-z"></td>
        <tool-tip for="cd-z">No contributions on Thursday May 28, 2026</tool-tip>
        """
        let days = try ContributionsParser.parseDays(html: html)
        let asOf = ymd(2026, 5, 28)
        #expect(ContributionsParser.sum(days: days, window: .weekly, asOf: asOf) == 0)
    }

    // MARK: - Helpers

    // MARK: - Trolling

    /// Sixty days before May 28 at a steady 20 a day, so their usual big day is 20.
    private func steadyHistory(_ count: Int = 20) -> [Date: Int] {
        var days: [Date: Int] = [:]
        for offset in 1...60 {
            days[ContributionsParser.isoCalendar().date(byAdding: .day, value: -offset, to: ymd(2026, 5, 28))!] = count
        }
        return days
    }

    @Test func trolling_flagsADayFarAboveTheirUsualBigDay() {
        var days = steadyHistory()
        days[ymd(2026, 5, 28)] = 784
        let burst = ContributionsParser.burst(days: days, window: .daily, asOf: ymd(2026, 5, 28))
        #expect(burst == Burst(day: ymd(2026, 5, 28), count: 784, usual: 20))
        #expect(burst?.multiple == 39)
    }

    @Test func trolling_ignoresABusyDayUnderFiveTimesTheirUsual() {
        var days = steadyHistory(40)
        days[ymd(2026, 5, 28)] = 200 // exactly 5×: not over the line
        #expect(ContributionsParser.burst(days: days, window: .daily, asOf: ymd(2026, 5, 28)) == nil)
    }

    @Test func trolling_needsMoreThanAHundred() {
        var days = steadyHistory(2)
        days[ymd(2026, 5, 28)] = 100 // 50× a quiet account's usual, but not over the floor
        #expect(ContributionsParser.burst(days: days, window: .daily, asOf: ymd(2026, 5, 28)) == nil)
        days[ymd(2026, 5, 28)] = 101
        #expect(ContributionsParser.burst(days: days, window: .daily, asOf: ymd(2026, 5, 28))?.count == 101)
    }

    @Test func trolling_newAccountOverTheFloorIsTrolling() {
        let days = [ymd(2026, 5, 28): 150]
        let burst = ContributionsParser.burst(days: days, window: .daily, asOf: ymd(2026, 5, 28))
        #expect(burst == Burst(day: ymd(2026, 5, 28), count: 150, usual: 0))
        #expect(burst?.multiple == nil)
    }

    @Test func trolling_staysInLongerWindowsUntilTheDayLeaves() {
        var days = steadyHistory()
        days[ymd(2026, 5, 25)] = 500
        days[ymd(2026, 5, 28)] = 20
        let asOf = ymd(2026, 5, 28)
        #expect(ContributionsParser.burst(days: days, window: .daily, asOf: asOf) == nil)
        #expect(ContributionsParser.burst(days: days, window: .weekly, asOf: asOf)?.count == 500)
        #expect(ContributionsParser.burst(days: days, window: .monthly, asOf: asOf)?.day == ymd(2026, 5, 25))
    }

    @Test func trolling_judgesEachDayOnlyAgainstTheDaysBeforeIt() {
        var days = steadyHistory()
        days[ymd(2026, 5, 27)] = 300
        days[ymd(2026, 5, 28)] = 5_000
        // The later huge day doesn't raise the bar for the earlier one…
        #expect(ContributionsParser.burst(days: days, window: .daily, asOf: ymd(2026, 5, 27))
            == Burst(day: ymd(2026, 5, 27), count: 300, usual: 20))
        // …and a window with two reports the bigger.
        #expect(ContributionsParser.burst(days: days, window: .weekly, asOf: ymd(2026, 5, 28))
            == Burst(day: ymd(2026, 5, 28), count: 5_000, usual: 20))
    }

    @Test func usualBigDay_isTheNinetiethPercentileOfActiveDays() {
        #expect(TrollCheck.usualBigDay([]) == 0)
        #expect(TrollCheck.usualBigDay([0, 0]) == 0)
        #expect(TrollCheck.usualBigDay(Array(1...10)) == 10)
        #expect(TrollCheck.usualBigDay([0] + Array(1...20)) == 19)
    }

    func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        let cal = ContributionsParser.isoCalendar()
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
}
