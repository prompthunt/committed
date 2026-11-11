import { order, showsTodaysMovement, type Standing, type Window } from "./ranking";

/**
 * The Live Activity content state, matching `LiveRankAttributes.ContentState` in the
 * iOS app (spec #39). Dates are integer Unix seconds. Keys and nullability must match the
 * Swift Codable shape exactly: ActivityKit decodes this JSON as-is.
 */
export interface LiveRankState {
  window: Window;
  /** nil = no data yet for you, or no visible rivals. */
  rank: number | null;
  /** Visible competitors including you. */
  competitorCount: number;
  /** Your count for the window; nil = not loaded. */
  contributions: number | null;
  above: Neighbor | null;
  below: Neighbor | null;
  /** + moved up / − moved down since the day's baseline. Today and This month, else 0. */
  movementToday: number;
  /**
   * Your current streak (`currentStreak`), the raw count. Left out without your count or calendar,
   * so older apps and saved states, which never had it, read the same as "no streak known".
   */
  streak?: number;
  /** Unix seconds of the data, not of the push. */
  updatedAt: number;
}

export interface Neighbor {
  login: string;
  contributions: number;
  /** Their places moved since the day's baseline, like yours. Today and This month, else 0. */
  movementToday: number;
  /** Their current streak, like yours; left out when they have no calendar. */
  streak?: number;
}

export interface LiveRankInput {
  self: string;
  /** Visible competitor logins in board order, `self` first (`selfFirst`): you win your ties. */
  competitors: readonly string[];
  standings: Readonly<Record<string, Standing | undefined>>;
  window: Window;
  /** Today's rank change per login (baseline − current), yours and your neighbors'; read on Today and This month. */
  rankDeltas: Readonly<Record<string, number | undefined>>;
  /** Current streak per login (`currentStreak`), for everyone with a calendar; absent = unknown. */
  streaks?: Readonly<Record<string, number | undefined>>;
  /** Unix seconds of the data. */
  now: number;
}

/** The one pure derivation of Live rank, built on the `order` port of `Ranking.order`. */
export function deriveLiveRankState(input: LiveRankInput): LiveRankState {
  const { self, competitors, standings, window } = input;
  const ranked = order(competitors, standings, window);
  const countFor = (login: string): number | null => {
    const standing = standings[login];
    return standing && standing.window === window ? standing.contributions : null;
  };
  const movement = (login: string): number => (showsTodaysMovement(window) ? (input.rankDeltas[login] ?? 0) : 0);
  // Only set when known, so the JSON leaves the key out (as Swift's encoder does for nil).
  const withStreak = <T extends object>(value: T, login: string): T & { streak?: number } => {
    const streak = input.streaks?.[login];
    return streak === undefined ? value : { ...value, streak };
  };
  const neighbor = (login: string | undefined): Neighbor | null => {
    if (login === undefined) return null;
    const contributions = countFor(login);
    return contributions === null ? null : withStreak({ login, contributions, movementToday: movement(login) }, login);
  };

  const contributions = countFor(self);
  const position = ranked.findIndex((entry) => entry.login === self);
  const ranks = contributions !== null && position >= 0 && competitors.length > 1;

  const state: LiveRankState = {
    window,
    rank: ranks ? ranked[position]!.rank : null,
    competitorCount: competitors.length,
    contributions,
    above: ranks ? neighbor(ranked[position - 1]?.login) : null,
    below: ranks ? neighbor(ranked[position + 1]?.login) : null,
    movementToday: movement(self),
    updatedAt: Math.floor(input.now),
  };
  // Your streak follows your count: none shows beside a count that hasn't loaded.
  return contributions === null ? state : withStreak(state, self);
}
