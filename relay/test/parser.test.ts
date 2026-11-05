import { describe, expect, it } from "vitest";
import rawFixture from "../../shared/fixtures/contributions-parser.json";
import { ContributionsParseError, parseDays, sumWindow } from "../src/parser";
import type { ContributionWindow } from "../src/types";

interface ParserFixture {
  parse: { name: string; html: string; days?: Record<string, number>; error?: string }[];
  sum: { name: string; days: Record<string, number>; window: ContributionWindow; today: string; expected: number }[];
}
const fixture = rawFixture as unknown as ParserFixture;

describe("contributions parser port (shared fixture)", () => {
  it("has cases", () => {
    expect(fixture.parse.length).toBeGreaterThan(0);
    expect(fixture.sum.length).toBeGreaterThan(0);
  });

  for (const testCase of fixture.parse) {
    it(`parses: ${testCase.name}`, () => {
      if (testCase.error !== undefined) {
        expect(() => parseDays(testCase.html)).toThrow(new ContributionsParseError(testCase.error));
        return;
      }
      expect(parseDays(testCase.html)).toEqual(testCase.days);
    });
  }

  for (const testCase of fixture.sum) {
    it(`sums: ${testCase.name}`, () => {
      const total = sumWindow(testCase.days, testCase.window, testCase.today);
      expect(total).toBe(testCase.expected);
    });
  }
});
