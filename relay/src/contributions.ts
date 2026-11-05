// Public contribution graphs, fetched anonymously and cached per login for 5 minutes in D1 so every
// installation that tracks a login shares one fetch. What to fetch first is decided in cron.ts.

import { logEvent, type Log } from "./log";
import { addDays, parseDays } from "./parser";
import type { ContributionDays } from "./types";

export const CACHE_TTL_SECONDS = 300;
/**
 * Outbound requests (GitHub fetches + APNs pushes) one cron run may make: the free plan's 50
 * external subrequests per invocation. D1 calls draw on a separate pool. Override with the
 * SUBREQUEST_LIMIT var (Workers Paid allows 10,000).
 */
export const DEFAULT_SUBREQUEST_LIMIT = 50;
/** Most GitHub fetches per run before the APNs reserve; override with the GITHUB_FETCH_BUDGET var. */
export const DEFAULT_FETCH_BUDGET = 40;
/** Days kept per login: the 30-day window from any local "today" (UTC-12 to UTC+14) fits inside. */
const RETAINED_DAYS = 35;
const CONCURRENCY = 6;
const IN_CLAUSE_CHUNK = 50;

export interface CachedCounts {
  days: ContributionDays;
  /** Unix seconds of the successful fetch: the data's time. */
  fetchedAt: number;
}

export interface CountsDeps {
  fetchContributions(login: string): Promise<Response>;
  log: Log;
}

/** Reads the cached counts for `logins` (logins never fetched successfully are absent). */
export async function readCounts(db: D1Database, logins: readonly string[]): Promise<Map<string, CachedCounts>> {
  const counts = new Map<string, CachedCounts>();
  for (let i = 0; i < logins.length; i += IN_CLAUSE_CHUNK) {
    const chunk = logins.slice(i, i + IN_CLAUSE_CHUNK);
    const { results } = await db
      .prepare(`SELECT login, days, fetched_at FROM contribution_cache WHERE login IN (${chunk.map(() => "?").join(",")})`)
      .bind(...chunk)
      .all<{ login: string; days: string; fetched_at: number }>();
    for (const row of results) counts.set(row.login, { days: JSON.parse(row.days) as ContributionDays, fetchedAt: row.fetched_at });
  }
  return counts;
}

/**
 * The logins due a refresh (5 minutes old, or never fetched), in the order to fetch them:
 * `first` (each board's own login and its neighbors) before the rest, the stalest first within
 * each group, never-fetched before cached. Ties keep `logins` order.
 */
export function refreshOrder(
  logins: readonly string[],
  first: ReadonlySet<string>,
  counts: ReadonlyMap<string, CachedCounts>,
  now: number,
): string[] {
  const age = (login: string) => counts.get(login)?.fetchedAt ?? -1;
  return logins
    .filter((login) => {
      const cached = counts.get(login);
      return !cached || now - cached.fetchedAt >= CACHE_TTL_SECONDS;
    })
    .sort((a, b) => Number(first.has(b)) - Number(first.has(a)) || age(a) - age(b));
}

/**
 * Fetches up to `budget` of `ordered` and writes successes to `counts` and the cache. A failed
 * fetch keeps any cached counts: stale data beats a blank. Returns the number of fetches made.
 */
export async function refreshCounts(
  db: D1Database,
  deps: CountsDeps,
  counts: Map<string, CachedCounts>,
  ordered: readonly string[],
  now: number,
  budget: number,
): Promise<number> {
  const queue = ordered.slice(0, Math.max(0, budget));
  const attempts = queue.length;
  const workers = Array.from({ length: Math.min(CONCURRENCY, queue.length) }, async () => {
    for (let login = queue.shift(); login !== undefined; login = queue.shift()) {
      const fresh = await fetchCounts(deps, login, now);
      if (!fresh) continue;
      counts.set(login, fresh);
      await db
        .prepare(
          "INSERT INTO contribution_cache (login, days, fetched_at) VALUES (?1, ?2, ?3) ON CONFLICT (login) DO UPDATE SET days = ?2, fetched_at = ?3",
        )
        .bind(login, JSON.stringify(fresh.days), fresh.fetchedAt)
        .run();
    }
  });
  await Promise.all(workers);
  return attempts;
}

async function fetchCounts(deps: CountsDeps, login: string, now: number): Promise<CachedCounts | null> {
  try {
    const response = await deps.fetchContributions(login);
    if (!response.ok) {
      logEvent(deps.log, "contributions_fetch_failed", { status: response.status });
      return null;
    }
    const all = parseDays(await response.text());
    const oldest = addDays(new Date(now * 1000).toISOString().slice(0, 10), -RETAINED_DAYS);
    const days = Object.fromEntries(Object.entries(all).filter(([date]) => date >= oldest));
    return { days, fetchedAt: Math.floor(now) };
  } catch (cause) {
    logEvent(deps.log, "contributions_fetch_failed", { error: cause instanceof Error ? cause.name : "unknown" });
    return null;
  }
}
