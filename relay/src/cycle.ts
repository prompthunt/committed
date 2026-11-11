import {
  endPayload,
  isDeadToken,
  startPayload,
  STALE_AFTER_SECONDS,
  updatePayload,
  type ApnsPayload,
  type ApnsSender,
} from "./apns";
import { competitorsOf, deriveBoard, loginData, type LoginData } from "./board";
import type { InstallationRow, Store } from "./db";
import type { LiveRankState } from "./liveRank";
import { parseDays } from "./parser";
import type { GitHubFetch, GitHubNameFetch, Log } from "./relay";

export interface CycleDeps {
  store: Store;
  apns: ApnsSender;
  github: GitHubFetch;
  githubName: GitHubNameFetch;
  now: () => number;
  log: Log;
}

/** Contribution pages are shared across installations for 5 minutes. */
export const CACHE_SECONDS = 5 * 60;
/** iOS ends a Live Activity at 8 hours; rotate before that. */
export const ROTATE_AFTER_SECONDS = 7.5 * 60 * 60;
/** Heartbeat when the last pushed state is within this long of its stale date. */
export const HEARTBEAT_MARGIN_SECONDS = 5 * 60;
/** The owner's public GitHub name is looked up at most once a day per installation, failed or not. */
export const NAME_LOOKUP_SECONDS = 24 * 60 * 60;
const FETCH_CONCURRENCY = 6;

/**
 * One cron run. For each installation: compute its `LiveRankState` from public contribution
 * graphs, then push only what changed (plus a heartbeat before the stale date), rotating the
 * activity before iOS's 8-hour limit.
 */
export async function runCycle(deps: CycleDeps): Promise<void> {
  const now = deps.now();
  const installations = await deps.store.all();
  const logins = new Set<string>();
  for (const row of installations) for (const login of competitorsOf(row)) logins.add(login);
  const data = await loadContributions([...logins], deps, now);

  for (const row of installations) {
    try {
      await runInstallation(row, data, deps, now);
    } catch (error) {
      deps.log("installation_failed", { id: row.id, error: String(error) });
    }
  }
  // After the pushes, so a slow or failing GitHub API never delays Live rank.
  for (const row of installations) await lookUpDisplayName(row, deps, now);
  deps.log("cycle_complete", { installations: installations.length, logins: logins.size });
}

async function runInstallation(
  row: InstallationRow,
  data: Map<string, LoginData>,
  deps: CycleDeps,
  now: number,
): Promise<void> {
  const { today, ranksToday, state } = deriveBoard(row, data, row.window, now);
  // The day's first run captures the movement baseline; later runs report baseline − current.
  if (row.baseline_date !== today || !row.baseline_ranks_json) {
    row.baseline_date = today;
    row.baseline_ranks_json = JSON.stringify(ranksToday);
  }
  const previous = row.last_state_json ? (JSON.parse(row.last_state_json) as LiveRankState) : null;

  if (row.activity_push_token) {
    const startedAt = row.activity_started_at ?? now;
    if (now - startedAt >= ROTATE_AFTER_SECONDS) {
      await send(row, "activity", endPayload(previous ?? state, now), 10, deps);
      row.activity_id = null;
      row.activity_push_token = null;
      row.activity_started_at = null;
      await start(row, state, deps, now);
    } else if (shouldUpdate(state, previous, now)) {
      const priority = previous !== null && previous.rank !== state.rank ? 10 : 5;
      if (await send(row, "activity", updatePayload(state, now), priority, deps)) {
        row.last_state_json = JSON.stringify(state);
        row.last_push_at = now;
      }
    }
  } else if (row.push_to_start_token) {
    // No activity (rotated, dismissed, or never started by the relay): restart at the next
    // rotation point, at most every 7.5 hours, rather than fighting the user every 5 minutes.
    const lastStart = row.last_start_at ?? row.created_at;
    if (now - lastStart >= ROTATE_AFTER_SECONDS) await start(row, state, deps, now);
  }

  await deps.store.save(row);
}

/**
 * The board route's `displayName`: the owner's public GitHub profile name, refreshed at most once a
 * day. Failures are silent (logged) and keep the last name until the next day's try.
 */
async function lookUpDisplayName(row: InstallationRow, deps: CycleDeps, now: number): Promise<void> {
  if (row.display_name_checked_at !== null && now - row.display_name_checked_at < NAME_LOOKUP_SECONDS) return;
  let name: string | null | undefined;
  try {
    name = (await deps.githubName(row.login))?.trim() || null;
  } catch (error) {
    deps.log("display_name_failed", { id: row.id, error: String(error) });
  }
  try {
    await deps.store.recordDisplayName(row.id, row.login, name, now);
  } catch (error) {
    deps.log("display_name_failed", { id: row.id, error: String(error) });
  }
}

async function start(row: InstallationRow, state: LiveRankState, deps: CycleDeps, now: number): Promise<void> {
  if (!row.push_to_start_token) return;
  row.last_start_at = now;
  if (await send(row, "pushToStart", startPayload(state, row.login, now), 10, deps)) {
    row.last_state_json = JSON.stringify(state);
    row.last_push_at = now;
  }
}

function shouldUpdate(state: LiveRankState, previous: LiveRankState | null, now: number): boolean {
  if (previous === null) return true;
  const { updatedAt: _a, ...current } = state;
  const { updatedAt: _b, ...last } = previous;
  if (JSON.stringify(current) !== JSON.stringify(last)) return true;
  // Heartbeat: newer data extends the stale date. Re-pushing equally old data would not.
  const nearStale = now >= previous.updatedAt + STALE_AFTER_SECONDS - HEARTBEAT_MARGIN_SECONDS;
  return nearStale && state.updatedAt > previous.updatedAt;
}

/** Sends one push; clears the token APNs rejects for good. Returns true on success. */
async function send(
  row: InstallationRow,
  which: "activity" | "pushToStart",
  payload: ApnsPayload,
  priority: 5 | 10,
  deps: CycleDeps,
): Promise<boolean> {
  const token = which === "activity" ? row.activity_push_token : row.push_to_start_token;
  if (!token) return false;
  const result = await deps.apns.send({ token, environment: row.apns_environment, priority, payload });
  const fields = { id: row.id, apsEvent: payload.aps.event, priority, status: result.status, reason: result.reason ?? null };
  if (result.status === 200) {
    deps.log("push_sent", fields);
    return true;
  }
  deps.log("push_failed", fields);
  if (isDeadToken(result)) {
    if (which === "activity") {
      row.activity_id = null;
      row.activity_push_token = null;
      row.activity_started_at = null;
      row.last_state_json = null;
    } else {
      row.push_to_start_token = null;
    }
    deps.log("token_cleared", { id: row.id, token: which });
  }
  return false;
}

/** Days per login, from the shared 5-minute cache or a fresh anonymous fetch. */
export async function loadContributions(
  logins: string[],
  deps: Pick<CycleDeps, "store" | "github" | "log">,
  now: number,
): Promise<Map<string, LoginData>> {
  const result = new Map<string, LoginData>();
  const queue = [...logins];
  const worker = async () => {
    for (let login = queue.shift(); login !== undefined; login = queue.shift()) {
      const cached = await deps.store.getCached(login);
      if (cached && now - cached.attempted_at < CACHE_SECONDS) {
        const entry = loginData(cached);
        if (entry) result.set(login, entry);
        continue;
      }
      try {
        const days = parseDays(await deps.github(login));
        await deps.store.putFetched(login, now, JSON.stringify(days));
        result.set(login, { days, fetchedAt: now });
      } catch (error) {
        await deps.store.putFailed(login, now, String(error));
        deps.log("contributions_failed", { login, error: String(error) });
        // Stale beats missing: keep the last good days, with their real age.
        const entry = loginData(cached);
        if (entry) result.set(login, entry);
      }
    }
  };
  await Promise.all(Array.from({ length: FETCH_CONCURRENCY }, worker));
  return result;
}
