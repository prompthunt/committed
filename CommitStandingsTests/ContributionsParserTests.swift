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

    @Test func unreadableCellIsNotAnObservedZero() throws {
        let html = """
        <td data-date="2026-05-27" data-count="0"></td>
        <td data-date="2026-05-28" id="unresolved"></td>
        <tool-tip for="unresolved">Contribution data unavailable</tool-tip>
        """
        #expect(try ContributionsParser.parseDays(html: html) == ["2026-05-27": 0])
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

    private var noon: Date { ymd(2026, 5, 28).addingTimeInterval(12 * 3_600) }

    private func observeJump(from before: Int, to after: Int, usual: Int = 20,
                             interval: TimeInterval = 300) -> ContributionHistory {
        var first = steadyHistory(usual, ["2026-05-28": before])
        first.observe(after: nil, at: noon)
        var second = steadyHistory(usual, ["2026-05-28": after])
        second.observe(after: first, at: noon.addingTimeInterval(interval))
        return second
    }

    @Test func trolling_usesTheJumpBetweenCloseRefreshes() {
        let history = observeJump(from: 19, to: 803)
        let burst = history.burst(for: .daily, asOf: noon)
        #expect(burst == Burst(day: ymd(2026, 5, 28), count: 784, usual: 20))
        #expect(StandingCounts(history: history, window: .daily, asOf: noon).burst == burst)
    }

    @Test func trolling_ignoresAHighTotalOnFirstReadOrAfterALongGap() {
        var first = steadyHistory(20, ["2026-05-28": 803])
        first.observe(after: nil, at: noon)
        #expect(first.burst(for: .daily, asOf: noon) == nil)
        #expect(observeJump(from: 19, to: 803, interval: 361).burst(for: .daily, asOf: noon) == nil)
    }

    @Test func trolling_ignoresGradualContributionsEvenWhenTheyReach803() {
        var prior: ContributionHistory?
        for (index, total) in stride(from: 3, through: 803, by: 100).enumerated() {
            let time = noon.addingTimeInterval(Double(index) * 300)
            var next = steadyHistory(20, ["2026-05-28": total])
            next.observe(after: prior, at: time)
            #expect(next.burst(for: .daily, asOf: time) == nil)
            prior = next
        }
        #expect(prior?.total(for: .daily, asOf: noon) == 803)
    }

    @Test func trolling_keepsTheFloorAndUsualDayThreshold() {
        #expect(observeJump(from: 40, to: 240, usual: 40).burst(for: .daily, asOf: noon) == nil)
        #expect(observeJump(from: 0, to: 100, usual: 2).burst(for: .daily, asOf: noon) == nil)
        #expect(observeJump(from: 0, to: 101, usual: 2, interval: 360).burst(for: .daily, asOf: noon)?.count == 101)
    }

    @Test func trolling_requiresAnObservedCountOnTheSameDay() {
        let midnight = ymd(2026, 5, 28)
        var previousDay = steadyHistory()
        previousDay.observe(after: nil, at: midnight.addingTimeInterval(-60))
        var today = steadyHistory(20, ["2026-05-28": 803])
        today.observe(after: previousDay, at: midnight)
        #expect(today.burst(for: .daily, asOf: midnight) == nil)

        var missingToday = steadyHistory()
        missingToday.observe(after: nil, at: noon)
        today.observe(after: missingToday, at: noon.addingTimeInterval(60))
        #expect(today.burst(for: .daily, asOf: noon) == nil)
    }

    @Test func trolling_keepsTheObservedBurstInLongerWindows() throws {
        let encoded = try JSONEncoder().encode(observeJump(from: 19, to: 803))
        let observed = try JSONDecoder().decode(ContributionHistory.self, from: encoded)
        let tomorrow = ymd(2026, 5, 29)
        var next = steadyHistory(20, ["2026-05-28": 803])
        next.observe(after: observed, at: tomorrow)
        #expect(next.burst(for: .daily, asOf: tomorrow) == nil)
        #expect(next.burst(for: .weekly, asOf: tomorrow)?.count == 784)
        #expect(next.burst(for: .weekly, asOf: ymd(2026, 6, 4)) == nil)
        #expect(next.burst(for: .monthly, asOf: ymd(2026, 6, 4))?.count == 784)
    }

    @Test func trolling_ignoresLegacyCachedFlagAndPreservesCount() throws {
        let standing = Standing(username: "fixture", contributions: 803, window: .daily, lastUpdated: noon,
                                state: .loaded, burst: Burst(day: noon, count: 803, usual: 20))
        let data = try JSONEncoder().encode(standing)
        let legacy = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "observedBurst", with: "burst")
        let restored = try JSONDecoder().decode(Standing.self, from: Data(legacy.utf8))
        #expect(restored.contributions == 803)
        #expect(restored.burst == nil)
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
