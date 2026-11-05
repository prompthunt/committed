import { describe, expect, it } from "vitest";
import fixture from "../../shared/fixtures/ranking-conformance.json";
import { deriveLiveRankState, order, type Standing } from "../src/ranking";
import type { ContributionWindow } from "../src/types";

type FixtureStanding = { contributions: number; window: string; lastUpdated: number };

function standingsOf(raw: Record<string, FixtureStanding>): Record<string, Standing> {
  return Object.fromEntries(
    Object.entries(raw).map(([login, s]) => [
      login,
      { contributions: s.contributions, window: s.window as ContributionWindow, lastUpdated: s.lastUpdated },
    ]),
  );
}

describe("ranking conformance (shared fixture)", () => {
  it("has cases", () => {
    expect(fixture.cases.length).toBeGreaterThan(0);
  });

  for (const testCase of fixture.cases) {
    const input = testCase.input;
    const window = input.window as ContributionWindow;
    const standings = standingsOf(input.standings as Record<string, FixtureStanding>);

    it(`orders: ${testCase.name}`, () => {
      const ranked = order(input.competitors, standings, window);
      expect(ranked.map((entry) => ({ login: entry.competitor.login, rank: entry.rank }))).toEqual(
        testCase.expected.order,
      );
    });

    it(`derives LiveRankState: ${testCase.name}`, () => {
      const state = deriveLiveRankState({
        competitors: input.competitors,
        standings,
        window,
        rankDeltas: input.rankDeltas as Record<string, number>,
        now: input.now,
      });
      expect(state).toEqual(testCase.expected.liveRankState);
    });
  }
});
