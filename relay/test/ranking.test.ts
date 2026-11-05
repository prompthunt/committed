import { describe, expect, it } from "vitest";
import fixture from "../../fixtures/ranking-conformance.json";
import { order, type Standing, type Window } from "../src/ranking";
import { deriveLiveRankState } from "../src/liveRank";

interface FixtureCase {
  name: string;
  input: {
    self: string;
    competitors: string[];
    window: Window;
    standings: Record<string, Standing>;
    rankDeltas: Record<string, number>;
    now: number;
  };
  expected: {
    order: { login: string; rank: number }[];
    liveRankState: unknown;
  };
}

const cases = fixture.cases as unknown as FixtureCase[];

describe("ranking conformance (fixtures/ranking-conformance.json)", () => {
  it("has cases", () => {
    expect(cases.length).toBeGreaterThan(0);
  });

  for (const c of cases) {
    it(`orders: ${c.name}`, () => {
      const ranked = order(c.input.competitors, c.input.standings, c.input.window);
      expect(ranked).toEqual(c.expected.order);
    });

    it(`derives LiveRankState: ${c.name}`, () => {
      const state = deriveLiveRankState({
        self: c.input.self,
        competitors: c.input.competitors,
        standings: c.input.standings,
        window: c.input.window,
        rankDeltas: c.input.rankDeltas,
        now: c.input.now,
      });
      expect(state).toEqual(c.expected.liveRankState);
    });
  }
});
