import type { InstallationRow } from "./db";
import { deriveLiveRankState, type LiveRankState } from "./liveRank";
import { localDate, sum, type Days } from "./parser";
import { order, selfFirst, type Standing, type Window } from "./ranking";

/**
 * Board computation shared by the cron cycle (Live rank pushes) and the board route (other
 * screens), so the two can't disagree. Both rank with `order` and derive with
 * `deriveLiveRankState`; only where the contribution days come from differs.
 */

export interface LoginData {
  days: Days;
  /** Unix seconds of the last successful fetch of these days. */
  fetchedAt: number;
}

/** Rows saved before registration enforced it may list you later: rank them you-first too. */
export function competitorsOf(row: InstallationRow): string[] {
  return selfFirst(row.login, JSON.parse(row.competitors_json) as string[]);
}

export function standingsFor(
  competitors: readonly string[],
  data: ReadonlyMap<string, LoginData>,
  window: Window,
  today: string,
): Record<string, Standing> {
  const standings: Record<string, Standing> = {};
  for (const login of competitors) {
    const entry = data.get(login);
    if (entry) standings[login] = { contributions: sum(entry.days, window, today), window };
  }
  return standings;
}

/** Today's daily ranks of the rows that have data: what the day's movement baseline records. */
export function dailyRanks(competitors: readonly string[], daily: Readonly<Record<string, Standing>>): Record<string, number> {
  const ranks: Record<string, number> = {};
  for (const entry of order(competitors, daily, "daily")) {
    if (daily[entry.login]) ranks[entry.login] = entry.rank;
  }
  return ranks;
}

/** Today's movement per login, `baseline − current`, as `RefreshCoordinator.updateDailyRankDeltas` reports it. */
export function rankDeltas(baseline: Readonly<Record<string, number>>, current: Readonly<Record<string, number>>) {
  const deltas: Record<string, number> = {};
  for (const [login, rank] of Object.entries(current)) {
    if (baseline[login] !== undefined) deltas[login] = baseline[login] - rank;
  }
  return deltas;
}

export interface BoardRow {
  rank: number;
  login: string;
  /** null = no data for this login yet (a placeholder row). */
  contributions: number | null;
  /** Places moved since today's baseline. Today only, else 0. */
  movementToday: number;
  /** This row is the installation's owner ("you"). */
  isSelf: boolean;
}

/**
 * The board route's body: the Live rank summary fields, plus the full visible board in board
 * order. `updatedAt` is when your own count was fetched (as in Live rank), else the newest data
 * used; null when nothing on the board has data.
 */
export interface Board extends Omit<LiveRankState, "updatedAt"> {
  updatedAt: number | null;
  /** Your login. */
  login: string;
  /** Contributions to pass the person above (at least 1, since you win ties); null with nobody above. */
  gapToPass: number | null;
  rows: BoardRow[];
}

/**
 * One installation's board from already-loaded contribution data. Pure: it reads the movement
 * baseline the cycle recorded but never changes it.
 */
export function readBoard(row: InstallationRow, data: ReadonlyMap<string, LoginData>, window: Window, now: number): Board {
  const competitors = competitorsOf(row);
  const today = localDate(now, row.time_zone);
  const daily = standingsFor(competitors, data, "daily", today);
  const deltas =
    row.baseline_date === today && row.baseline_ranks_json
      ? rankDeltas(JSON.parse(row.baseline_ranks_json) as Record<string, number>, dailyRanks(competitors, daily))
      : {};
  const standings = window === "daily" ? daily : standingsFor(competitors, data, window, today);

  const newest = Math.max(...competitors.map((login) => data.get(login)?.fetchedAt ?? -Infinity));
  const updatedAt = data.get(row.login)?.fetchedAt ?? (Number.isFinite(newest) ? newest : null);
  const state = deriveLiveRankState({
    self: row.login,
    competitors,
    standings,
    window,
    rankDeltas: deltas,
    now: updatedAt ?? now,
  });

  const rows = order(competitors, standings, window).map(({ login, rank }) => ({
    rank,
    login,
    contributions: standings[login]?.contributions ?? null,
    movementToday: window === "daily" && standings[login] ? (deltas[login] ?? 0) : 0,
    isSelf: login === row.login,
  }));
  const gapToPass =
    state.above && state.contributions !== null ? Math.max(state.above.contributions - state.contributions, 1) : null;

  return { ...state, updatedAt, login: row.login, gapToPass, rows };
}
