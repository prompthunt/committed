import { DAY_COUNT, type Window } from "./ranking";

/**
 * TypeScript port of `ContributionsParser` (CommitStandings/Services/ContributionsParser.swift).
 * Parses GitHub's public contributions calendar HTML at
 * `https://github.com/users/{login}/contributions` into per-day counts.
 *
 * Two shapes are supported, exactly as in Swift:
 * 1. Modern: `<td data-date="YYYY-MM-DD" id="...">` paired with
 *    `<tool-tip for="...">N contributions on ...</tool-tip>` ("No contributions" → 0).
 * 2. Legacy: `<td data-date="YYYY-MM-DD" data-count="N">`, or an `aria-label="N contributions on ..."`.
 *
 * Days are keyed by the calendar date GitHub prints (`YYYY-MM-DD`). The Swift parser keys
 * by the start of that day in the Mac's time zone; the relay instead compares the date
 * strings with the installation's own local date (see `localDate`).
 */

export type Days = Record<string, number>;

export class ContributionsParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ContributionsParseError";
  }
}

const dateCellRegex = /<td\b([^>]*)\bdata-date="(\d{4})-(\d{2})-(\d{2})"([^>]*)>([\s\S]*?)<\/td>/gi;
const idAttrRegex = /\bid="([^"]+)"/i;
const dataCountRegex = /\bdata-count="(\d+)"/i;
const ariaLabelRegex = /aria-label="([^"]+)"/i;
const tooltipRegex = /<tool-tip\b[^>]*\bfor="([^"]+)"[^>]*>([\s\S]*?)<\/tool-tip>/gi;
const leadingCountRegex = /^\s*([\d,]+)\s+contribution/i;
const noContribRegex = /^\s*no\s+contributions/i;

export function parseDays(html: string): Days {
  const cells = [...html.matchAll(dateCellRegex)];
  if (cells.length === 0) throw new ContributionsParseError("No day cells found");
  const tooltipCounts = extractTooltipCounts(html);

  const result: Days = {};
  for (const match of cells) {
    const [, preAttrs = "", year, month, day, postAttrs = "", body = ""] = match;
    const key = `${year}-${month}-${day}`;
    const attrs = `${preAttrs} ${postAttrs}`;
    const id = attrs.match(idAttrRegex)?.[1];
    const directCount = attrs.match(dataCountRegex)?.[1];
    const label = attrs.match(ariaLabelRegex)?.[1] ?? body.match(ariaLabelRegex)?.[1];
    const labelCount = label === undefined ? undefined : parseCount(label);

    if (directCount !== undefined) {
      result[key] = Number.parseInt(directCount, 10);
    } else if (id !== undefined && tooltipCounts.has(id)) {
      result[key] = tooltipCounts.get(id)!;
    } else if (labelCount !== undefined) {
      result[key] = labelCount;
    } else {
      result[key] = 0;
    }
  }
  return result;
}

/** Sum of the window ending on `today` (inclusive), today and the prior `dayCount − 1` days. */
export function sum(days: Days, window: Window, today: string): number {
  const earliest = addDays(today, -(DAY_COUNT[window] - 1));
  let total = 0;
  for (const [date, count] of Object.entries(days)) {
    if (date >= earliest && date <= today) total += count;
  }
  return total;
}

/**
 * Days in a row with at least one contribution as of `today`, the port of Swift's
 * `ContributionHistory.currentStreak(asOf:)`. While today has none yet, the run counts back from
 * yesterday, so a streak stays alive until today ends. A day missing from the calendar counts as
 * none, so the run stops at the calendar's first day, and days after `today` never count. The raw
 * count: the apps show it from 2, and past 365 as "365+".
 */
export function currentStreak(days: Days, today: string): number {
  const contributed = (date: string) => (days[date] ?? 0) > 0;
  let day = contributed(today) ? today : addDays(today, -1);
  let streak = 0;
  while (contributed(day)) {
    streak += 1;
    day = addDays(day, -1);
  }
  return streak;
}

/** The calendar date (`YYYY-MM-DD`) at `unixSeconds` in the IANA `timeZone`. */
export function localDate(unixSeconds: number, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(unixSeconds * 1000));
  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

export function isValidTimeZone(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone });
    return true;
  } catch {
    return false;
  }
}

function addDays(date: string, delta: number): string {
  const [year, month, day] = date.split("-").map(Number);
  const shifted = new Date(Date.UTC(year!, month! - 1, day! + delta));
  return shifted.toISOString().slice(0, 10);
}

function extractTooltipCounts(html: string): Map<string, number> {
  const byId = new Map<string, number>();
  for (const [, forId = "", body = ""] of html.matchAll(tooltipRegex)) {
    byId.set(forId, parseCount(body) ?? 0);
  }
  return byId;
}

function parseCount(label: string): number | undefined {
  if (noContribRegex.test(label)) return 0;
  const captured = label.match(leadingCountRegex)?.[1];
  if (captured === undefined) return undefined;
  const value = Number.parseInt(captured.replaceAll(",", ""), 10);
  return Number.isNaN(value) ? undefined : value;
}
