// D1 access for installations. Rows never contain a GitHub token or the raw install secret.

import type { ApnsEnvironment } from "./apns";
import type { LiveRankState } from "./ranking";
import type { ContributionWindow } from "./types";

export interface Installation {
  id: string;
  secretHash: string;
  environment: ApnsEnvironment;
  pushToStartToken: string | null;
  login: string;
  /** Visible logins in roster order, self included. */
  competitors: string[];
  window: ContributionWindow;
  timeZone: string;
  activityId: string | null;
  activityPushToken: string | null;
  activityStartedAt: number | null;
  rotationAnchorAt: number;
  /** Send time of a push-to-start no reported activity has claimed yet: that activity's age. */
  pendingStartAt: number | null;
  lastState: LiveRankState | null;
  lastStaleAt: number | null;
  baselineDay: string | null;
  baselineRanks: Record<string, number> | null;
  rateWindowStart: number;
  rateCount: number;
  /** Bumped on every write. A write that read an older revision is dropped. */
  revision: number;
  createdAt: number;
  updatedAt: number;
}

interface Row {
  id: string;
  secret_hash: string;
  environment: string;
  push_to_start_token: string | null;
  login: string;
  competitors: string;
  window: string;
  time_zone: string;
  activity_id: string | null;
  activity_push_token: string | null;
  activity_started_at: number | null;
  rotation_anchor_at: number;
  pending_start_at: number | null;
  last_state: string | null;
  last_stale_at: number | null;
  baseline_day: string | null;
  baseline_ranks: string | null;
  rate_window_start: number;
  rate_count: number;
  revision: number;
  created_at: number;
  updated_at: number;
}

function fromRow(row: Row): Installation {
  return {
    id: row.id,
    secretHash: row.secret_hash,
    environment: row.environment as ApnsEnvironment,
    pushToStartToken: row.push_to_start_token,
    login: row.login,
    competitors: JSON.parse(row.competitors) as string[],
    window: row.window as ContributionWindow,
    timeZone: row.time_zone,
    activityId: row.activity_id,
    activityPushToken: row.activity_push_token,
    activityStartedAt: row.activity_started_at,
    rotationAnchorAt: row.rotation_anchor_at,
    pendingStartAt: row.pending_start_at,
    lastState: row.last_state === null ? null : (JSON.parse(row.last_state) as LiveRankState),
    lastStaleAt: row.last_stale_at,
    baselineDay: row.baseline_day,
    baselineRanks: row.baseline_ranks === null ? null : (JSON.parse(row.baseline_ranks) as Record<string, number>),
    rateWindowStart: row.rate_window_start,
    rateCount: row.rate_count,
    revision: row.revision,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function getInstallation(db: D1Database, id: string): Promise<Installation | null> {
  const row = await db.prepare("SELECT * FROM installations WHERE id = ?").bind(id).first<Row>();
  return row ? fromRow(row) : null;
}

export async function listInstallations(db: D1Database): Promise<Installation[]> {
  const { results } = await db.prepare("SELECT * FROM installations ORDER BY id").all<Row>();
  return results.map(fromRow);
}

/**
 * Inserts a new installation, or updates one only if nobody wrote it since it was read
 * (`installation.revision` is the revision read). Returns false when another write won.
 */
export async function saveInstallation(db: D1Database, installation: Installation, isNew = false): Promise<boolean> {
  const i = installation;
  const values = [
    i.secretHash,
    i.environment,
    i.pushToStartToken,
    i.login,
    JSON.stringify(i.competitors),
    i.window,
    i.timeZone,
    i.activityId,
    i.activityPushToken,
    i.activityStartedAt,
    i.rotationAnchorAt,
    i.lastState === null ? null : JSON.stringify(i.lastState),
    i.lastStaleAt,
    i.baselineDay,
    i.baselineRanks === null ? null : JSON.stringify(i.baselineRanks),
    i.rateWindowStart,
    i.rateCount,
    i.updatedAt,
    i.pendingStartAt,
  ];
  const statement = isNew
    ? db
        .prepare(
          `INSERT INTO installations (secret_hash, environment, push_to_start_token, login, competitors, window,
             time_zone, activity_id, activity_push_token, activity_started_at, rotation_anchor_at, last_state,
             last_stale_at, baseline_day, baseline_ranks, rate_window_start, rate_count, updated_at,
             pending_start_at, id, created_at, revision)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, 1)
           ON CONFLICT (id) DO NOTHING`,
        )
        .bind(...values, i.id, i.createdAt)
    : db
        .prepare(
          `UPDATE installations SET secret_hash = ?1, environment = ?2, push_to_start_token = ?3, login = ?4,
             competitors = ?5, window = ?6, time_zone = ?7, activity_id = ?8, activity_push_token = ?9,
             activity_started_at = ?10, rotation_anchor_at = ?11, last_state = ?12, last_stale_at = ?13,
             baseline_day = ?14, baseline_ranks = ?15, rate_window_start = ?16, rate_count = ?17,
             updated_at = ?18, pending_start_at = ?19, revision = revision + 1
           WHERE id = ?20 AND revision = ?21`,
        )
        .bind(...values, i.id, i.revision);
  const result = await statement.run();
  return result.meta.changes === 1;
}

export async function deleteInstallation(db: D1Database, id: string): Promise<void> {
  await db.prepare("DELETE FROM installations WHERE id = ?").bind(id).run();
}

/** Forget the current activity (ended, rotated, or its token was rejected). */
export function clearActivity(installation: Installation): void {
  installation.activityId = null;
  installation.activityPushToken = null;
  installation.activityStartedAt = null;
  installation.lastState = null;
  installation.lastStaleAt = null;
}
