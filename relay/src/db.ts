import type { ApnsEnvironment } from "./apns";
import type { Window } from "./ranking";

export interface InstallationRow {
  id: string;
  secret_hash: string;
  apns_environment: ApnsEnvironment;
  push_to_start_token: string | null;
  activity_id: string | null;
  activity_push_token: string | null;
  activity_started_at: number | null;
  last_start_at: number | null;
  login: string;
  competitors_json: string;
  window: Window;
  time_zone: string;
  baseline_date: string | null;
  baseline_ranks_json: string | null;
  last_state_json: string | null;
  last_push_at: number | null;
  rate_window_start: number;
  rate_count: number;
  created_at: number;
  updated_at: number;
}

export interface Registration {
  pushToStartToken: string | null;
  login: string;
  competitors: string[];
  window: Window;
  timeZone: string;
  apnsEnvironment: ApnsEnvironment;
}

export interface CachedDays {
  attempted_at: number;
  fetched_at: number | null;
  days_json: string | null;
}

/** A login's last good days in the contribution cache. */
export interface CachedLoginDays {
  login: string;
  fetched_at: number;
  days_json: string;
}

export interface BoardTokenRow {
  token_hash: string;
  installation_id: string;
  label: string | null;
  created_at: number;
  revoked_at: number | null;
}

export class Store {
  constructor(private readonly db: D1Database) {}

  get(id: string): Promise<InstallationRow | null> {
    return this.db.prepare("SELECT * FROM installations WHERE id = ?").bind(id).first<InstallationRow>();
  }

  async all(): Promise<InstallationRow[]> {
    return (await this.db.prepare("SELECT * FROM installations").all<InstallationRow>()).results;
  }

  async create(id: string, secretHash: string, reg: Registration, now: number): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO installations (id, secret_hash, apns_environment, push_to_start_token, login,
           competitors_json, window, time_zone, rate_window_start, rate_count, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)`,
      )
      .bind(id, secretHash, reg.apnsEnvironment, reg.pushToStartToken, reg.login, JSON.stringify(reg.competitors),
        reg.window, reg.timeZone, now, now, now)
      .run();
  }

  async update(id: string, reg: Registration, resetBaseline: boolean, now: number): Promise<void> {
    await this.db
      .prepare(
        `UPDATE installations SET apns_environment = ?, push_to_start_token = ?, login = ?, competitors_json = ?,
           window = ?, time_zone = ?, updated_at = ?,
           baseline_date = CASE WHEN ? THEN NULL ELSE baseline_date END,
           baseline_ranks_json = CASE WHEN ? THEN NULL ELSE baseline_ranks_json END
         WHERE id = ?`,
      )
      .bind(reg.apnsEnvironment, reg.pushToStartToken, reg.login, JSON.stringify(reg.competitors), reg.window,
        reg.timeZone, now, resetBaseline ? 1 : 0, resetBaseline ? 1 : 0, id)
      .run();
  }

  async setActivity(id: string, activityId: string, pushToken: string, now: number): Promise<void> {
    // A new activity starts from a clean slate: the next cycle pushes the current state to it.
    await this.db
      .prepare(
        `UPDATE installations SET activity_id = ?, activity_push_token = ?, activity_started_at = ?,
           last_start_at = ?, last_state_json = NULL, last_push_at = NULL, updated_at = ? WHERE id = ?`,
      )
      .bind(activityId, pushToken, now, now, now, id)
      .run();
  }

  async recordWrite(id: string, windowStart: number, count: number): Promise<void> {
    await this.db
      .prepare("UPDATE installations SET rate_window_start = ?, rate_count = ? WHERE id = ?")
      .bind(windowStart, count, id)
      .run();
  }

  async delete(id: string): Promise<void> {
    await this.db.prepare("DELETE FROM installations WHERE id = ?").bind(id).run();
  }

  async save(row: InstallationRow): Promise<void> {
    await this.db
      .prepare(
        `UPDATE installations SET push_to_start_token = ?, activity_id = ?, activity_push_token = ?,
           activity_started_at = ?, last_start_at = ?, baseline_date = ?, baseline_ranks_json = ?,
           last_state_json = ?, last_push_at = ? WHERE id = ?`,
      )
      .bind(row.push_to_start_token, row.activity_id, row.activity_push_token, row.activity_started_at,
        row.last_start_at, row.baseline_date, row.baseline_ranks_json, row.last_state_json, row.last_push_at, row.id)
      .run();
  }

  // MARK: - Contribution cache, shared across installations

  getCached(login: string): Promise<CachedDays | null> {
    return this.db
      .prepare("SELECT attempted_at, fetched_at, days_json FROM contribution_cache WHERE login = ?")
      .bind(login)
      .first();
  }

  async putFetched(login: string, now: number, daysJson: string): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO contribution_cache (login, attempted_at, fetched_at, days_json, error) VALUES (?, ?, ?, ?, NULL)
         ON CONFLICT(login) DO UPDATE SET attempted_at = excluded.attempted_at, fetched_at = excluded.fetched_at,
           days_json = excluded.days_json, error = NULL`,
      )
      .bind(login, now, now, daysJson)
      .run();
  }

  /** A failed fetch keeps the last good days (stale beats missing) and records only the attempt. */
  async putFailed(login: string, now: number, error: string): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO contribution_cache (login, attempted_at, error) VALUES (?, ?, ?)
         ON CONFLICT(login) DO UPDATE SET attempted_at = excluded.attempted_at, error = excluded.error`,
      )
      .bind(login, now, error)
      .run();
  }

  /** Last good days for each login, whatever their age. Reads only: nothing is fetched. */
  async getCachedDays(logins: readonly string[]): Promise<CachedLoginDays[]> {
    const { results } = await this.db
      .prepare(
        `SELECT login, fetched_at, days_json FROM contribution_cache
         WHERE login IN (SELECT value FROM json_each(?)) AND fetched_at IS NOT NULL AND days_json IS NOT NULL`,
      )
      .bind(JSON.stringify(logins))
      .all<CachedLoginDays>();
    return results;
  }

  // MARK: - Board read tokens (minted by hand for now; see README)

  getBoardToken(tokenHash: string): Promise<BoardTokenRow | null> {
    return this.db.prepare("SELECT * FROM board_tokens WHERE token_hash = ?").bind(tokenHash).first<BoardTokenRow>();
  }
}
