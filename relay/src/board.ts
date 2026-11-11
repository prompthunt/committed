import type { CachedDays, InstallationRow } from "./db";
import { deriveLiveRankState, type LiveRankState } from "./liveRank";
import { currentStreak, localDate, sum, type Days } from "./parser";
import { order, selfFirst, type Standing, type Window } from "./ranking";

/**
 * Board computation shared by the cron cycle (Live rank pushes) and the board route (other
 * screens). Both call `deriveBoard`, so they can't disagree; only where the contribution days
 * come from differs, and both read them through `loginData`.
 */

export interface LoginData {
  days: Days;
  /** Unix seconds of the last successful fetch of these days. */
  fetchedAt: number;
}

/** A contribution cache row's last good days, or null when it has none. */
export function loginData(cached: Pick<CachedDays, "fetched_at" | "days_json"> | null): LoginData | null {
  if (!cached || cached.days_json === null || cached.fetched_at === null) return null;
  return { days: JSON.parse(cached.days_json) as Days, fetchedAt: cached.fetched_at };
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
function dailyRanks(competitors: readonly string[], daily: Readonly<Record<string, Standing>>): Record<string, number> {
  const ranks: Record<string, number> = {};
  for (const entry of order(competitors, daily, "daily")) {
    if (daily[entry.login]) ranks[entry.login] = entry.rank;
  }
  return ranks;
}

/** Everyone's current streak from the same calendars, in the installation's own day, as the app works it out. */
export function streaksFor(
  competitors: readonly string[],
  data: ReadonlyMap<string, LoginData>,
  today: string,
): Record<string, number> {
  const streaks: Record<string, number> = {};
  for (const login of competitors) {
    const entry = data.get(login);
    if (entry) streaks[login] = currentStreak(entry.days, today);
  }
  return streaks;
}

/** Today's movement per login, `baseline − current`, as `RefreshCoordinator.updateTodaysRankDeltas` reports it. */
function rankDeltas(baseline: Readonly<Record<string, number>>, current: Readonly<Record<string, number>>) {
  const deltas: Record<string, number> = {};
  for (const [login, rank] of Object.entries(current)) {
    if (baseline[login] !== undefined) deltas[login] = baseline[login] - rank;
  }
  return deltas;
}

export interface BoardDerivation {
  /** The installation's local calendar date. */
  today: string;
  /** Today's daily ranks: the movement baseline the day's first cycle records. */
  ranksToday: Record<string, number>;
  /** Today's movement per login; empty until today's baseline exists. */
  deltas: Record<string, number>;
  standings: Record<string, Standing>;
  state: LiveRankState;
}

/**
 * The one derivation of an installation's Live rank state for a window. Pure: it reads the
 * movement baseline but never records it (the cycle does, from `ranksToday`).
 */
export function deriveBoard(
  row: InstallationRow,
  data: ReadonlyMap<string, LoginData>,
  window: Window,
  now: number,
): BoardDerivation {
  const competitors = competitorsOf(row);
  const today = localDate(now, row.time_zone);
  // Today's movement mirrors RefreshCoordinator.updateTodaysRankDeltas: baseline − current, once
  // the day's baseline (daily ranks of rows with data) exists.
  const daily = standingsFor(competitors, data, "daily", today);
  const ranksToday = dailyRanks(competitors, daily);
  const deltas =
    row.baseline_date === today && row.baseline_ranks_json
      ? rankDeltas(JSON.parse(row.baseline_ranks_json) as Record<string, number>, ranksToday)
      : {};
  const standings = window === "daily" ? daily : standingsFor(competitors, data, window, today);
  const state = deriveLiveRankState({
    self: row.login,
    competitors,
    standings,
    window,
    rankDeltas: deltas,
    streaks: streaksFor(competitors, data, today),
    // The data's age is that of your own count, the headline number. A rival whose page keeps
    // failing (renamed account) must not pin every push's stale date in the past.
    now: data.get(row.login)?.fetchedAt ?? now,
  });
  return { today, ranksToday, deltas, standings, state };
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
 * The board route's body: the Live rank state the cycle derives (same `updatedAt` rule: when
 * your own count was fetched, else the read time), plus the full visible board in board order.
 */
export interface Board extends LiveRankState {
  /** Your login. */
  login: string;
  /** Your public GitHub name, as the cycle last looked it up; null when unknown or empty. */
  displayName: string | null;
  /** Contributions to pass the person above (at least 1, since you win ties); null with nobody above. */
  gapToPass: number | null;
  rows: BoardRow[];
}

/**
 * One installation's board from already-loaded contribution data. Pure: it reads the movement
 * baseline the cycle recorded but never changes it.
 */
export function readBoard(row: InstallationRow, data: ReadonlyMap<string, LoginData>, window: Window, now: number): Board {
  const { standings, deltas, state } = deriveBoard(row, data, window, now);
  const rows = order(competitorsOf(row), standings, window).map(({ login, rank }) => ({
    rank,
    login,
    contributions: standings[login]?.contributions ?? null,
    movementToday: window === "daily" && standings[login] ? (deltas[login] ?? 0) : 0,
    isSelf: login === row.login,
  }));
  const gapToPass =
    state.above && state.contributions !== null ? Math.max(state.above.contributions - state.contributions, 1) : null;

  return { ...state, login: row.login, displayName: row.display_name || null, gapToPass, rows };
}

/**
 * The board route's (and web widget's) one error shape, never cached. The device API keeps its
 * older `{ error }` bodies.
 */
export function boardError(status: number, error: string, message: string): Response {
  return Response.json({ error, message }, { status, headers: { "cache-control": "no-store" } });
}
