/**
 * TypeScript port of `Ranking.order` (CommitStandings/Store/Ranking.swift), the single
 * source of truth for board ordering. Keep the two in lockstep: both run the shared
 * conformance cases in fixtures/ranking-conformance.json.
 *
 * Contributions descending; a competitor with no standing for the window (or one whose
 * standing is for a different window) sorts last, below a real 0; ties keep competitor
 * order. Ranks start at 1.
 */

export type Window = "daily" | "weekly" | "monthly";

export const WINDOWS: readonly Window[] = ["daily", "weekly", "monthly"];

export const DAY_COUNT: Record<Window, number> = { daily: 1, weekly: 7, monthly: 30 };

export interface Standing {
  contributions: number;
  window: Window;
}

export interface RankedEntry {
  login: string;
  rank: number;
}

export function order(
  competitors: readonly string[],
  standings: Readonly<Record<string, Standing | undefined>>,
  window: Window,
): RankedEntry[] {
  const indexed = competitors.map((login, index) => {
    const standing = standings[login];
    // Same -1 sentinel as Swift, so a real 0 outranks missing data.
    const contributions = standing && standing.window === window ? standing.contributions : -1;
    return { index, login, contributions };
  });
  indexed.sort((lhs, rhs) =>
    lhs.contributions === rhs.contributions ? lhs.index - rhs.index : rhs.contributions - lhs.contributions,
  );
  return indexed.map((entry, position) => ({ login: entry.login, rank: position + 1 }));
}

/**
 * The board as ranked: your own login first, then everyone else in the order given. You're first
 * on your own board (as on the iPhone and the Mac), so `order` breaks a tie in your favor, and
 * "N to pass" (`gapToPass` in Swift) never names someone you're level with.
 */
export function selfFirst(self: string, competitors: readonly string[]): string[] {
  return [self, ...competitors.filter((login) => login !== self)];
}
