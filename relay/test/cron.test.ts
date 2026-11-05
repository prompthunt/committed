import { describe, expect, it } from "vitest";
import { ACTIVITY_TOKEN, INSTALL, PTS_TOKEN, T0, makeRelay, registration, type TestRelay } from "./helpers";

const path = `/v1/installations/${INSTALL}`;
const ROTATION = 7.5 * 3600;
const DAY = "2026-11-04"; // local date in Los Angeles at T0

async function registered(options: { activity?: boolean; body?: Record<string, unknown> } = {}): Promise<TestRelay> {
  const relay = makeRelay();
  relay.github.set("me", { [DAY]: 5 });
  relay.github.set("alice", { [DAY]: 9 });
  relay.github.set("bob", { [DAY]: 3 });
  expect((await relay.request("PUT", path, { body: registration(options.body) })).status).toBe(204);
  if (options.activity !== false) {
    expect(
      (await relay.request("PUT", `${path}/activity`, { body: { activityId: "activity-1", pushToken: ACTIVITY_TOKEN } })).status,
    ).toBe(204);
  }
  return relay;
}

async function tick(relay: TestRelay, seconds = 300): Promise<void> {
  relay.clock.advance(seconds);
  await relay.cron();
}

describe("cron: updates", () => {
  it("pushes the current state to a newly reported activity", async () => {
    const relay = await registered();
    await relay.cron();

    expect(relay.apns.requests).toHaveLength(1);
    const [request] = relay.apns.requests;
    expect(request?.environment).toBe("sandbox");
    expect(request?.deviceToken).toBe(ACTIVITY_TOKEN);
    expect(request?.headers["apns-push-type"]).toBe("liveactivity");
    expect(request?.headers["apns-topic"]).toBe("com.addisonk.CommitStandings.iOS.push-type.liveactivity");
    expect(request?.headers.authorization).toBe("bearer test-provider-token");
    expect(request?.headers["apns-priority"]).toBe("5");
    expect(JSON.parse(request!.body)).toEqual({
      aps: {
        timestamp: T0,
        event: "update",
        "content-state": {
          window: "daily",
          rank: 2,
          competitorCount: 3,
          contributions: 5,
          above: { login: "alice", contributions: 9 },
          below: { login: "bob", contributions: 3 },
          movementToday: 0,
          updatedAt: T0,
        },
        "stale-date": T0 + 20 * 60,
      },
    });
  });

  it("omits nil values from the content state", async () => {
    const relay = await registered({ body: { competitors: ["me"] } });
    await relay.cron();
    const state = relay.apns.payloads()[0]?.aps["content-state"];
    expect(state).toEqual({ window: "daily", competitorCount: 1, contributions: 5, movementToday: 0, updatedAt: T0 });
  });

  it("does not push when nothing changed", async () => {
    const relay = await registered();
    await relay.cron();
    relay.apns.clear();
    await tick(relay);
    expect(relay.apns.requests).toHaveLength(0);
  });

  it("sends a heartbeat ten minutes before the stale date, with a later stale date", async () => {
    const relay = await registered();
    await relay.cron();
    relay.apns.clear();
    await tick(relay); // T0+300: nothing
    expect(relay.apns.requests).toHaveLength(0);
    await tick(relay); // T0+600: stale date T0+1200 is 10 minutes away
    const [heartbeat] = relay.apns.payloads();
    expect(heartbeat?.priority).toBe("5");
    expect(heartbeat?.aps["stale-date"]).toBe(T0 + 600 + 20 * 60);
    expect((heartbeat?.aps["content-state"] as { updatedAt: number }).updatedAt).toBe(T0 + 600);
  });

  it("does not repeat a heartbeat when the data can't advance", async () => {
    const relay = await registered();
    await relay.cron();
    relay.github.failing = new Set(["me", "alice", "bob"]);
    relay.apns.clear();
    for (let i = 0; i < 6; i += 1) await tick(relay);
    // Cached counts stay, so the state never changes and its stale date can't move: let it go stale.
    expect(relay.apns.requests).toHaveLength(0);
  });

  it("uses priority 10 only when the rank changes", async () => {
    const relay = await registered();
    await relay.cron();
    relay.apns.clear();

    relay.github.set("me", { [DAY]: 6 }); // still #2
    await tick(relay);
    expect(relay.apns.payloads().map((push) => push.priority)).toEqual(["5"]);

    relay.github.set("me", { [DAY]: 12 }); // passes alice: #1
    await tick(relay);
    const pushes = relay.apns.payloads();
    expect(pushes.map((push) => push.priority)).toEqual(["5", "10"]);
    expect(pushes[1]?.aps["content-state"]).toMatchObject({ rank: 1, below: { login: "alice", contributions: 9 } });
    expect(pushes[1]?.aps["stale-date"]).toBe(relay.clock.seconds + 20 * 60);
  });

  it("keeps cached counts when GitHub fails, and treats never-loaded people as missing", async () => {
    const relay = await registered();
    relay.github.calendars.delete("bob");
    await relay.cron();
    expect(relay.apns.payloads()[0]?.aps["content-state"]).toMatchObject({ rank: 2, above: { login: "alice", contributions: 9 } });
    expect(relay.apns.payloads()[0]?.aps["content-state"]).not.toHaveProperty("below");

    relay.github.failing = new Set(["alice"]);
    relay.apns.clear();
    await tick(relay);
    expect(relay.apns.requests).toHaveLength(0); // alice's cached 9 still ranks above
  });
});

describe("cron: Today's movement and local midnight", () => {
  it("measures movement from the day's first run", async () => {
    const relay = await registered();
    await relay.cron(); // baseline: alice 1, me 2, bob 3
    relay.github.set("me", { [DAY]: 10 });
    relay.apns.clear();
    await tick(relay);
    expect(relay.apns.payloads()[0]?.aps["content-state"]).toMatchObject({ rank: 1, movementToday: 1 });
  });

  it("resets Today in place at local midnight without a new activity", async () => {
    const relay = await registered();
    await relay.cron();
    relay.github.set("me", { [DAY]: 10 });
    await tick(relay);

    // 23:30 in Los Angeles: a recent activity, still moved up one place today.
    const evening = "f6".repeat(40);
    relay.clock.seconds = Date.UTC(2026, 10, 5, 7, 30, 0) / 1000;
    await relay.request("PUT", `${path}/activity`, { body: { activityId: "activity-2", pushToken: evening } });
    await relay.cron();
    expect(relay.apns.payloads().at(-1)?.aps["content-state"]).toMatchObject({ rank: 1, contributions: 10, movementToday: 1 });
    relay.apns.clear();

    // 00:00 on 2026-11-05 in Los Angeles (PST) is 08:00 UTC.
    relay.clock.seconds = Date.UTC(2026, 10, 5, 8, 0, 0) / 1000;
    await relay.cron();
    const pushes = relay.apns.payloads();
    expect(pushes.map((push) => [push.token, push.aps.event])).toEqual([[evening, "update"]]);
    expect(pushes[0]?.aps["content-state"]).toMatchObject({ rank: 1, contributions: 0, movementToday: 0 });
  });

  it("uses each installation's own calendar day", async () => {
    const relay = makeRelay();
    const days = { "2026-11-04": 4, "2026-11-05": 7 };
    relay.github.set("me", days);
    relay.github.set("alice", { "2026-11-04": 1, "2026-11-05": 1 });
    const london = "8F14E45F-CEA7-4B5B-9D0A-7C5E2B1A0002";
    const londonToken = "c3".repeat(40);
    await relay.request("PUT", path, { body: registration({ competitors: ["me", "alice"] }) });
    await relay.request("PUT", `${path}/activity`, { body: { activityId: "la", pushToken: ACTIVITY_TOKEN } });
    await relay.request("PUT", `/v1/installations/${london}`, {
      body: registration({ competitors: ["me", "alice"], timeZone: "Europe/London" }),
    });
    await relay.request("PUT", `/v1/installations/${london}/activity`, { body: { activityId: "uk", pushToken: londonToken } });

    // 01:00 UTC on 2026-11-05: already the 5th in London, still the 4th (17:00) in Los Angeles.
    relay.clock.seconds = Date.UTC(2026, 10, 5, 1, 0, 0) / 1000;
    await relay.cron();
    const byToken = Object.fromEntries(relay.apns.payloads().map((push) => [push.token, push.aps["content-state"]]));
    expect(byToken[ACTIVITY_TOKEN]).toMatchObject({ contributions: 4 });
    expect(byToken[londonToken]).toMatchObject({ contributions: 7 });
  });

  it("reports no movement outside Today", async () => {
    const relay = await registered({ body: { window: "weekly" } });
    await relay.cron();
    relay.github.set("me", { [DAY]: 10 });
    relay.apns.clear();
    await tick(relay);
    expect(relay.apns.payloads()[0]?.aps["content-state"]).toMatchObject({ window: "weekly", rank: 1, movementToday: 0 });
  });
});

describe("cron: always-on rotation", () => {
  it("ends a 7.5-hour-old activity immediately, then push-to-starts a fresh one", async () => {
    const relay = await registered();
    await relay.cron();
    relay.clock.seconds = T0 + ROTATION - 300;
    await relay.cron();
    expect(relay.apns.payloads().filter((push) => push.aps.event !== "update")).toHaveLength(0);
    relay.apns.clear();

    relay.clock.seconds = T0 + ROTATION;
    await relay.cron();
    const [end, start] = relay.apns.payloads();
    expect(relay.apns.requests).toHaveLength(2);
    expect(end?.token).toBe(ACTIVITY_TOKEN);
    expect(end?.aps.event).toBe("end");
    expect(end?.priority).toBe("5");
    expect(start?.priority).toBe("10");
    expect(end?.aps["dismissal-date"]).toBeLessThan(relay.clock.seconds);
    expect(end?.aps["content-state"]).toMatchObject({ rank: 2 });
    expect(start?.token).toBe(PTS_TOKEN);
    expect(start?.aps).toMatchObject({
      event: "start",
      "attributes-type": "LiveRankAttributes",
      attributes: { selfLogin: "me" },
      "input-push-token": 1,
      "content-state": { rank: 2, contributions: 5 },
      "stale-date": relay.clock.seconds + 20 * 60,
    });
    expect(start?.aps.alert).toMatchObject({ title: "Live rank" });

    // Until the device reports the new activity, nothing else is sent.
    relay.apns.clear();
    await tick(relay);
    expect(relay.apns.requests).toHaveLength(0);

    const next = "d4".repeat(40);
    await relay.request("PUT", `${path}/activity`, { body: { activityId: "activity-2", pushToken: next } });
    await tick(relay);
    expect(relay.apns.payloads().map((push) => [push.token, push.aps.event])).toEqual([[next, "update"]]);
  });

  it("keeps an activity's age when only its push token changes", async () => {
    const relay = await registered();
    await relay.cron();
    const rotated = "e5".repeat(40);
    relay.clock.seconds = T0 + 3600;
    await relay.request("PUT", `${path}/activity`, { body: { activityId: "activity-1", pushToken: rotated } });
    relay.apns.clear();
    relay.clock.seconds = T0 + ROTATION;
    await relay.cron();
    expect(relay.apns.payloads().map((push) => [push.token, push.aps.event])).toEqual([
      [rotated, "end"],
      [PTS_TOKEN, "start"],
    ]);
  });

  it("rotates a relay-started activity 7.5 hours after its start push, not after the app reports it", async () => {
    const relay = await registered({ activity: false });
    const startedAt = T0 + ROTATION;
    relay.clock.seconds = startedAt;
    await relay.cron();
    expect(relay.apns.payloads().map((push) => push.aps.event)).toEqual(["start"]);

    // The app reports the relay-started activity an hour later (it was closed until then).
    const next = "d4".repeat(40);
    relay.clock.seconds = startedAt + 3600;
    await relay.request("PUT", `${path}/activity`, { body: { activityId: "relay-started", pushToken: next } });
    await relay.cron();
    relay.apns.clear();

    relay.clock.seconds = startedAt + ROTATION;
    await relay.cron();
    expect(relay.apns.payloads().map((push) => [push.token, push.aps.event])).toEqual([
      [next, "end"],
      [PTS_TOKEN, "start"],
    ]);
  });

  it("rotates an app-started activity by the start time the app reports", async () => {
    const relay = await registered({ activity: false });
    const startedAt = T0 - 3600; // started an hour before the app could report it
    const body = { activityId: "app-started", pushToken: ACTIVITY_TOKEN, startedAt };
    expect((await relay.request("PUT", `${path}/activity`, { body })).status).toBe(204);
    await relay.cron();
    relay.clock.seconds = startedAt + ROTATION - 60;
    await relay.cron();
    relay.apns.clear();

    relay.clock.seconds = startedAt + ROTATION;
    await relay.cron();
    expect(relay.apns.payloads().map((push) => [push.token, push.aps.event])).toEqual([
      [ACTIVITY_TOKEN, "end"],
      [PTS_TOKEN, "start"],
    ]);
  });

  it("treats a reported start time in the future as now", async () => {
    const relay = await registered({ activity: false });
    const body = { activityId: "app-started", pushToken: ACTIVITY_TOKEN, startedAt: T0 + 86_400 };
    expect((await relay.request("PUT", `${path}/activity`, { body })).status).toBe(204);
    relay.clock.seconds = T0 + ROTATION;
    await relay.cron();
    expect(relay.apns.payloads().map((push) => push.aps.event)).toEqual(["end", "start"]);
  });

  it("restarts a missing activity at most every 7.5 hours", async () => {
    const relay = await registered({ activity: false });
    await relay.cron();
    await tick(relay);
    expect(relay.apns.requests).toHaveLength(0);

    relay.clock.seconds = T0 + ROTATION;
    await relay.cron();
    expect(relay.apns.payloads().map((push) => [push.token, push.aps.event])).toEqual([[PTS_TOKEN, "start"]]);

    relay.apns.clear();
    for (let i = 0; i < 4; i += 1) await tick(relay);
    expect(relay.apns.requests).toHaveLength(0);

    relay.clock.seconds = T0 + 2 * ROTATION;
    await relay.cron();
    expect(relay.apns.payloads().map((push) => push.aps.event)).toEqual(["start"]);
  });

  it("does not start anything without a push-to-start token", async () => {
    const relay = await registered({ activity: false, body: { pushToStartToken: null } });
    relay.clock.seconds = T0 + ROTATION;
    await relay.cron();
    expect(relay.apns.requests).toHaveLength(0);
  });
});

describe("cron: rejected tokens", () => {
  it("drops an activity token APNs answers 410 for", async () => {
    const relay = await registered();
    relay.apns.respond((request) => request.deviceToken === ACTIVITY_TOKEN, { status: 410, reason: "Unregistered" });
    await relay.cron();
    relay.github.set("me", { [DAY]: 20 });
    relay.apns.clear();
    await tick(relay);
    expect(relay.apns.requests.filter((request) => request.deviceToken === ACTIVITY_TOKEN)).toHaveLength(0);
  });

  it("drops a push-to-start token APNs calls bad", async () => {
    const relay = await registered({ activity: false });
    relay.apns.respond((request) => request.deviceToken === PTS_TOKEN, { status: 400, reason: "BadDeviceToken" });
    relay.clock.seconds = T0 + ROTATION;
    await relay.cron();
    expect(relay.apns.requests).toHaveLength(1);
    relay.apns.clear();
    relay.clock.seconds = T0 + 3 * ROTATION;
    await relay.cron();
    expect(relay.apns.requests).toHaveLength(0);
  });

  it("retries a push that failed for another reason", async () => {
    const relay = await registered();
    relay.apns.respond(() => relay.clock.seconds === T0, { status: 503, reason: "ServiceUnavailable" });
    await relay.cron();
    relay.apns.clear();
    await tick(relay);
    expect(relay.apns.payloads().map((push) => push.token)).toEqual([ACTIVITY_TOKEN]);
  });

  it("never logs push tokens", async () => {
    const relay = await registered();
    relay.apns.respond(() => true, { status: 410, reason: "ExpiredToken" });
    await relay.cron();
    relay.clock.seconds = T0 + ROTATION;
    await relay.cron();
    const logs = relay.logs.join("\n");
    expect(logs).toContain("token_removed");
    for (const token of [ACTIVITY_TOKEN, PTS_TOKEN]) expect(logs).not.toContain(token);
  });
});

describe("cron: contribution counts", () => {
  it("fetches each login once per 5 minutes across installations", async () => {
    const relay = await registered();
    const other = "8F14E45F-CEA7-4B5B-9D0A-7C5E2B1A0003";
    await relay.request("PUT", `/v1/installations/${other}`, { body: registration({ login: "alice", competitors: ["alice", "me"] }) });
    await relay.cron();
    expect([...relay.github.fetched].sort()).toEqual(["alice", "bob", "me"]);

    relay.github.fetched.length = 0;
    relay.clock.advance(299);
    await relay.cron();
    expect(relay.github.fetched).toHaveLength(0);

    relay.clock.advance(1);
    await relay.cron();
    expect([...relay.github.fetched].sort()).toEqual(["alice", "bob", "me"]);
  });

  it("spreads fetches over runs when the board exceeds the per-run budget", async () => {
    const relay = makeRelay({}, { GITHUB_FETCH_BUDGET: "2" });
    relay.github.set("me", { [DAY]: 5 });
    relay.github.set("alice", { [DAY]: 9 });
    relay.github.set("bob", { [DAY]: 3 });
    await relay.request("PUT", path, { body: registration() });
    await relay.cron();
    expect(relay.github.fetched).toHaveLength(2);
    await tick(relay, 60);
    expect(relay.github.fetched).toHaveLength(3);
    expect(new Set(relay.github.fetched).size).toBe(3);
  });
});

describe("cron: fetch priority and the subrequest budget", () => {
  // p1 80, p2 70, p3 60, p4 50, me 45, p5 40, p6 30, p7 20, p8 10: you sit between p4 and p5.
  const board = ["me", "p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8"];
  const counts: Record<string, number> = { me: 45, p1: 80, p2: 70, p3: 60, p4: 50, p5: 40, p6: 30, p7: 20, p8: 10 };

  function relayWith(vars: Record<string, string>): TestRelay {
    const relay = makeRelay({}, vars);
    for (const login of board) relay.github.set(login, { [DAY]: counts[login]! });
    return relay;
  }

  /** A first run at T0 that caches everyone but `failing`. */
  async function warmCache(failing: string[] = []): Promise<void> {
    const warm = relayWith({});
    warm.github.failing = new Set(failing);
    await warm.request("PUT", path, { body: registration({ competitors: board }) });
    await warm.request("PUT", `${path}/activity`, { body: { activityId: "activity-1", pushToken: ACTIVITY_TOKEN } });
    await warm.cron();
    expect(warm.github.fetched).toHaveLength(board.length);
  }

  it("refreshes your own count and your neighbors' before anyone else's", async () => {
    await warmCache();
    const short = relayWith({ GITHUB_FETCH_BUDGET: "3" });
    short.clock.seconds = T0 + 300;
    await short.cron();
    expect([...short.github.fetched].sort()).toEqual(["me", "p4", "p5"]);
  });

  it("then refreshes the stalest cached counts, never-fetched ones first", async () => {
    await warmCache(["p8"]); // p8 has never been fetched
    const relay = relayWith({ GITHUB_FETCH_BUDGET: "5" });
    relay.clock.seconds = T0 + 300; // everyone is due; p8 first, then board order breaks the tie
    await relay.cron();
    expect([...relay.github.fetched].sort()).toEqual(["me", "p1", "p4", "p5", "p8"]);

    relay.github.fetched.length = 0;
    relay.clock.seconds = T0 + 600; // p2, p3, p6, p7 (fetched at T0) are now the stalest
    await relay.cron();
    expect([...relay.github.fetched].sort()).toEqual(["me", "p2", "p3", "p4", "p5"]);
  });

  it("keeps a subrequest for every push it may send, and still pushes", async () => {
    await warmCache();
    // 5 subrequests in all; the activity may need 1 push, so at most 4 fetches.
    const relay = relayWith({ SUBREQUEST_LIMIT: "5" });
    relay.github.set("me", { [DAY]: 55 }); // passes p4
    relay.clock.seconds = T0 + 300;
    await relay.cron();
    expect(relay.github.fetched).toHaveLength(4);
    expect(relay.apns.payloads().map((push) => push.aps["content-state"])).toMatchObject([{ rank: 4 }]);
  });

  it("reserves two pushes for a rotation", async () => {
    await warmCache();
    const relay = relayWith({ SUBREQUEST_LIMIT: "5" });
    relay.clock.seconds = T0 + ROTATION;
    await relay.cron();
    expect(relay.github.fetched).toHaveLength(3);
    expect(relay.apns.payloads().map((push) => push.aps.event)).toEqual(["end", "start"]);
  });

  it("defers pushes beyond the limit to the next run instead of failing", async () => {
    const installs = ["8F14E45F-CEA7-4B5B-9D0A-7C5E2B1A0011", "8F14E45F-CEA7-4B5B-9D0A-7C5E2B1A0012", "8F14E45F-CEA7-4B5B-9D0A-7C5E2B1A0013"];
    const relay = relayWith({ SUBREQUEST_LIMIT: "2" });
    for (const [index, id] of installs.entries()) {
      await relay.request("PUT", `/v1/installations/${id}`, { body: registration({ competitors: ["me", "p1"] }) });
      const token = String(index + 1).repeat(64);
      await relay.request("PUT", `/v1/installations/${id}/activity`, { body: { activityId: `a${index}`, pushToken: token } });
    }
    await relay.cron();
    expect(relay.github.fetched).toHaveLength(0);
    expect(relay.apns.requests).toHaveLength(2);
    expect(relay.logs.join("\n")).toContain("push_deferred");

    relay.apns.clear();
    await tick(relay);
    expect(relay.apns.payloads().map((push) => push.token)).toEqual(["3".repeat(64)]);
  });
});
