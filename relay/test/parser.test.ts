import { describe, expect, it } from "vitest";
import { ContributionsParseError, localDate, parseDays, sum } from "../src/parser";

// These cases mirror CommitStandingsTests/ContributionsParserTests.swift one for one
// (same HTML, same expectations). Days are keyed by the calendar date GitHub prints
// ("YYYY-MM-DD"), which is what the Swift parser's local-midnight Date keys represent.

describe("parseDays (port of ContributionsParser.parseDays)", () => {
  it("modern format: tooltip-linked per-day counts", () => {
    const html = `
<table>
  <td data-date="2026-05-22" id="cd-0"></td>
  <td data-date="2026-05-23" id="cd-1"></td>
  <td data-date="2026-05-28" id="cd-2"></td>
</table>
<tool-tip for="cd-0" popover="manual">3 contributions on Friday May 22, 2026</tool-tip>
<tool-tip for="cd-1">No contributions on Saturday May 23, 2026</tool-tip>
<tool-tip for="cd-2">12 contributions on Thursday May 28, 2026</tool-tip>`;
    const days = parseDays(html);
    expect(days["2026-05-22"]).toBe(3);
    expect(days["2026-05-23"]).toBe(0);
    expect(days["2026-05-28"]).toBe(12);
  });

  it("legacy aria-label", () => {
    const html = `
<td data-date="2026-05-28" aria-label="7 contributions on Thursday, May 28, 2026"></td>
<td data-date="2026-05-27" aria-label="No contributions on Wednesday, May 27, 2026"></td>`;
    const days = parseDays(html);
    expect(days["2026-05-28"]).toBe(7);
    expect(days["2026-05-27"]).toBe(0);
  });

  it("legacy data-count", () => {
    expect(parseDays(`<td data-date="2026-05-28" data-count="9"></td>`)["2026-05-28"]).toBe(9);
  });

  it("comma-separated count", () => {
    const html = `
<td data-date="2026-05-28" id="cd-x"></td>
<tool-tip for="cd-x">1,234 contributions on Thursday May 28, 2026</tool-tip>`;
    expect(parseDays(html)["2026-05-28"]).toBe(1234);
  });

  it("empty HTML throws parseFailed", () => {
    expect(() => parseDays("<html></html>")).toThrow(new ContributionsParseError("No day cells found"));
  });

  it("zero activity returns zero, not an error", () => {
    const html = `
<td data-date="2026-05-28" id="cd-z"></td>
<tool-tip for="cd-z">No contributions on Thursday May 28, 2026</tool-tip>`;
    expect(sum(parseDays(html), "weekly", "2026-05-28")).toBe(0);
  });
});

describe("sum (port of ContributionsParser.sum)", () => {
  it("daily includes only today", () => {
    expect(sum({ "2026-05-27": 100, "2026-05-28": 7 }, "daily", "2026-05-28")).toBe(7);
  });

  it("weekly includes today and the prior six", () => {
    const days = {
      "2026-05-21": 100, // day 8, outside
      "2026-05-22": 1,
      "2026-05-23": 2,
      "2026-05-24": 3,
      "2026-05-25": 4,
      "2026-05-26": 5,
      "2026-05-27": 6,
      "2026-05-28": 7,
      "2026-05-29": 100, // future, outside
    };
    expect(sum(days, "weekly", "2026-05-28")).toBe(28);
  });

  it("monthly includes today and the prior twenty-nine", () => {
    const days = {
      "2026-04-30": 100, // outside the 30-day trailing window
      "2026-05-01": 1,
      "2026-05-15": 2,
      "2026-05-30": 3,
      "2026-05-31": 100,
    };
    expect(sum(days, "monthly", "2026-05-30")).toBe(6);
  });

  it("This month runs from the 1st of today's month to today", () => {
    const days = {
      "2026-10-31": 100, // last month
      "2026-11-01": 1,
      "2026-11-09": 2,
      "2026-11-10": 3,
      "2026-11-11": 100, // future
    };
    expect(sum(days, "month", "2026-11-10")).toBe(6);
  });

  it("This month on the 1st counts only the 1st", () => {
    expect(sum({ "2026-11-30": 40, "2026-12-01": 2 }, "month", "2026-12-01")).toBe(2);
    expect(sum({ "2026-12-31": 40, "2027-01-01": 0 }, "month", "2027-01-01")).toBe(0);
  });

  it("windows cross month and year boundaries", () => {
    expect(sum({ "2025-12-31": 4, "2026-01-01": 1 }, "weekly", "2026-01-02")).toBe(5);
  });
});

describe("localDate", () => {
  // 2026-11-05T02:30:00Z
  const now = Date.UTC(2026, 10, 5, 2, 30) / 1000;

  it("uses the installation's IANA time zone, not UTC", () => {
    expect(localDate(now, "UTC")).toBe("2026-11-05");
    expect(localDate(now, "America/Los_Angeles")).toBe("2026-11-04");
    expect(localDate(now, "Asia/Tokyo")).toBe("2026-11-05");
  });
});
