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
}
