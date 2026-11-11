import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { createRelay } from "../src/relay";
import { Clock, FakeApns, FakeGitHub, HOUR, MINUTE } from "./support/fakes";

/**
 * The board route's `displayName`: the installation owner's public GitHub name, looked up by the
 * cron cycle at most once a day per installation and cached in D1. Board reads never call GitHub.
 */

const ID = "inst-name-0001";
const SECRET = "k".repeat(40);
const TOKEN = "t".repeat(43);
const T0 = Date.UTC(2026, 10, 5, 15, 0) / 1000;

let github: FakeGitHub;
let clock: Clock;
let relay: ReturnType<typeof createRelay>;

beforeEach(() => {
  github = new FakeGitHub();
  clock = new Clock(T0);
  relay = createRelay({
    db: env.DB,
    apns: new FakeApns(),
    github: github.fetch,
    githubName: github.name,
    now: clock.now,
    bundleId: "b",
    log: () => {},
  });
  github.set("me", { "2026-11-05": 5 });
  github.set("alice", { "2026-11-05": 9 });
});

async function register(login = "me") {
  const res = await relay.fetch(
    new Request(`https://relay.test/v1/installations/${ID}`, {
      method: "PUT",
      headers: { authorization: `Bearer ${SECRET}`, "content-type": "application/json" },
      body: JSON.stringify({
        pushToStartToken: null,
        login,
        competitors: [login, "alice"],
        window: "daily",
        timeZone: "America/New_York",
        apnsEnvironment: "sandbox",
      }),
    }),
  );
  expect(res.ok).toBe(true);
}

async function mint() {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(TOKEN));
  const hash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  await env.DB.prepare("INSERT INTO board_tokens (token_hash, installation_id, created_at) VALUES (?, ?, ?)")
    .bind(hash, ID, clock.seconds)
    .run();
}

async function displayName(): Promise<unknown> {
  const res = await relay.fetch(
    new Request(`https://relay.test/v1/installations/${ID}/board`, { headers: { authorization: `Bearer ${TOKEN}` } }),
  );
  expect(res.status).toBe(200);
  return ((await res.json()) as { displayName: unknown }).displayName;
}

describe("displayName", () => {
  beforeEach(async () => {
    await register();
    await mint();
  });

  it("is null until the cycle has looked the name up", async () => {
    github.setName("me", "Addison Kowalski");
    expect(await displayName()).toBeNull();
    expect(github.nameRequests).toEqual([]);
  });

  it("is the owner's public GitHub name once the cycle has run", async () => {
    github.setName("me", "Addison Kowalski");
    await relay.runCycle();
    expect(github.nameRequests).toEqual(["me"]);
    expect(await displayName()).toBe("Addison Kowalski");
  });

  it("is looked up at most once a day per installation", async () => {
    github.setName("me", "Addison Kowalski");
    await relay.runCycle();
    for (let i = 0; i < 5; i++) {
      clock.advance(5 * MINUTE);
      await relay.runCycle();
    }
    expect(github.nameRequests).toEqual(["me"]);

    github.setName("me", "Addison K.");
    clock.seconds = T0 + 24 * HOUR;
    await relay.runCycle();
    expect(github.nameRequests).toEqual(["me", "me"]);
    expect(await displayName()).toBe("Addison K.");
  });

  it("is null when the profile has no name, or only whitespace", async () => {
    github.setName("me", null);
    await relay.runCycle();
    expect(await displayName()).toBeNull();

    github.setName("me", "   ");
    clock.advance(24 * HOUR);
    await relay.runCycle();
    expect(await displayName()).toBeNull();
  });

  it("fails silently: pushes and the board carry on, and the lookup retries the next day", async () => {
    github.setName("me", "Addison Kowalski");
    await relay.runCycle();
    github.failName("me");
    clock.advance(24 * HOUR);
    await relay.runCycle();
    // A failed lookup keeps the last good name and waits a day before trying again.
    expect(await displayName()).toBe("Addison Kowalski");
    clock.advance(6 * HOUR);
    await relay.runCycle();
    expect(github.nameRequests).toEqual(["me", "me"]);

    github.setName("me", "Addison");
    clock.advance(18 * HOUR);
    await relay.runCycle();
    expect(github.nameRequests).toEqual(["me", "me", "me"]);
    expect(await displayName()).toBe("Addison");
  });

  it("a failing first lookup leaves it null and doesn't stop the cycle", async () => {
    github.failName("me");
    await relay.runCycle();
    expect(await displayName()).toBeNull();
    const state = await env.DB.prepare("SELECT baseline_date FROM installations WHERE id = ?").bind(ID).first<{ baseline_date: string }>();
    expect(state?.baseline_date).toBe("2026-11-05");
  });

  it("is forgotten when the installation's login changes, and looked up again for the new one", async () => {
    github.setName("me", "Addison Kowalski");
    await relay.runCycle();
    github.set("other", { "2026-11-05": 1 });
    github.setName("other", "Other Person");
    await register("other");
    expect(await displayName()).toBeNull();
    clock.advance(5 * MINUTE);
    await relay.runCycle();
    expect(github.nameRequests).toEqual(["me", "other"]);
    expect(await displayName()).toBe("Other Person");
  });
});
