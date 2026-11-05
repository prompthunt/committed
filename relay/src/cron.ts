// The 5-minute cron: recompute every installation's LiveRankState from public contribution graphs
// and push what changed. Lifecycle rules are written up in relay/README.md.

import { sendPush, type PushOutcome } from "./apns";
import type { RelayDeps } from "./app";
import { ApnsNotConfiguredError } from "./auth";
import {
  DEFAULT_FETCH_BUDGET,
  DEFAULT_SUBREQUEST_LIMIT,
  readCounts,
  refreshCounts,
  refreshOrder,
  type CachedCounts,
} from "./contributions";
import type { Env } from "./env";
import { logEvent } from "./log";
import { END_PRIORITY, START_PRIORITY, endPayload, staleDate, startPayload, updatePayload } from "./payload";
import { sumWindow } from "./parser";
import { deriveLiveRankState, order, type Competitor, type LiveRankState, type Standing } from "./ranking";
import { clearActivity, getInstallation, listInstallations, saveInstallation, type Installation } from "./store";
import { localDate } from "./time";

/** iOS ends a Live Activity after 8 hours; the relay replaces it at 7.5. */
export const ROTATE_AFTER_SECONDS = 7.5 * 3600;
/** Send a heartbeat once the stale date is this close, so a fresh one lands before it. */
export const HEARTBEAT_LEAD_SECONDS = 10 * 60;

export async function runCron(env: Env, deps: RelayDeps): Promise<void> {
  const now = deps.now();
  const installations = await listInstallations(env.DB);
  if (installations.length === 0) return;

  // Every GitHub fetch and APNs push is a subrequest, and a run has a fixed number. Pushes come
  // first: the fetch budget is what's left after reserving every push this run may send.
  const limit = nonNegativeInt(env.SUBREQUEST_LIMIT) ?? DEFAULT_SUBREQUEST_LIMIT;
  const reserve = installations.reduce((total, installation) => total + pushesDue(installation, now), 0);
  const fetchBudget = Math.max(0, Math.min(nonNegativeInt(env.GITHUB_FETCH_BUDGET) ?? DEFAULT_FETCH_BUDGET, limit - reserve));

  const logins = [...new Set(installations.flatMap((installation) => installation.competitors))];
  const counts = await readCounts(env.DB, logins);
  // What each board shows first: your own count and the people right above and below you.
  const focus = new Set(installations.flatMap((installation) => shownLogins(installation, counts, now)));
  const fetched = await refreshCounts(env.DB, deps, counts, refreshOrder(logins, focus, counts, now), now, fetchBudget);
  const budget: PushBudget = { left: limit - fetched };

  for (const installation of installations) {
    try {
      await updateInstallation(env, deps, installation, counts, now, budget);
    } catch (cause) {
      if (cause instanceof ApnsNotConfiguredError) {
        logEvent(deps.log, "apns_not_configured");
        return;
      }
      logEvent(deps.log, "installation_update_failed", {
        install: installation.id,
        error: cause instanceof Error ? cause.name : "unknown",
      });
    }
  }
}

/** Facts from one run, re-applied to a fresh row if a device write landed meanwhile. */
interface Outcome {
  readRevision: number;
  baseline?: { day: string | null; ranks: Record<string, number> | null };
  delivered?: { token: string; state: LiveRankState; staleAt: number };
  endedActivityToken?: string;
  removedPushToStartToken?: string;
  startedAt?: number;
}

/** Subrequests left for APNs in this run. */
interface PushBudget {
  left: number;
}

/** The most pushes `installation` can need this run: an update, or a rotation's end and start. */
function pushesDue(installation: Installation, now: number): number {
  const rotationDue = (since: number | null) => since !== null && now - since >= ROTATE_AFTER_SECONDS;
  if (installation.activityPushToken) {
    return rotationDue(installation.activityStartedAt) && installation.pushToStartToken ? 2 : 1;
  }
  return installation.pushToStartToken && rotationDue(installation.rotationAnchorAt) ? 1 : 0;
}

/** Each board as the cache has it now. */
function board(installation: Installation, counts: ReadonlyMap<string, CachedCounts>, now: number) {
  const today = localDate(now, installation.timeZone);
  const competitors: Competitor[] = installation.competitors.map((login) => ({ login, isSelf: login === installation.login }));
  const standings: Record<string, Standing> = {};
  for (const login of installation.competitors) {
    const cached = counts.get(login);
    if (!cached) continue;
    standings[login] = {
      contributions: sumWindow(cached.days, installation.window, today),
      window: installation.window,
      lastUpdated: cached.fetchedAt,
    };
  }
  return { today, competitors, standings };
}

/** You and the people directly above and below you, by the cached counts. */
function shownLogins(installation: Installation, counts: ReadonlyMap<string, CachedCounts>, now: number): string[] {
  const { competitors, standings } = board(installation, counts, now);
  const ranked = order(competitors, standings, installation.window);
  const self = ranked.findIndex((entry) => entry.competitor.isSelf);
  return ranked.slice(Math.max(0, self - 1), self + 2).map((entry) => entry.competitor.login);
}

async function updateInstallation(
  env: Env,
  deps: RelayDeps,
  installation: Installation,
  counts: Map<string, CachedCounts>,
  now: number,
  budget: PushBudget,
): Promise<void> {
  const { today, competitors, standings } = board(installation, counts, now);

  const outcome: Outcome = { readRevision: installation.revision };
  const rankDeltas = todaysMovement(installation, competitors, standings, today, outcome);
  const state = deriveLiveRankState({ competitors, standings, window: installation.window, rankDeltas, now });

  // Pushes past the run's subrequest limit wait for the next run (nothing is recorded as sent).
  const canPush = (count: number): boolean => {
    if (budget.left >= count) return true;
    logEvent(deps.log, "push_deferred", { install: installation.id });
    return false;
  };
  const push = async (token: string, priority: 5 | 10, payload: unknown, kind: string): Promise<PushOutcome> => {
    budget.left -= 1;
    const result = await sendPush(deps, env, { environment: installation.environment, token, priority, payload });
    logEvent(deps.log, result.outcome === "token-gone" ? "token_removed" : `push_${result.outcome}`, {
      install: installation.id,
      kind,
      status: result.status,
      reason: result.reason,
    });
    return result.outcome;
  };

  const activityToken = installation.activityPushToken;
  const pushToStart = installation.pushToStartToken;
  const activityAge = installation.activityStartedAt === null ? 0 : now - installation.activityStartedAt;

  if (activityToken && activityAge >= ROTATE_AFTER_SECONDS) {
    // Rotation: end the old activity at once, then push-to-start a fresh one (both, or neither).
    if (canPush(pushToStart ? 2 : 1)) {
      await push(activityToken, END_PRIORITY, endPayload(installation.lastState ?? state, now), "end");
      outcome.endedActivityToken = activityToken;
      if (pushToStart) await start(pushToStart);
    }
  } else if (!activityToken && pushToStart && now - installation.rotationAnchorAt >= ROTATE_AFTER_SECONDS) {
    if (canPush(1)) await start(pushToStart);
  } else if (activityToken) {
    const last = installation.lastState;
    const nextStale = staleDate(state);
    const changed = last === null || !sameContent(last, state);
    const heartbeat =
      installation.lastStaleAt !== null && now >= installation.lastStaleAt - HEARTBEAT_LEAD_SECONDS && nextStale > installation.lastStaleAt;
    if ((changed || heartbeat) && canPush(1)) {
      const priority = last !== null && last.rank !== state.rank ? 10 : 5;
      const result = await push(activityToken, priority, updatePayload(state, now), "update");
      if (result === "delivered") outcome.delivered = { token: activityToken, state, staleAt: nextStale };
      if (result === "token-gone") outcome.endedActivityToken = activityToken;
    }
  }

  await persist(env, deps, installation, outcome, now);

  async function start(token: string): Promise<void> {
    const result = await push(token, START_PRIORITY, startPayload(installation.login, state, now), "start");
    if (result === "delivered") outcome.startedAt = now;
    if (result === "token-gone") outcome.removedPushToStartToken = token;
  }
}

/**
 * Today's places moved per login, against a baseline captured at the first run of the local day
 * (mirrors RefreshCoordinator.updateDailyRankDeltas). Only people with data are ranked.
 */
function todaysMovement(
  installation: Installation,
  competitors: Competitor[],
  standings: Record<string, Standing>,
  today: string,
  outcome: Outcome,
): Record<string, number> {
  if (installation.window !== "daily") {
    if (installation.baselineDay !== null) outcome.baseline = { day: null, ranks: null };
    return {};
  }
  const current: Record<string, number> = {};
  for (const entry of order(competitors, standings, "daily")) {
    if (standings[entry.competitor.login]) current[entry.competitor.login] = entry.rank;
  }
  if (installation.baselineDay !== today || installation.baselineRanks === null) {
    outcome.baseline = { day: today, ranks: current };
    return {};
  }
  const deltas: Record<string, number> = {};
  for (const [login, rank] of Object.entries(current)) {
    const baseline = installation.baselineRanks[login];
    if (baseline !== undefined) deltas[login] = baseline - rank;
  }
  return deltas;
}

function apply(installation: Installation, outcome: Outcome, sameRead: boolean): void {
  // A baseline only stands for the board it was computed from.
  if (outcome.baseline && sameRead) {
    installation.baselineDay = outcome.baseline.day;
    installation.baselineRanks = outcome.baseline.ranks;
  }
  if (outcome.delivered && installation.activityPushToken === outcome.delivered.token) {
    installation.lastState = outcome.delivered.state;
    installation.lastStaleAt = outcome.delivered.staleAt;
  }
  if (outcome.endedActivityToken && installation.activityPushToken === outcome.endedActivityToken) clearActivity(installation);
  if (outcome.removedPushToStartToken && installation.pushToStartToken === outcome.removedPushToStartToken) {
    installation.pushToStartToken = null;
  }
  if (outcome.startedAt !== undefined) {
    installation.rotationAnchorAt = outcome.startedAt;
    installation.pendingStartAt = outcome.startedAt;
  }
}

async function persist(env: Env, deps: RelayDeps, installation: Installation, outcome: Outcome, now: number): Promise<void> {
  const changes = outcome.baseline || outcome.delivered || outcome.endedActivityToken || outcome.removedPushToStartToken || outcome.startedAt;
  if (!changes) return;
  let row: Installation | null = installation;
  for (let attempt = 0; attempt < 3 && row; attempt += 1) {
    apply(row, outcome, row.revision === outcome.readRevision);
    row.updatedAt = now;
    if (await saveInstallation(env.DB, row)) return;
    row = await getInstallation(env.DB, installation.id); // a device write won; re-apply to it
  }
  if (row) logEvent(deps.log, "installation_save_conflict", { install: installation.id });
}

/** Equal apart from `updatedAt`, which advances with every fetch. */
function sameContent(a: LiveRankState, b: LiveRankState): boolean {
  const neighbor = (n: LiveRankState["above"]) => (n === null ? "" : `${n.login}:${n.contributions}`);
  return (
    a.window === b.window &&
    a.rank === b.rank &&
    a.competitorCount === b.competitorCount &&
    a.contributions === b.contributions &&
    neighbor(a.above) === neighbor(b.above) &&
    neighbor(a.below) === neighbor(b.below) &&
    a.movementToday === b.movementToday
  );
}

function nonNegativeInt(value: string | undefined): number | undefined {
  const parsed = value === undefined ? NaN : Number(value);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : undefined;
}
