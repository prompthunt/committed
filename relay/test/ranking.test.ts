import { describe, expect, it } from "vitest";
import fixture from "../../fixtures/ranking-conformance.json";
import { order, type Standing, type Window } from "../src/ranking";
import { deriveLiveRankState } from "../src/liveRank";
import { currentStreak, localDate, sum, type Days } from "../src/parser";

interface FixtureCase {
  name: string;
  input: {
    self: string;
    competitors: string[];
    window: Window;
    /** Counts, or `days` (calendars) with `timeZone` and `asOf`, from which standings are derived. */
    standings?: Record<string, Standing>;
    days?: Record<string, Days>;
    timeZone?: string;
    asOf?: string;
    rankDeltas: Record<string, number>;
    now: number;
  };
  expected: {
    order: { login: string; rank: number }[];
    streaks?: Record<string, number>;
    liveRankState: unknown;
  };
}

const cases = fixture.cases as unknown as FixtureCase[];

/** A case's standings and streaks: given, or worked out from its calendars as the cycle does. */
function board(input: FixtureCase["input"]): {
  standings: Record<string, Standing>;
  streaks: Record<string, number>;
} {
  if (!input.days) return { standings: input.standings ?? {}, streaks: {} };
  const today = localDate(input.now, input.timeZone!);
  const standings: Record<string, Standing> = {};
  const streaks: Record<string, number> = {};
  for (const [login, days] of Object.entries(input.days)) {
    standings[login] = { contributions: sum(days, input.window, today), window: input.window };
    streaks[login] = currentStreak(days, today);
  }
  return { standings, streaks };
}

describe("ranking conformance (fixtures/ranking-conformance.json)", () => {
  it("has cases, some with calendars", () => {
    expect(cases.length).toBeGreaterThan(0);
    expect(cases.some((c) => c.input.days)).toBe(true);
  });

  // You're first on your own board everywhere (registration and the cycle enforce it), so a case
  // with you later would test a board that can't exist.
  it("lists you first in every case", () => {
    for (const c of cases) expect(c.input.competitors[0], c.name).toBe(c.input.self);
  });

  // A case gives counts or calendars, never both, so nothing derived from days is overridden.
  it("gives each case standings or days, with a time zone and day for days", () => {
    for (const c of cases) {
      expect(c.input.standings === undefined, c.name).toBe(c.input.days !== undefined);
      if (c.input.days) {
        expect(c.input.timeZone, c.name).toBeTypeOf("string");
        expect(c.input.asOf, c.name).toBeTypeOf("string");
        expect(c.expected.streaks, c.name).toBeDefined();
      }
    }
  });

  for (const c of cases) {
    if (c.input.days) {
      it(`resolves the local day: ${c.name}`, () => {
        expect(localDate(c.input.now, c.input.timeZone!)).toBe(c.input.asOf);
      });

      it(`counts streaks: ${c.name}`, () => {
        expect(board(c.input).streaks).toStrictEqual(c.expected.streaks);
      });
    }

    it(`orders: ${c.name}`, () => {
      const ranked = order(c.input.competitors, board(c.input).standings, c.input.window);
      expect(ranked).toEqual(c.expected.order);
    });

    it(`derives LiveRankState: ${c.name}`, () => {
      const { standings, streaks } = board(c.input);
      const state = deriveLiveRankState({
        self: c.input.self,
        competitors: c.input.competitors,
        standings,
        window: c.input.window,
        rankDeltas: c.input.rankDeltas,
        streaks,
        now: c.input.now,
      });
      // Strict: a streak the fixture leaves out must be absent from the push, not undefined-valued.
      expect(JSON.parse(JSON.stringify(state))).toStrictEqual(c.expected.liveRankState);
    });
  }
});
