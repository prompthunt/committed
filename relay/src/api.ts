// Device API (JSON over HTTPS, `Authorization: Bearer <install secret>`):
//   PUT    /v1/installations/{id}           register or update
//   PUT    /v1/installations/{id}/activity  report the current Live Activity and its push token
//   DELETE /v1/installations/{id}           unregister and end the activity
// The first PUT for an ID sets its secret; only the secret's SHA-256 is stored. Bodies are strict:
// unknown fields are rejected, so a GitHub token can't be sent, stored, or logged.

import { sendPush, type ApnsEnvironment } from "./apns";
import type { RelayDeps } from "./app";
import type { Env } from "./env";
import { logEvent } from "./log";
import { END_PRIORITY, endPayload, placeholderState } from "./payload";
import { clearActivity, deleteInstallation, getInstallation, saveInstallation, type Installation } from "./store";
import { WINDOWS, type ContributionWindow } from "./types";

export const MAX_COMPETITORS = 1000;
export const RATE_WINDOW_SECONDS = 600;
export const RATE_LIMIT = 30;

const ROUTE = /^\/v1\/installations\/([A-Za-z0-9-]{8,64})(\/activity)?$/;
const HEX_TOKEN = /^[0-9a-fA-F]{32,512}$/;
const MIN_SECRET = 32;
const MAX_SECRET = 256;

export async function handleRequest(request: Request, env: Env, deps: RelayDeps): Promise<Response> {
  const url = new URL(request.url);
  const route = ROUTE.exec(url.pathname);
  if (!route) return error(404, "not found");
  const id = route[1]!;
  const isActivity = route[2] !== undefined;
  const allowed = isActivity ? ["PUT"] : ["PUT", "DELETE"];
  if (!allowed.includes(request.method)) {
    return error(405, "method not allowed", { allow: allowed.join(", ") });
  }

  const secret = bearer(request);
  if (secret === null) return error(401, "missing or malformed install secret");
  const secretHash = await sha256Hex(secret);
  const existing = await getInstallation(env.DB, id);
  if (existing && !(await sameDigest(existing.secretHash, secretHash))) return error(401, "wrong install secret");

  if (request.method === "DELETE") return unregister(env, deps, id, existing);
  if (isActivity && !existing) return error(404, "unknown installation");

  const now = deps.now();
  if (existing) {
    const limited = rateLimit(existing, now);
    if (limited) {
      logEvent(deps.log, "rate_limited", { install: id });
      return limited;
    }
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return error(400, "body must be JSON");
  }

  if (isActivity) return reportActivity(env, deps, existing!, body, now);
  return register(env, deps, id, secretHash, existing, body, now);
}

async function register(
  env: Env,
  deps: RelayDeps,
  id: string,
  secretHash: string,
  existing: Installation | null,
  body: unknown,
  now: number,
): Promise<Response> {
  const parsed = parseRegistration(body);
  if (typeof parsed === "string") return error(400, parsed);

  const installation: Installation = existing ?? {
    id,
    secretHash,
    environment: parsed.environment,
    pushToStartToken: null,
    login: parsed.login,
    competitors: parsed.competitors,
    window: parsed.window,
    timeZone: parsed.timeZone,
    activityId: null,
    activityPushToken: null,
    activityStartedAt: null,
    // A new installation waits a full rotation before the relay starts an activity on its own:
    // the app starts the first one itself, and a missing activity means the user dismissed it.
    rotationAnchorAt: now,
    pendingStartAt: null,
    lastState: null,
    lastStaleAt: null,
    baselineDay: null,
    baselineRanks: null,
    rateWindowStart: now,
    rateCount: 1,
    revision: 0,
    createdAt: now,
    updatedAt: now,
  };

  const boardChanged =
    installation.window !== parsed.window ||
    installation.timeZone !== parsed.timeZone ||
    installation.login !== parsed.login ||
    installation.competitors.join(",") !== parsed.competitors.join(",");
  if (boardChanged) {
    // Mirrors RefreshCoordinator re-baselining when the visible board changes.
    installation.baselineDay = null;
    installation.baselineRanks = null;
  }
  if (installation.window !== parsed.window) {
    // The app ends the old activity and starts one for the new Window; push its first state.
    installation.lastState = null;
    installation.lastStaleAt = null;
  }
  installation.environment = parsed.environment;
  installation.pushToStartToken = parsed.pushToStartToken;
  installation.login = parsed.login;
  installation.competitors = parsed.competitors;
  installation.window = parsed.window;
  installation.timeZone = parsed.timeZone;
  installation.updatedAt = now;

  if (!(await saveInstallation(env.DB, installation, existing === null))) return error(409, "concurrent update, retry");
  logEvent(deps.log, existing ? "installation_updated" : "installation_registered", {
    install: id,
    competitors: parsed.competitors.length,
    window: parsed.window,
  });
  return new Response(null, { status: 204 });
}

async function reportActivity(env: Env, deps: RelayDeps, installation: Installation, body: unknown, now: number): Promise<Response> {
  if (!isRecord(body) || !onlyKeys(body, ["activityId", "pushToken", "startedAt"])) return error(400, "unexpected fields");
  const { activityId, pushToken, startedAt } = body;
  if (typeof activityId !== "string" || activityId.length < 1 || activityId.length > 128) return error(400, "bad activityId");
  if (typeof pushToken !== "string" || !HEX_TOKEN.test(pushToken)) return error(400, "bad pushToken");
  // Optional (older apps omit it): Unix seconds the app started this activity.
  if (startedAt !== undefined && !(Number.isSafeInteger(startedAt) && (startedAt as number) >= 0)) {
    return error(400, "bad startedAt");
  }

  if (installation.activityId === activityId) {
    // Same activity, rotated push token: keep its age so the 7.5-hour rotation stays on schedule.
    installation.activityPushToken = pushToken.toLowerCase();
  } else {
    installation.activityId = activityId;
    installation.activityPushToken = pushToken.toLowerCase();
    // Its age counts from when it started: the app's own start time, or for one the relay
    // started, the push-to-start's send time. Never later than now.
    const started = typeof startedAt === "number" ? startedAt : (installation.pendingStartAt ?? now);
    installation.activityStartedAt = Math.min(started, now);
    installation.rotationAnchorAt = Math.min(started, now);
    installation.pendingStartAt = null;
    installation.lastState = null;
    installation.lastStaleAt = null;
  }
  installation.updatedAt = now;
  if (!(await saveInstallation(env.DB, installation))) return error(409, "concurrent update, retry");
  logEvent(deps.log, "activity_reported", { install: installation.id });
  return new Response(null, { status: 204 });
}

async function unregister(env: Env, deps: RelayDeps, id: string, existing: Installation | null): Promise<Response> {
  if (!existing) return new Response(null, { status: 204 });
  const now = deps.now();
  if (existing.activityPushToken) {
    const state = existing.lastState ?? placeholderState(existing.window, existing.competitors.length, now);
    try {
      const result = await sendPush(deps, env, {
        environment: existing.environment,
        token: existing.activityPushToken,
        priority: END_PRIORITY,
        payload: endPayload(state, now),
      });
      logEvent(deps.log, "activity_end_sent", { install: id, status: result.status, reason: result.reason });
    } catch (cause) {
      logEvent(deps.log, "activity_end_failed", { install: id, error: String(cause) });
    }
    clearActivity(existing);
  }
  await deleteInstallation(env.DB, id);
  logEvent(deps.log, "installation_deleted", { install: id });
  return new Response(null, { status: 204 });
}

interface Registration {
  login: string;
  competitors: string[];
  window: ContributionWindow;
  timeZone: string;
  environment: ApnsEnvironment;
  pushToStartToken: string | null;
}

const REGISTRATION_KEYS = ["login", "competitors", "window", "timeZone", "environment", "pushToStartToken"];

function parseRegistration(body: unknown): Registration | string {
  if (!isRecord(body)) return "body must be an object";
  if (!onlyKeys(body, REGISTRATION_KEYS)) return "unexpected fields";
  const login = typeof body.login === "string" ? normalizeLogin(body.login) : null;
  if (!login) return "bad login";
  if (!Array.isArray(body.competitors)) return "competitors must be an array";
  if (body.competitors.length > MAX_COMPETITORS) return `at most ${MAX_COMPETITORS} competitors`;
  const competitors: string[] = [];
  for (const raw of body.competitors) {
    const normalized = typeof raw === "string" ? normalizeLogin(raw) : null;
    if (!normalized) return "bad competitor login";
    if (!competitors.includes(normalized)) competitors.push(normalized);
  }
  if (!competitors.includes(login)) return "competitors must include login";
  if (typeof body.window !== "string" || !WINDOWS.includes(body.window as ContributionWindow)) return "bad window";
  if (typeof body.timeZone !== "string" || !isTimeZone(body.timeZone)) return "bad timeZone";
  if (body.environment !== "sandbox" && body.environment !== "production") return "bad environment";
  const token = body.pushToStartToken;
  if (token !== undefined && token !== null && (typeof token !== "string" || !HEX_TOKEN.test(token))) {
    return "bad pushToStartToken";
  }
  return {
    login,
    competitors,
    window: body.window as ContributionWindow,
    timeZone: body.timeZone,
    environment: body.environment,
    pushToStartToken: typeof token === "string" ? token.toLowerCase() : null,
  };
}

/** UsernameNormalization.normalize from the Swift app. */
export function normalizeLogin(raw: string): string | null {
  let login = raw.trim();
  if (login.startsWith("@")) login = login.slice(1);
  login = login.toLowerCase();
  if (login.length === 0 || login.length > 39) return null;
  if (!/^[a-z0-9-]+$/.test(login)) return null;
  if (login.startsWith("-") || login.endsWith("-") || login.includes("--")) return null;
  return login;
}

function isTimeZone(zone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}

function rateLimit(installation: Installation, now: number): Response | null {
  if (now - installation.rateWindowStart >= RATE_WINDOW_SECONDS) {
    installation.rateWindowStart = now;
    installation.rateCount = 0;
  }
  if (installation.rateCount >= RATE_LIMIT) {
    const retryAfter = Math.max(1, Math.ceil(installation.rateWindowStart + RATE_WINDOW_SECONDS - now));
    return error(429, "too many updates", { "retry-after": String(retryAfter) });
  }
  installation.rateCount += 1;
  return null;
}

function bearer(request: Request): string | null {
  const header = request.headers.get("authorization");
  const match = header ? /^Bearer (\S+)$/.exec(header) : null;
  const secret = match?.[1];
  if (!secret || secret.length < MIN_SECRET || secret.length > MAX_SECRET) return null;
  return secret;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sameDigest(a: string, b: string): Promise<boolean> {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  return left.byteLength === right.byteLength && crypto.subtle.timingSafeEqual(left, right);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function onlyKeys(value: Record<string, unknown>, allowed: string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}

function error(status: number, message: string, headers: Record<string, string> = {}): Response {
  return Response.json({ error: message }, { status, headers });
}
