import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { MAX_BOARD_COMPETITORS } from "../src/publicBoard";
import { createRelay } from "../src/relay";
import { Clock, FakeApns, FakeGitHub, MINUTE } from "./support/fakes";

// 2026-11-04 08:46 in New York.
const T0 = 1_793_800_000;

let github: FakeGitHub;
let clock: Clock;
let limited: boolean;
let limiterKeys: string[];
let relay: ReturnType<typeof createRelay>;

function get(query: string, init: RequestInit = {}): Promise<Response> {
  return relay.fetch(new Request(`https://relay.test/v1/board?${query}`, init));
}

beforeEach(() => {
  github = new FakeGitHub();
  clock = new Clock(T0);
  limited = false;
  limiterKeys = [];
  relay = createRelay({
    db: env.DB,
    apns: new FakeApns(),
    github: github.fetch,
    githubName: github.name,
    now: clock.now,
    bundleId: "com.example.app",
    boardLimiter: {
      limit: async ({ key }) => {
        limiterKeys.push(key);
        return { success: !limited };
      },
    },
  });
  github.set("me", { "2026-11-04": 5, "2026-11-01": 10 });
  github.set("alice", { "2026-11-04": 9 });
  github.set("bob", { "2026-11-04": 1, "2026-11-02": 30 });
});

describe("GET /v1/board", () => {
  it("ranks you among your rivals for today, readable from any origin", async () => {
    const res = await get("login=Me&competitors=alice,Bob&window=daily&tz=America/New_York");
    expect(res.status).toBe(200);
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
    expect(res.headers.get("cache-control")).toBe("public, max-age=60");
    expect(await res.json()).toEqual({
      window: "daily",
      rank: 2,
      competitorCount: 3,
      contributions: 5,
      above: { login: "alice", contributions: 9, movementToday: 0 },
      below: { login: "bob", contributions: 1, movementToday: 0 },
      movementToday: 0,
      updatedAt: T0,
    });
  });

  it("sums the 7-day window", async () => {
    const res = await get("login=me&competitors=alice,bob&window=weekly&tz=America/New_York");
    const body = (await res.json()) as { rank: number; contributions: number; above: { login: string } };
    expect(body.rank).toBe(2);
    expect(body.contributions).toBe(15);
    expect(body.above.login).toBe("bob");
  });

  it("shares the 5-minute contribution cache", async () => {
    await get("login=me&competitors=alice&tz=UTC");
    await get("login=me&competitors=alice&tz=UTC");
    expect(github.requests).toEqual(["me", "alice"]);
    clock.advance(5 * MINUTE);
    await get("login=me&competitors=alice&tz=UTC");
    expect(github.requests).toEqual(["me", "alice", "me", "alice"]);
  });

  it("has no rank without rivals", async () => {
    const body = (await (await get("login=me")).json()) as { rank: number | null; contributions: number };
    expect(body.rank).toBeNull();
    expect(body.contributions).toBe(5);
  });

  it("rejects bad input", async () => {
    expect((await get("competitors=alice")).status).toBe(400);
    expect((await get("login=me&competitors=al ice")).status).toBe(400);
    expect((await get("login=me&window=yearly")).status).toBe(400);
    expect((await get("login=me&tz=Mars/Base")).status).toBe(400);
    const many = Array.from({ length: MAX_BOARD_COMPETITORS }, (_, i) => `user${i}`).join(",");
    const res = await get(`login=me&competitors=${many}`);
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "too_many_competitors" });
    expect(github.requests).toEqual([]);
  });

  it("rate-limits per IP", async () => {
    limited = true;
    const res = await get("login=me&competitors=alice", { headers: { "cf-connecting-ip": "203.0.113.9" } });
    expect(res.status).toBe(429);
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
    expect(limiterKeys).toEqual(["203.0.113.9"]);
    expect(github.requests).toEqual([]);
  });

  it("is read-only", async () => {
    expect((await get("login=me", { method: "POST", body: "{}" })).status).toBe(405);
  });
});
