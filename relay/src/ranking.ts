// TypeScript port of CommitStandings/Store/Ranking.swift plus the LiveRankState derivation.
// Both are pinned by shared/fixtures/ranking-conformance.json, which the Swift tests also run.

import type { ContributionWindow } from "./types";

export interface Competitor {
  login: string;
  isSelf: boolean;
}

/** One login's count for a window. `lastUpdated` is Unix seconds of the data. */
export interface Standing {
  contributions: number;
  window: ContributionWindow;
  lastUpdated: number;
}

export interface RankedEntry {
  rank: number;
  competitor: Competitor;
}

export interface Neighbor {
  login: string;
  contributions: number;
}

/** LiveRankAttributes.ContentState. Optional values are null here; payloads omit them. */
export interface LiveRankState {
  window: ContributionWindow;
  rank: number | null;
  competitorCount: number;
  contributions: number | null;
  above: Neighbor | null;
  below: Neighbor | null;
  movementToday: number;
  updatedAt: number;
}

/**
 * Rank by contributions descending. A competitor with no standing for the window (or a standing for
 * a different window) sorts last; ties keep the competitor order. Ranks start at 1.
 */
export function order(
  competitors: readonly Competitor[],
  standings: Readonly<Record<string, Standing>>,
  window: ContributionWindow,
): RankedEntry[] {
  return competitors
    .map((competitor, index) => ({ competitor, index, contributions: countFor(standings, competitor.login, window) ?? -1 }))
    .sort((lhs, rhs) => (lhs.contributions === rhs.contributions ? lhs.index - rhs.index : rhs.contributions - lhs.contributions))
    .map((entry, position) => ({ rank: position + 1, competitor: entry.competitor }));
}

export interface LiveRankInput {
  /** Visible competitors in roster order, self included. */
  competitors: readonly Competitor[];
  standings: Readonly<Record<string, Standing>>;
  window: ContributionWindow;
  /** Places moved since the day's baseline per login (+ up). Read only for self, only on Today. */
  rankDeltas: Readonly<Record<string, number>>;
  /** Unix seconds; the fallback for `updatedAt` when no visible standing has data. */
  now: number;
}

/** The single derivation of Live rank's content state. Semantics: relay/README.md. */
export function deriveLiveRankState(input: LiveRankInput): LiveRankState {
  const { competitors, standings, window, rankDeltas, now } = input;
  const ranked = order(competitors, standings, window);
  const selfIndex = ranked.findIndex((entry) => entry.competitor.isSelf);
  const self = selfIndex >= 0 ? ranked[selfIndex]! : undefined;
  const contributions = self ? countFor(standings, self.competitor.login, window) : null;
  const hasRivals = competitors.length > 1;
  const ranks = self !== undefined && contributions !== null && hasRivals;

  const neighbor = (entry: RankedEntry | undefined): Neighbor | null => {
    if (!entry) return null;
    const count = countFor(standings, entry.competitor.login, window);
    return count === null ? null : { login: entry.competitor.login, contributions: count };
  };

  const dataTimes = competitors
    .map((competitor) => standings[competitor.login])
    .filter((standing): standing is Standing => standing !== undefined && standing.window === window)
    .map((standing) => standing.lastUpdated);

  return {
    window,
    rank: ranks ? self.rank : null,
    competitorCount: competitors.length,
    contributions,
    above: ranks ? neighbor(ranked[selfIndex - 1]) : null,
    below: ranks ? neighbor(ranked[selfIndex + 1]) : null,
    movementToday: ranks && window === "daily" ? (rankDeltas[self.competitor.login] ?? 0) : 0,
    updatedAt: Math.floor(dataTimes.length > 0 ? Math.max(...dataTimes) : now),
  };
}

function countFor(standings: Readonly<Record<string, Standing>>, login: string, window: ContributionWindow): number | null {
  const standing = standings[login];
  return standing !== undefined && standing.window === window ? standing.contributions : null;
}
