import { standingsFor, streaksFor } from "./board";
import { loadContributions } from "./cycle";
import type { Store } from "./db";
import { deriveLiveRankState, type LiveRankState } from "./liveRank";
import { isValidTimeZone, localDate } from "./parser";
import { selfFirst, WINDOWS, type Window } from "./ranking";
import type { GitHubFetch, Log } from "./relay";

/**
 * `GET /v1/board` (public): one board's Live rank state, computed on request from the same shared
 * contribution cache the cron run uses. Unauthenticated and read-only: it takes public
 * usernames and stores nothing but the per-login cache. It backs the NZXT Kraken LCD page
 * (gitcommitted.app/kraken), which can't read github.com itself (no CORS).
 */

/** Smaller than a registration's cap: every login here can cost a GitHub fetch. */
export const MAX_BOARD_COMPETITORS = 100;

export interface BoardQuery {
  login: string;
  competitors: string[];
  window: Window;
  timeZone: string;
}

/** Parses `?login=&competitors=a,b&window=&tz=`, or returns an error code. */
export function parseBoardQuery(params: URLSearchParams, normalizeLogin: (raw: unknown) => string | null): BoardQuery | string {
  const login = normalizeLogin(params.get("login"));
  if (!login) return "invalid_login";

  const raw = (params.get("competitors") ?? "").split(",").filter((entry) => entry.trim() !== "");
  const normalized = raw.map(normalizeLogin);
  if (normalized.some((competitor) => competitor === null)) return "invalid_competitors";
  const competitors = selfFirst(login, [...new Set(normalized as string[])]);
  if (competitors.length > MAX_BOARD_COMPETITORS) return "too_many_competitors";

  const window = params.get("window") ?? "daily";
  if (!WINDOWS.includes(window as Window)) return "invalid_window";
  const timeZone = params.get("tz") ?? "UTC";
  if (!isValidTimeZone(timeZone)) return "invalid_time_zone";

  return { login, competitors, window: window as Window, timeZone };
}

export async function boardState(
  query: BoardQuery,
  deps: { store: Store; github: GitHubFetch; log: Log; now: number },
): Promise<LiveRankState> {
  const data = await loadContributions(query.competitors, deps, deps.now);
  const today = localDate(deps.now, query.timeZone);
  const standings = standingsFor(query.competitors, data, query.window, today);
  return deriveLiveRankState({
    self: query.login,
    competitors: query.competitors,
    standings,
    window: query.window,
    // Movement needs a per-board daily baseline, which a stateless read doesn't keep.
    rankDeltas: {},
    streaks: streaksFor(query.competitors, data, today),
    now: standings[query.login] ? data.get(query.login)!.fetchedAt : deps.now,
  });
}
