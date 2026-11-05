import { endPayload, type ApnsEnvironment, type ApnsSender } from "./apns";
import { Store, type InstallationRow, type Registration } from "./db";
import { runCycle } from "./cycle";
import type { LiveRankState } from "./liveRank";
import { isValidTimeZone } from "./parser";
import { WINDOWS, type Window } from "./ranking";

/** Fetches the public `github.com/users/<login>/contributions` HTML. Never authenticated. */
export type GitHubFetch = (login: string) => Promise<string>;

/** Structured log sink. Callers pass ids and event names only: never tokens or secrets. */
export type Log = (event: string, fields?: Record<string, string | number | boolean | null>) => void;

export interface RelayDeps {
  db: D1Database;
  apns: ApnsSender;
  github: GitHubFetch;
  /** Unix seconds. */
  now: () => number;
  bundleId: string;
  log?: Log;
}

export const MAX_COMPETITORS = 1000;
export const RATE_LIMIT_WINDOW_SECONDS = 10 * 60;
export const RATE_LIMIT_MAX_WRITES = 30;
const MAX_BODY_BYTES = 128 * 1024;
const MIN_SECRET_LENGTH = 32;

const ID_PATTERN = /^[A-Za-z0-9-]{8,64}$/;
const HEX_TOKEN = /^[0-9a-f]{16,512}$/;
// GitHub logins: alphanumerics and single hyphens, 1–39 chars (UsernameNormalization in Swift).
const LOGIN_PATTERN = /^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,38}$/;

export const defaultLog: Log = (event, fields = {}) => {
  console.log(JSON.stringify({ event, ...fields }));
};

export function createRelay(deps: RelayDeps) {
  const store = new Store(deps.db);
  const log = deps.log ?? defaultLog;

  async function fetchHandler(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/" && request.method === "GET") return text(200, "Committed relay");

    const match = url.pathname.match(/^\/v1\/installations\/([^/]+)(\/activity)?$/);
    if (!match || !ID_PATTERN.test(match[1]!)) return json(404, { error: "not_found" });
    const id = match[1]!;
    const isActivity = match[2] !== undefined;

    const secret = bearer(request);
    if (!secret) return json(401, { error: "unauthorized" });
    const secretHash = await sha256Hex(secret);
    const existing = await store.get(id);
    if (existing && !(await sameHash(existing.secret_hash, secretHash))) return json(401, { error: "unauthorized" });

    if (request.method === "DELETE" && !isActivity) {
      if (!existing) return new Response(null, { status: 204 });
      await endActivity(existing);
      await store.delete(id);
      log("installation_deleted", { id });
      return new Response(null, { status: 204 });
    }
    if (request.method !== "PUT") return json(405, { error: "method_not_allowed" });

    if (existing && !(await allowWrite(existing))) return json(429, { error: "rate_limited" });

    const body = await readJson(request);
    if (body === undefined) return json(400, { error: "invalid_json" });

    if (isActivity) {
      if (!existing) return json(404, { error: "not_registered" });
      const activity = parseActivity(body);
      if (typeof activity === "string") return json(400, { error: activity });
      await store.setActivity(id, activity.activityId, activity.pushToken, deps.now());
      log("activity_registered", { id });
      return json(200, { ok: true });
    }

    const registration = parseRegistration(body);
    if (typeof registration === "string") return json(400, { error: registration });
    if (!existing) {
      await store.create(id, secretHash, registration, deps.now());
      log("installation_created", { id, competitors: registration.competitors.length });
      return json(201, { ok: true });
    }
    // A changed board (hide/show, roster sync) invalidates today's movement baseline,
    // as a visibility change does in RefreshCoordinator.
    const resetBaseline = existing.competitors_json !== JSON.stringify(registration.competitors);
    await store.update(id, registration, resetBaseline, deps.now());
    log("installation_updated", { id, competitors: registration.competitors.length });
    return json(200, { ok: true });
  }

  async function allowWrite(row: InstallationRow): Promise<boolean> {
    const now = deps.now();
    if (now - row.rate_window_start >= RATE_LIMIT_WINDOW_SECONDS) {
      await store.recordWrite(row.id, now, 1);
      return true;
    }
    if (row.rate_count >= RATE_LIMIT_MAX_WRITES) {
      log("rate_limited", { id: row.id });
      return false;
    }
    await store.recordWrite(row.id, row.rate_window_start, row.rate_count + 1);
    return true;
  }

  async function endActivity(row: InstallationRow): Promise<void> {
    if (!row.activity_push_token) return;
    const now = deps.now();
    const state = row.last_state_json ? (JSON.parse(row.last_state_json) as LiveRankState) : placeholderState(row, now);
    const result = await deps.apns.send({
      token: row.activity_push_token,
      environment: row.apns_environment,
      priority: 10,
      payload: endPayload(state, now),
    });
    log("activity_ended", { id: row.id, status: result.status, reason: result.reason ?? null });
  }

  return {
    fetch: fetchHandler,
    /** One cron run: recompute every installation's Live rank and push what changed. */
    runCycle: () => runCycle({ store, apns: deps.apns, github: deps.github, now: deps.now, log }),
  };
}

export function placeholderState(row: InstallationRow, now: number): LiveRankState {
  const competitors = JSON.parse(row.competitors_json) as string[];
  return {
    window: row.window,
    rank: null,
    competitorCount: competitors.length,
    contributions: null,
    above: null,
    below: null,
    movementToday: 0,
    updatedAt: now,
  };
}

// MARK: - Validation

const REGISTRATION_KEYS = new Set(["pushToStartToken", "login", "competitors", "window", "timeZone", "apnsEnvironment"]);
const ACTIVITY_KEYS = new Set(["activityId", "pushToken"]);

/** Returns the registration, or an error code. Unknown keys are rejected so a GitHub token can't be accepted. */
function parseRegistration(body: unknown): Registration | string {
  if (!isObject(body)) return "invalid_body";
  for (const key of Object.keys(body)) if (!REGISTRATION_KEYS.has(key)) return `unknown_field:${key}`;

  const pushToStartToken = body.pushToStartToken ?? null;
  if (pushToStartToken !== null && !(typeof pushToStartToken === "string" && HEX_TOKEN.test(pushToStartToken))) {
    return "invalid_push_to_start_token";
  }
  const login = normalizeLogin(body.login);
  if (!login) return "invalid_login";
  if (!Array.isArray(body.competitors)) return "invalid_competitors";
  const normalized = body.competitors.map(normalizeLogin);
  if (normalized.some((competitor) => competitor === null)) return "invalid_competitors";
  // Keep the board order the device sent (it matters for ties); self goes first if missing.
  const unique = [...new Set(normalized as string[])];
  const competitors = unique.includes(login) ? unique : [login, ...unique];
  if (competitors.length > MAX_COMPETITORS) return "too_many_competitors";

  if (typeof body.window !== "string" || !WINDOWS.includes(body.window as Window)) return "invalid_window";
  if (typeof body.timeZone !== "string" || !isValidTimeZone(body.timeZone)) return "invalid_time_zone";
  if (body.apnsEnvironment !== "sandbox" && body.apnsEnvironment !== "production") return "invalid_apns_environment";

  return {
    pushToStartToken: pushToStartToken as string | null,
    login,
    competitors,
    window: body.window as Window,
    timeZone: body.timeZone,
    apnsEnvironment: body.apnsEnvironment as ApnsEnvironment,
  };
}

function parseActivity(body: unknown): { activityId: string; pushToken: string } | string {
  if (!isObject(body)) return "invalid_body";
  for (const key of Object.keys(body)) if (!ACTIVITY_KEYS.has(key)) return `unknown_field:${key}`;
  if (typeof body.activityId !== "string" || body.activityId.length === 0 || body.activityId.length > 128) {
    return "invalid_activity_id";
  }
  if (typeof body.pushToken !== "string" || !HEX_TOKEN.test(body.pushToken)) return "invalid_push_token";
  return { activityId: body.activityId, pushToken: body.pushToken };
}

function normalizeLogin(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  let login = raw.trim();
  if (login.startsWith("@")) login = login.slice(1);
  login = login.toLowerCase();
  return LOGIN_PATTERN.test(login) ? login : null;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// MARK: - HTTP helpers

function bearer(request: Request): string | null {
  const header = request.headers.get("authorization") ?? "";
  const match = header.match(/^Bearer\s+(\S+)$/i);
  const secret = match?.[1];
  return secret && secret.length >= MIN_SECRET_LENGTH && secret.length <= 256 ? secret : null;
}

async function readJson(request: Request): Promise<unknown> {
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return undefined;
  try {
    return JSON.parse(raw);
  } catch {
    return undefined;
  }
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sameHash(a: string, b: string): Promise<boolean> {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  return left.byteLength === right.byteLength && crypto.subtle.timingSafeEqual(left, right);
}

function json(status: number, body: unknown): Response {
  return Response.json(body, { status });
}

function text(status: number, body: string): Response {
  return new Response(body, { status, headers: { "content-type": "text/plain" } });
}
