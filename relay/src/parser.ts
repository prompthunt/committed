// TypeScript port of CommitStandings/Services/ContributionsParser.swift.
//
// Parses GitHub's public contributions calendar HTML at
// `https://github.com/users/{login}/contributions` into per-day counts. Two shapes are supported:
//   1. Modern: `<td data-date="YYYY-MM-DD" id="...">` paired with
//      `<tool-tip for="...">N contributions on ...</tool-tip>` ("No contributions" -> 0).
//   2. Legacy: `<td data-date="YYYY-MM-DD" data-count="N">`, or an `aria-label="N contributions on ..."`
//      on the cell or a child element.
// Both apps and the relay must agree, so this file is tested against shared/fixtures/contributions-parser.json.

import { WINDOW_DAY_COUNT, type ContributionDays, type ContributionWindow } from "./types";

export class ContributionsParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ContributionsParseError";
  }
}

const DATE_CELL = /<td\b([^>]*)\bdata-date="(\d{4})-(\d{2})-(\d{2})"([^>]*)>([\s\S]*?)<\/td>/gi;
const ID_ATTR = /\bid="([^"]+)"/i;
const DATA_COUNT = /\bdata-count="(\d+)"/i;
const ARIA_LABEL = /aria-label="([^"]+)"/i;
const TOOLTIP = /<tool-tip\b[^>]*\bfor="([^"]+)"[^>]*>([\s\S]*?)<\/tool-tip>/gi;
const LEADING_COUNT = /^\s*([\d,]+)\s+contribution/i;
const NO_CONTRIBUTIONS = /^\s*no\s+contributions/i;

/** Per-day counts keyed by the page's calendar date. Throws when the page has no day cells. */
export function parseDays(html: string): ContributionDays {
  const tooltipCounts = new Map<string, number>();
  for (const match of html.matchAll(TOOLTIP)) {
    tooltipCounts.set(match[1]!, countFromLabel(match[2]!) ?? 0);
  }

  const days: ContributionDays = {};
  let cells = 0;
  for (const match of html.matchAll(DATE_CELL)) {
    cells += 1;
    const [, pre, year, month, day, post, body] = match as unknown as string[];
    const attrs = `${pre} ${post}`;
    const key = `${year}-${month}-${day}`;

    const direct = DATA_COUNT.exec(attrs)?.[1];
    const id = ID_ATTR.exec(attrs)?.[1];
    const label = ARIA_LABEL.exec(attrs)?.[1] ?? ARIA_LABEL.exec(body!)?.[1];
    const labelCount = label === undefined ? undefined : countFromLabel(label);

    if (direct !== undefined) {
      days[key] = Number.parseInt(direct, 10);
    } else if (id !== undefined && tooltipCounts.has(id)) {
      days[key] = tooltipCounts.get(id)!;
    } else if (labelCount !== undefined) {
      days[key] = labelCount;
    } else {
      days[key] = 0;
    }
  }
  if (cells === 0) throw new ContributionsParseError("No day cells found");
  return days;
}

/**
 * Sum of the window's days ending on `today` (a local calendar date, `YYYY-MM-DD`), inclusive.
 * Daily = today only; weekly = today and the prior 6 days; monthly = today and the prior 29.
 */
export function sumWindow(days: ContributionDays, window: ContributionWindow, today: string): number {
  const earliest = addDays(today, -(WINDOW_DAY_COUNT[window] - 1));
  let total = 0;
  for (const [date, count] of Object.entries(days)) {
    if (date >= earliest && date <= today) total += count;
  }
  return total;
}

/** Calendar-date arithmetic on `YYYY-MM-DD` strings, independent of any time zone or DST. */
export function addDays(date: string, delta: number): string {
  const [year, month, day] = date.split("-").map((part) => Number.parseInt(part, 10));
  const shifted = new Date(Date.UTC(year!, month! - 1, day! + delta));
  return shifted.toISOString().slice(0, 10);
}

function countFromLabel(label: string): number | undefined {
  if (NO_CONTRIBUTIONS.test(label)) return 0;
  const digits = LEADING_COUNT.exec(label)?.[1];
  if (digits === undefined) return undefined;
  const value = Number.parseInt(digits.replaceAll(",", ""), 10);
  return Number.isNaN(value) ? undefined : value;
}
