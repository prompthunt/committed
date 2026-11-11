import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { LiveRankState } from "../src/liveRank";
import { createRelay } from "../src/relay";
import { Clock, FakeApns, FakeGitHub, HOUR, MINUTE } from "./support/fakes";

const SECRET = "k".repeat(40);
const PTS = "c3".repeat(40);
const ACTIVITY = "d4".repeat(40);
const BUNDLE = "com.example.app";

// 2026-11-05T15:00:00Z: 10:00 in New York, 00:00 on Nov 6 in Tokyo, 07:00 in Los Angeles.
const T0 = Date.UTC(2026, 10, 5, 15, 0) / 1000;

let apns: FakeApns;
let github: FakeGitHub;
let clock: Clock;
let relay: ReturnType<typeof createRelay>;

beforeEach(() => {
  apns = new FakeApns();
  github = new FakeGitHub();
  clock = new Clock(T0);
  relay = createRelay({ db: env.DB, apns, github: github.fetch, now: clock.now, bundleId: BUNDLE, log: () => {} });
});

async function put(path: string, body: unknown): Promise<Response> {
  const res = await relay.fetch(
    new Request(`https://relay.test${path}`, {
      method: "PUT",
      headers: { authorization: `Bearer ${SECRET}`, "content-type": "application/json" },
      body: JSON.stringify(body),
    }),
  );
  expect(res.ok).toBe(true);
  return res;
}

async function register(
  id: string,
  overrides: Partial<{ window: string; timeZone: string; competitors: string[]; pushToStartToken: string | null }> = {},
) {
  await put(`/v1/installations/${id}`, {
    pushToStartToken: PTS,
    login: "me",
    competitors: ["me", "alice", "bob"],
    window: "daily",
    timeZone: "America/New_York",
    apnsEnvironment: "sandbox",
    ...overrides,
  });
}

async function reportActivity(id: string, token = ACTIVITY, activityId = "act-1") {
  await put(`/v1/installations/${id}/activity`, { activityId, pushToken: token });
}

function lastState(): LiveRankState {
  return apns.sent.at(-1)!.payload.aps["content-state"];
}

const ID = "inst-0001";

describe("updates", () => {
  beforeEach(() => {
    github.set("me", { "2026-11-05": 5 });
    github.set("alice", { "2026-11-05": 9 });
    github.set("bob", { "2026-11-05": 1 });
  });

  it("pushes the derived Live rank as a liveactivity update with a stale date", async () => {
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();

    expect(apns.sent).toHaveLength(1);
    const push = apns.sent[0]!;
    expect(push.token).toBe(ACTIVITY);
    expect(push.environment).toBe("sandbox");
    expect(push.payload.aps.event).toBe("update");
    expect(push.payload.aps.timestamp).toBe(T0);
    expect(push.payload.aps["content-state"]).toEqual({
      window: "daily",
      rank: 2,
      competitorCount: 3,
      contributions: 5,
      above: { login: "alice", contributions: 9, movementToday: 0, streak: 1 },
      below: { login: "bob", contributions: 1, movementToday: 0, streak: 1 },
      movementToday: 0,
      streak: 1,
      updatedAt: T0,
    });
    expect(push.payload.aps["stale-date"]).toBe(T0 + 20 * MINUTE);
  });

  it("pushes only when the state changed", async () => {
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();
    apns.clear();

    clock.advance(5 * MINUTE);
    await relay.runCycle();
    expect(apns.sent).toHaveLength(0);

    github.set("me", { "2026-11-05": 6 });
    clock.advance(5 * MINUTE);
    await relay.runCycle();
    expect(apns.sent).toHaveLength(1);
    expect(lastState().contributions).toBe(6);
  });

  it("uses priority 10 only when your rank changed", async () => {
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();
    expect(apns.sent.at(-1)!.priority).toBe(5);

    github.set("me", { "2026-11-05": 7 }); // still #2
    clock.advance(5 * MINUTE);
    await relay.runCycle();
    expect(apns.sent.at(-1)!.priority).toBe(5);

    github.set("me", { "2026-11-05": 12 }); // passes alice: #1
    clock.advance(5 * MINUTE);
    await relay.runCycle();
    expect(lastState().rank).toBe(1);
    expect(apns.sent.at(-1)!.priority).toBe(10);
  });

  it("sends a heartbeat before the stale date when nothing changed", async () => {
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();
    apns.clear();

    for (let i = 0; i < 2; i++) {
      clock.advance(5 * MINUTE);
      await relay.runCycle();
    }
    expect(apns.sent).toHaveLength(0);

    clock.advance(5 * MINUTE); // 15 minutes since the last push; stale at 20
    await relay.runCycle();
    expect(apns.sent).toHaveLength(1);
    const heartbeat = apns.sent[0]!;
    expect(heartbeat.priority).toBe(5);
    expect(heartbeat.payload.aps["stale-date"]).toBeGreaterThan(clock.seconds);
    expect(heartbeat.payload.aps["content-state"].updatedAt).toBe(clock.seconds);
  });

  it("keeps the stale date ahead when a rival's page keeps failing", async () => {
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();
    github.fail("bob"); // e.g. a renamed account: 404 from now on, last good days kept
    apns.clear();

    for (let i = 0; i < 12; i++) {
      clock.advance(5 * MINUTE);
      await relay.runCycle();
    }
    expect(apns.sent.length).toBeGreaterThan(0); // heartbeats continue
    const last = apns.sent.at(-1)!.payload.aps;
    expect(last["stale-date"]).toBeGreaterThan(clock.seconds);
    // Bob's last good calendar keeps his count and his streak.
    expect(last["content-state"].below).toEqual({ login: "bob", contributions: 1, movementToday: 0, streak: 1 });
  });

  it("shows placeholders, not zero, when your counts can't be fetched", async () => {
    github.fail("me");
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();
    expect(lastState().contributions).toBeNull();
    expect(lastState().rank).toBeNull();
  });

  it("fetches each login once per 5 minutes across installations", async () => {
    await register("inst-000a");
    await register("inst-000b");
    await relay.runCycle();
    expect(github.requests.sort()).toEqual(["alice", "bob", "me"]);

    clock.advance(4 * MINUTE);
    await relay.runCycle();
    expect(github.requests).toHaveLength(3);

    clock.advance(MINUTE);
    await relay.runCycle();
    expect(github.requests).toHaveLength(6);
  });
});

describe("today's movement", () => {
  it("measures rank change against the day's first run", async () => {
    github.set("me", { "2026-11-05": 5 });
    github.set("alice", { "2026-11-05": 9 });
    github.set("bob", { "2026-11-05": 1 });
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();
    expect(lastState().movementToday).toBe(0);

    github.set("me", { "2026-11-05": 20 });
    clock.advance(5 * MINUTE);
    await relay.runCycle();
    expect(lastState().rank).toBe(1);
    expect(lastState().movementToday).toBe(1);
  });

  it("carries each neighbor's movement, so the island shows their chevrons too", async () => {
    github.set("me", { "2026-11-05": 5 });
    github.set("alice", { "2026-11-05": 9 });
    github.set("bob", { "2026-11-05": 1 });
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();

    // Bob passes you: you drop to #3 with Bob directly above, up one since the morning.
    github.set("bob", { "2026-11-05": 7 });
    clock.advance(5 * MINUTE);
    await relay.runCycle();
    expect(lastState().rank).toBe(3);
    expect(lastState().movementToday).toBe(-1);
    expect(lastState().above).toEqual({ login: "bob", contributions: 7, movementToday: 1, streak: 1 });
    expect(lastState().below).toBeNull();
  });

  it("reports no neighbor movement outside Today", async () => {
    github.set("me", { "2026-11-05": 5 });
    github.set("alice", { "2026-11-05": 9 });
    github.set("bob", { "2026-11-05": 1 });
    await register(ID, { window: "weekly" });
    await reportActivity(ID);
    await relay.runCycle();

    github.set("bob", { "2026-11-05": 7 });
    clock.advance(5 * MINUTE);
    await relay.runCycle();
    expect(lastState().above).toEqual({ login: "bob", contributions: 7, movementToday: 0, streak: 1 });
  });
});

describe("streaks", () => {
  it("pushes your streak and your neighbors', worked out from the calendars it reads", async () => {
    // 10:00 Nov 5 in New York. You've nothing yet today but a 3-day run up to yesterday; alice is
    // on day 2; bob stopped two days ago.
    github.set("me", { "2026-11-01": 0, "2026-11-02": 4, "2026-11-03": 1, "2026-11-04": 2, "2026-11-05": 0 });
    github.set("alice", { "2026-11-03": 0, "2026-11-04": 1, "2026-11-05": 3 });
    github.set("bob", { "2026-11-03": 8, "2026-11-04": 0, "2026-11-05": 0 });
    await register(ID, { window: "weekly" });
    await reportActivity(ID);
    await relay.runCycle();

    expect(lastState()).toStrictEqual({
      window: "weekly",
      rank: 2,
      competitorCount: 3,
      contributions: 7,
      above: { login: "bob", contributions: 8, movementToday: 0, streak: 0 },
      below: { login: "alice", contributions: 4, movementToday: 0, streak: 2 },
      movementToday: 0,
      streak: 3,
      updatedAt: T0,
    });
  });

  it("pushes again when only a streak changed", async () => {
    github.set("me", { "2026-11-04": 2, "2026-11-05": 0 });
    github.set("alice", { "2026-11-04": 9, "2026-11-05": 0 });
    github.set("bob", { "2026-11-05": 0 });
    await register(ID, { window: "weekly" });
    await reportActivity(ID);
    await relay.runCycle();
    expect(lastState().streak).toBe(1);
    apns.clear();

    // You contribute today and yesterday's count drops by one: the same weekly total, a longer run.
    github.set("me", { "2026-11-03": 0, "2026-11-04": 1, "2026-11-05": 1 });
    clock.advance(5 * MINUTE);
    await relay.runCycle();
    expect(apns.sent).toHaveLength(1);
    expect(lastState().contributions).toBe(2);
    expect(lastState().streak).toBe(2);
  });

  it("leaves your streak out while your count can't be fetched", async () => {
    github.set("alice", { "2026-11-05": 9 });
    github.set("bob", { "2026-11-05": 1 });
    github.fail("me");
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();
    expect(lastState().contributions).toBeNull();
    expect("streak" in lastState()).toBe(false);
  });
});

describe("local midnight", () => {
  it("resets Today and its baseline at each installation's own midnight", async () => {
    // Just before T0: 23:55 Nov 5 in Tokyo, 06:55 Nov 5 in Los Angeles.
    clock.seconds = T0 - 5 * MINUTE;
    github.set("me", { "2026-11-05": 4, "2026-11-06": 0 });
    github.set("alice", { "2026-11-05": 9, "2026-11-06": 0 });
    github.set("bob", { "2026-11-05": 1, "2026-11-06": 0 });
    await register("inst-tokyo", { timeZone: "Asia/Tokyo" });
    await register("inst-la-00", { timeZone: "America/Los_Angeles" });
    await reportActivity("inst-tokyo", "e5".repeat(40), "act-tokyo");
    await reportActivity("inst-la-00", "f6".repeat(40), "act-la");
    await relay.runCycle();

    const stateFor = (token: string) =>
      apns.sent.filter((push) => push.token === token).at(-1)!.payload.aps["content-state"];
    expect(stateFor("e5".repeat(40)).contributions).toBe(4);
    expect(stateFor("f6".repeat(40)).contributions).toBe(4);

    // Me passes alice late on Nov 5: Tokyo is already on Nov 6, LA isn't.
    github.set("me", { "2026-11-05": 30, "2026-11-06": 0 });
    clock.seconds = T0;
    apns.clear();
    await relay.runCycle();

    const tokyo = stateFor("e5".repeat(40));
    expect(tokyo.contributions).toBe(0); // new local day, Today reset in place
    expect(tokyo.movementToday).toBe(0); // fresh baseline
    expect(apns.sent.filter((push) => push.token === "e5".repeat(40))[0]!.payload.aps.event).toBe("update");

    const la = stateFor("f6".repeat(40));
    expect(la.contributions).toBe(30);
    expect(la.rank).toBe(1);
    expect(la.movementToday).toBe(1);
  });
});

describe("rotation", () => {
  beforeEach(() => {
    github.set("me", { "2026-11-05": 5 });
    github.set("alice", { "2026-11-05": 9 });
    github.set("bob", { "2026-11-05": 1 });
  });

  it("at 7.5 hours ends the activity immediately, then push-to-starts a fresh one", async () => {
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();
    apns.clear();

    clock.advance(7 * HOUR + 25 * MINUTE);
    await relay.runCycle();
    expect(apns.events()).not.toContain(`end:${ACTIVITY}`);

    clock.advance(5 * MINUTE); // 7.5 hours
    apns.clear();
    await relay.runCycle();
    expect(apns.events()).toEqual([`end:${ACTIVITY}`, `start:${PTS}`]);

    const end = apns.sent[0]!.payload.aps;
    expect(end["dismissal-date"]).toBe(clock.seconds);

    const start = apns.sent[1]!.payload.aps;
    expect(start["attributes-type"]).toBe("LiveRankAttributes");
    expect(start.attributes).toEqual({ selfLogin: "me" });
    expect(start["content-state"].rank).toBe(2);
    expect(start["stale-date"]).toBe(start["content-state"].updatedAt + 20 * MINUTE);

    // The old activity is forgotten; nothing more until the device reports the new one.
    apns.clear();
    clock.advance(5 * MINUTE);
    await relay.runCycle();
    expect(apns.sent).toHaveLength(0);

    await reportActivity(ID, "a7".repeat(40), "act-2");
    await relay.runCycle();
    expect(apns.events()).toEqual([`update:${"a7".repeat(40)}`]);
  });

  it("without an activity, restarts with push-to-start at most every 7.5 hours", async () => {
    await register(ID);
    await relay.runCycle();
    expect(apns.sent).toHaveLength(0); // just registered: the device starts the first activity

    clock.advance(7 * HOUR + 30 * MINUTE);
    await relay.runCycle();
    expect(apns.events()).toEqual([`start:${PTS}`]);

    apns.clear();
    for (let i = 0; i < 16; i++) {
      clock.advance(30 * MINUTE);
      await relay.runCycle();
    }
    expect(apns.events()).toEqual([`start:${PTS}`]); // once more, 7.5 hours after the last start
  });

  it("does nothing without any token", async () => {
    await register(ID, { pushToStartToken: null });
    clock.advance(8 * HOUR);
    await relay.runCycle();
    expect(apns.sent).toHaveLength(0);
  });
});

describe("dead tokens", () => {
  beforeEach(() => {
    github.set("me", { "2026-11-05": 5 });
    github.set("alice", { "2026-11-05": 9 });
    github.set("bob", { "2026-11-05": 1 });
  });

  it("clears the activity token on 410", async () => {
    await register(ID);
    await reportActivity(ID);
    apns.respond(ACTIVITY, { status: 410, reason: "Unregistered" });
    await relay.runCycle();
    const row = await env.DB.prepare("SELECT * FROM installations WHERE id = ?").bind(ID).first<Record<string, unknown>>();
    expect(row!.activity_push_token).toBeNull();
    expect(row!.activity_id).toBeNull();
    expect(row!.push_to_start_token).toBe(PTS);

    apns.clear();
    clock.advance(5 * MINUTE);
    await relay.runCycle();
    expect(apns.sent).toHaveLength(0);
  });

  it("clears the push-to-start token on BadDeviceToken", async () => {
    await register(ID);
    apns.respond(PTS, { status: 400, reason: "BadDeviceToken" });
    clock.advance(8 * HOUR);
    await relay.runCycle();
    const row = await env.DB.prepare("SELECT * FROM installations WHERE id = ?").bind(ID).first<Record<string, unknown>>();
    expect(row!.push_to_start_token).toBeNull();
  });
});

describe("you first", () => {
  // Rows saved before the relay put self first keep the device's order in D1. The cycle must
  // still rank you ahead of anyone you tie, or "1 to pass" would name someone you're level with.
  it("ranks you ahead of a rival you tie, even when the stored board lists you later", async () => {
    github.set("me", { "2026-11-05": 5 });
    github.set("alice", { "2026-11-05": 5 });
    github.set("bob", { "2026-11-05": 6 });
    await register(ID);
    await env.DB.prepare("UPDATE installations SET competitors_json = ? WHERE id = ?")
      .bind(JSON.stringify(["alice", "me", "bob"]), ID)
      .run();
    await reportActivity(ID);
    await relay.runCycle();

    expect(lastState()).toMatchObject({
      rank: 2,
      competitorCount: 3,
      above: { login: "bob", contributions: 6 },
      below: { login: "alice", contributions: 5 },
    });
  });
});

describe("logging", () => {
  afterEach(() => vi.restoreAllMocks());

  it("never logs push tokens or the install secret", async () => {
    const lines: string[] = [];
    for (const method of ["log", "info", "warn", "error", "debug"] as const) {
      vi.spyOn(console, method).mockImplementation((...args: unknown[]) => {
        lines.push(args.map(String).join(" "));
      });
    }
    // Default logger this time.
    relay = createRelay({ db: env.DB, apns, github: github.fetch, now: clock.now, bundleId: BUNDLE });
    github.set("me", { "2026-11-05": 5 });
    github.fail("alice");
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();
    apns.respond(ACTIVITY, { status: 410, reason: "Unregistered" });
    github.set("me", { "2026-11-05": 6 });
    clock.advance(5 * MINUTE);
    await relay.runCycle();
    clock.advance(8 * HOUR);
    await relay.runCycle();
    await relay.fetch(
      new Request(`https://relay.test/v1/installations/${ID}`, {
        method: "DELETE",
        headers: { authorization: `Bearer ${SECRET}` },
      }),
    );

    expect(lines.length).toBeGreaterThan(0);
    const all = lines.join("\n");
    for (const secret of [PTS, ACTIVITY, SECRET]) expect(all).not.toContain(secret);
  });

  it("names each push line push_sent or push_failed, with the APNs event beside it", async () => {
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    // Default logger: the line it prints is what log search sees.
    relay = createRelay({ db: env.DB, apns, github: github.fetch, now: clock.now, bundleId: BUNDLE });
    github.set("me", { "2026-11-05": 5 });
    github.set("alice", { "2026-11-05": 9 });
    await register(ID);
    await reportActivity(ID);
    await relay.runCycle();
    apns.respond(ACTIVITY, { status: 400, reason: "BadDeviceToken" });
    github.set("me", { "2026-11-05": 6 });
    clock.advance(5 * MINUTE);
    await relay.runCycle();

    const pushes = lines
      .map((line) => JSON.parse(line) as Record<string, unknown>)
      .filter((entry) => entry.apsEvent !== undefined)
      .map((entry) => [entry.event, entry.apsEvent]);
    expect(pushes).toEqual([
      ["push_sent", "update"],
      ["push_failed", "update"],
    ]);
  });
});
