import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { ACTIVITY_TOKEN, INSTALL, PTS_TOKEN, SECRET, makeRelay, registration } from "./helpers";

const path = `/v1/installations/${INSTALL}`;

describe("device API: registration and auth", () => {
  it("registers an installation and accepts its activity", async () => {
    const relay = makeRelay();
    expect((await relay.request("PUT", path, { body: registration() })).status).toBe(204);
    const activity = await relay.request("PUT", `${path}/activity`, {
      body: { activityId: "activity-1", pushToken: ACTIVITY_TOKEN },
    });
    expect(activity.status).toBe(204);
  });

  it("requires the bearer install secret", async () => {
    const relay = makeRelay();
    expect((await relay.request("PUT", path, { body: registration(), secret: null })).status).toBe(401);
    await relay.request("PUT", path, { body: registration() });
    expect((await relay.request("PUT", path, { body: registration(), secret: `${SECRET}-other` })).status).toBe(401);
    expect(
      (await relay.request("PUT", `${path}/activity`, { body: { activityId: "a", pushToken: ACTIVITY_TOKEN }, secret: null }))
        .status,
    ).toBe(401);
    expect((await relay.request("DELETE", path, { secret: "wrong-secret-0123456789abcdef0123" })).status).toBe(401);
  });

  it("rejects a short secret", async () => {
    const relay = makeRelay();
    expect((await relay.request("PUT", path, { body: registration(), secret: "short" })).status).toBe(401);
  });

  it("reports an activity for an unknown installation as not found", async () => {
    const relay = makeRelay();
    const response = await relay.request("PUT", `${path}/activity`, { body: { activityId: "a", pushToken: ACTIVITY_TOKEN } });
    expect(response.status).toBe(404);
  });

  it("stores only a hash of the secret", async () => {
    const relay = makeRelay();
    await relay.request("PUT", path, { body: registration() });
    const dump = JSON.stringify((await env.DB.prepare("SELECT * FROM installations").all()).results);
    expect(dump).not.toContain(SECRET);
    expect(dump).toContain(INSTALL);
  });
});

describe("device API: validation", () => {
  const invalid: [string, Record<string, unknown>][] = [
    ["a GitHub token field", { githubToken: "gho_0123456789abcdefghijklmnopqrstuvwxyz" }],
    ["any unknown field", { token: "ghp_0123456789abcdefghijklmnopqrstuvwxyz" }],
    ["a bad window", { window: "yearly" }],
    ["a bad time zone", { timeZone: "Mars/Olympus_Mons" }],
    ["a bad environment", { environment: "staging" }],
    ["a bad login", { login: "not a login!" }],
    ["competitors without self", { competitors: ["alice", "bob"] }],
    ["a bad competitor", { competitors: ["me", "-bad-"] }],
    ["a non-hex push-to-start token", { pushToStartToken: "zz-not-hex" }],
  ];
  for (const [label, override] of invalid) {
    it(`rejects ${label} and stores nothing`, async () => {
      const relay = makeRelay();
      expect((await relay.request("PUT", path, { body: registration(override) })).status).toBe(400);
      const activity = await relay.request("PUT", `${path}/activity`, { body: { activityId: "a", pushToken: ACTIVITY_TOKEN } });
      expect(activity.status).toBe(404);
    });
  }

  it("accepts up to 1,000 competitors and rejects more", async () => {
    const relay = makeRelay();
    const people = (count: number) => ["me", ...Array.from({ length: count - 1 }, (_, i) => `user${i}`)];
    expect((await relay.request("PUT", path, { body: registration({ competitors: people(1000) }) })).status).toBe(204);
    expect((await relay.request("PUT", path, { body: registration({ competitors: people(1001) }) })).status).toBe(400);
  });

  it("rejects a malformed install ID and unknown routes", async () => {
    const relay = makeRelay();
    expect((await relay.request("PUT", "/v1/installations/not%20an%20id", { body: registration() })).status).toBe(404);
    expect((await relay.request("GET", path)).status).toBe(405);
    expect((await relay.request("GET", "/")).status).toBe(404);
  });

  it("rejects an activity without a hex push token", async () => {
    const relay = makeRelay();
    await relay.request("PUT", path, { body: registration() });
    const response = await relay.request("PUT", `${path}/activity`, { body: { activityId: "a", pushToken: "nope" } });
    expect(response.status).toBe(400);
  });
});

describe("device API: rate limiting", () => {
  it("limits writes per installation and resets after the window", async () => {
    const relay = makeRelay();
    for (let i = 0; i < 30; i += 1) {
      expect((await relay.request("PUT", path, { body: registration() })).status).toBe(204);
    }
    const limited = await relay.request("PUT", path, { body: registration() });
    expect(limited.status).toBe(429);
    expect(Number(limited.headers.get("retry-after"))).toBeGreaterThan(0);
    relay.clock.advance(600);
    expect((await relay.request("PUT", path, { body: registration() })).status).toBe(204);
  });

  it("always allows unregistering", async () => {
    const relay = makeRelay();
    for (let i = 0; i < 31; i += 1) await relay.request("PUT", path, { body: registration() });
    expect((await relay.request("DELETE", path)).status).toBe(204);
  });
});

describe("device API: unregister", () => {
  it("ends the current activity immediately and forgets the installation", async () => {
    const relay = makeRelay();
    await relay.request("PUT", path, { body: registration() });
    await relay.request("PUT", `${path}/activity`, { body: { activityId: "activity-1", pushToken: ACTIVITY_TOKEN } });
    expect((await relay.request("DELETE", path)).status).toBe(204);

    const [end] = relay.apns.payloads();
    expect(end?.token).toBe(ACTIVITY_TOKEN);
    expect(end?.aps.event).toBe("end");
    expect(end?.aps["dismissal-date"]).toBeLessThan(relay.clock.seconds);
    expect((await relay.request("PUT", `${path}/activity`, { body: { activityId: "a", pushToken: ACTIVITY_TOKEN } })).status).toBe(
      404,
    );
  });

  it("sends nothing when there is no activity", async () => {
    const relay = makeRelay();
    await relay.request("PUT", path, { body: registration() });
    expect((await relay.request("DELETE", path)).status).toBe(204);
    expect(relay.apns.requests).toHaveLength(0);
  });

  it("treats unregistering an unknown installation as done", async () => {
    const relay = makeRelay();
    expect((await relay.request("DELETE", path)).status).toBe(204);
  });
});

describe("device API: privacy", () => {
  it("never logs push tokens or the secret", async () => {
    const relay = makeRelay();
    await relay.request("PUT", path, { body: registration() });
    await relay.request("PUT", `${path}/activity`, { body: { activityId: "activity-1", pushToken: ACTIVITY_TOKEN } });
    relay.apns.respond(() => true, { status: 410, reason: "Unregistered" });
    await relay.request("DELETE", path);
    const logs = relay.logs.join("\n");
    expect(relay.logs.length).toBeGreaterThan(0);
    for (const secret of [PTS_TOKEN, ACTIVITY_TOKEN, SECRET]) expect(logs).not.toContain(secret);
  });
});
