import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { createRelay } from "../src/relay";
import { Clock, FakeApns, FakeGitHub } from "./support/fakes";

const ID = "8f0c1d5e-4b7a-4c39-9a51-2f6d8e0b7c11";
const SECRET = "s".repeat(43);
const PTS = "a1".repeat(40);
const ACTIVITY_TOKEN = "b2".repeat(40);

const registration = {
  pushToStartToken: PTS,
  login: "Me",
  competitors: ["me", "Alice", "bob"],
  window: "daily",
  timeZone: "America/New_York",
  apnsEnvironment: "sandbox",
};

let apns: FakeApns;
let clock: Clock;
let relay: ReturnType<typeof createRelay>;

function call(method: string, path: string, body?: unknown, secret: string | null = SECRET): Promise<Response> {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (secret !== null) headers.authorization = `Bearer ${secret}`;
  return relay.fetch(
    new Request(`https://relay.test${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
  );
}

async function row(id = ID) {
  return env.DB.prepare("SELECT * FROM installations WHERE id = ?").bind(id).first<Record<string, unknown>>();
}

beforeEach(() => {
  apns = new FakeApns();
  clock = new Clock(1_793_800_000);
  relay = createRelay({ db: env.DB, apns, github: new FakeGitHub().fetch, githubName: new FakeGitHub().name, now: clock.now, bundleId: "com.example.app" });
});

describe("PUT /v1/installations/{id}", () => {
  it("registers an installation and stores only a hash of the secret", async () => {
    const res = await call("PUT", `/v1/installations/${ID}`, registration);
    expect(res.status).toBe(201);
    const stored = await row();
    expect(stored).not.toBeNull();
    expect(stored!.secret_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(stored)).not.toContain(SECRET);
    expect(stored!.login).toBe("me");
    expect(JSON.parse(stored!.competitors_json as string)).toEqual(["me", "alice", "bob"]);
    expect(stored!.push_to_start_token).toBe(PTS);
    expect(stored!.window).toBe("daily");
    expect(stored!.time_zone).toBe("America/New_York");
    expect(stored!.apns_environment).toBe("sandbox");
  });

  it("updates with the same secret and rejects a different one", async () => {
    await call("PUT", `/v1/installations/${ID}`, registration);
    const update = await call("PUT", `/v1/installations/${ID}`, { ...registration, window: "weekly" });
    expect(update.status).toBe(200);
    expect((await row())!.window).toBe("weekly");

    const hijack = await call("PUT", `/v1/installations/${ID}`, { ...registration, login: "mallory" }, "x".repeat(43));
    expect(hijack.status).toBe(401);
    expect((await row())!.login).toBe("me");
  });

  it("requires a bearer secret", async () => {
    expect((await call("PUT", `/v1/installations/${ID}`, registration, null)).status).toBe(401);
    expect((await call("PUT", `/v1/installations/${ID}`, registration, "short")).status).toBe(401);
    expect(await row()).toBeNull();
  });

  it("puts self first when the board list omits it, and drops duplicates", async () => {
    await call("PUT", `/v1/installations/${ID}`, { ...registration, competitors: ["alice", "ALICE", "bob"] });
    expect(JSON.parse((await row())!.competitors_json as string)).toEqual(["me", "alice", "bob"]);
  });

  // You're first on your own board, so you win a tie with any rival, as the iPhone's rows do
  // ("N to pass" relies on it). The rivals keep the order the device sent.
  it("moves self to the front when the board list has it later", async () => {
    await call("PUT", `/v1/installations/${ID}`, { ...registration, competitors: ["alice", "bob", "me"] });
    expect(JSON.parse((await row())!.competitors_json as string)).toEqual(["me", "alice", "bob"]);
  });

  it("accepts at most 1,000 competitors", async () => {
    const logins = (n: number) => Array.from({ length: n }, (_, i) => `user-${i}`);
    const ok = await call("PUT", `/v1/installations/${ID}`, { ...registration, competitors: ["me", ...logins(999)] });
    expect(ok.status).toBe(201);
    const tooMany = await call("PUT", `/v1/installations/${ID}`, { ...registration, competitors: ["me", ...logins(1000)] });
    expect(tooMany.status).toBe(400);
  });

  it("never accepts a GitHub token: unknown fields are rejected", async () => {
    const res = await call("PUT", `/v1/installations/${ID}`, { ...registration, githubToken: "gho_secret" });
    expect(res.status).toBe(400);
    expect(await row()).toBeNull();
  });

  it("rejects invalid fields", async () => {
    const bad = [
      { ...registration, login: "gho_abc123" },
      { ...registration, window: "yearly" },
      { ...registration, timeZone: "Mars/Olympus" },
      { ...registration, apnsEnvironment: "staging" },
      { ...registration, pushToStartToken: "not-hex" },
      { ...registration, competitors: "me" },
    ];
    for (const body of bad) {
      expect((await call("PUT", `/v1/installations/${ID}`, body)).status, JSON.stringify(body)).toBe(400);
    }
    expect((await call("PUT", "/v1/installations/bad id!", registration)).status).toBe(404);
  });

  it("rate-limits writes per installation", async () => {
    let status = 0;
    for (let i = 0; i < 40 && status !== 429; i++) {
      status = (await call("PUT", `/v1/installations/${ID}`, registration)).status;
    }
    expect(status).toBe(429);
    clock.advance(11 * 60);
    expect((await call("PUT", `/v1/installations/${ID}`, registration)).status).toBe(200);
  });
});

describe("PUT /v1/installations/{id}/activity", () => {
  it("records the activity id, push token, and start time", async () => {
    await call("PUT", `/v1/installations/${ID}`, registration);
    const res = await call("PUT", `/v1/installations/${ID}/activity`, { activityId: "act-1", pushToken: ACTIVITY_TOKEN });
    expect(res.status).toBe(200);
    const stored = await row();
    expect(stored!.activity_id).toBe("act-1");
    expect(stored!.activity_push_token).toBe(ACTIVITY_TOKEN);
    expect(stored!.activity_started_at).toBe(clock.seconds);
  });

  it("needs a registered installation and its secret", async () => {
    expect((await call("PUT", `/v1/installations/${ID}/activity`, { activityId: "a", pushToken: ACTIVITY_TOKEN })).status).toBe(404);
    await call("PUT", `/v1/installations/${ID}`, registration);
    const wrong = await call("PUT", `/v1/installations/${ID}/activity`, { activityId: "a", pushToken: ACTIVITY_TOKEN }, "y".repeat(43));
    expect(wrong.status).toBe(401);
  });
});

describe("DELETE /v1/installations/{id}", () => {
  it("ends the activity with immediate dismissal and forgets the installation", async () => {
    await call("PUT", `/v1/installations/${ID}`, registration);
    await call("PUT", `/v1/installations/${ID}/activity`, { activityId: "act-1", pushToken: ACTIVITY_TOKEN });
    const res = await call("DELETE", `/v1/installations/${ID}`);
    expect(res.status).toBe(204);
    expect(await row()).toBeNull();
    expect(apns.events()).toEqual([`end:${ACTIVITY_TOKEN}`]);
    expect(apns.sent[0]!.payload.aps["dismissal-date"]).toBe(clock.seconds);
  });

  it("rejects the wrong secret", async () => {
    await call("PUT", `/v1/installations/${ID}`, registration);
    expect((await call("DELETE", `/v1/installations/${ID}`, undefined, "z".repeat(43))).status).toBe(401);
    expect(await row()).not.toBeNull();
  });
});
