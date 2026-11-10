import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import fixture from "../../fixtures/ranking-conformance.json";
import { localDate } from "../src/parser";
import { createRelay } from "../src/relay";
import type { Standing, Window } from "../src/ranking";
import { Clock, FakeApns, FakeGitHub, MINUTE } from "./support/fakes";

const ID = "inst-board-0001";
const OTHER_ID = "inst-board-0002";
const SECRET = "k".repeat(40);
const TOKEN = "t".repeat(43);
const OTHER_TOKEN = "o".repeat(43);

// 2026-11-05T15:00:00Z: 10:00 in New York, 00:00 on Nov 6 in Tokyo.
const T0 = Date.UTC(2026, 10, 5, 15, 0) / 1000;

let github: FakeGitHub;
let clock: Clock;
let relay: ReturnType<typeof createRelay>;

beforeEach(() => {
  github = new FakeGitHub();
  clock = new Clock(T0);
  relay = createRelay({ db: env.DB, apns: new FakeApns(), github: github.fetch, now: clock.now, bundleId: "b", log: () => {} });
});

async function deviceCall(method: string, id: string, body?: unknown): Promise<Response> {
  return relay.fetch(
    new Request(`https://relay.test/v1/installations/${id}`, {
      method,
      headers: { authorization: `Bearer ${SECRET}`, "content-type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
  );
}

async function register(
  id: string,
  overrides: Partial<{ login: string; competitors: string[]; window: Window; timeZone: string }> = {},
) {
  const res = await deviceCall("PUT", id, {
    pushToStartToken: null,
    login: "me",
    competitors: ["me", "alice", "bob"],
    window: "daily",
    timeZone: "America/New_York",
    apnsEnvironment: "sandbox",
    ...overrides,
  });
  expect(res.ok).toBe(true);
}

/** Mints a board read token by hand, as the README does with `wrangler d1 execute`. */
async function mint(token: string, installationId: string, revokedAt: number | null = null) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  const hash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  await env.DB.prepare("INSERT INTO board_tokens (token_hash, installation_id, created_at, revoked_at) VALUES (?, ?, ?, ?)")
    .bind(hash, installationId, clock.seconds, revokedAt)
    .run();
}

async function seedCache(login: string, days: Record<string, number>, fetchedAt: number) {
  await env.DB.prepare("INSERT OR REPLACE INTO contribution_cache VALUES (?, ?, ?, ?, NULL)")
    .bind(login, fetchedAt, fetchedAt, JSON.stringify(days))
    .run();
}

function board(id = ID, query = "", token: string | null = TOKEN, authorization?: string): Promise<Response> {
  const headers: Record<string, string> = {};
  if (authorization !== undefined) headers.authorization = authorization;
  else if (token !== null) headers.authorization = `Bearer ${token}`;
  return relay.fetch(new Request(`https://relay.test/v1/installations/${id}/board${query}`, { headers }));
}

interface FixtureCase {
  name: string;
  input: {
    self: string;
    competitors: string[];
    window: Window;
    standings: Record<string, Standing>;
    rankDeltas: Record<string, number>;
    now: number;
  };
  expected: { order: { login: string; rank: number }[]; liveRankState: Record<string, unknown> };
}

describe("GET /v1/installations/{id}/board", () => {
  // The relay's cache holds days, not windowed standings: a standing in the case's window becomes
  // that many contributions today, and one in another window becomes no cached data at all.
  for (const c of fixture.cases as unknown as FixtureCase[]) {
    it(`matches the ranking conformance fixture: ${c.name}`, async () => {
      const { input, expected } = c;
      clock.seconds = input.now;
      const timeZone = "America/New_York";
      const today = localDate(input.now, timeZone);
      await register(ID, { login: input.self, competitors: input.competitors, window: "daily", timeZone });
      await mint(TOKEN, ID);
      for (const [login, standing] of Object.entries(input.standings)) {
        if (standing.window === input.window) await seedCache(login, { [today]: standing.contributions }, input.now);
      }
      if (input.window === "daily") {
        const baseline: Record<string, number> = {};
        for (const entry of expected.order) {
          const delta = input.rankDeltas[entry.login];
          if (delta !== undefined) baseline[entry.login] = entry.rank + delta;
        }
        await env.DB.prepare("UPDATE installations SET baseline_date = ?, baseline_ranks_json = ? WHERE id = ?")
          .bind(today, JSON.stringify(baseline), ID)
          .run();
      }

      const res = await board(ID, `?window=${input.window}`);
      expect(res.status).toBe(200);
      expect(res.headers.get("cache-control")).toBe("private, max-age=60");
      const body = (await res.json()) as Record<string, unknown> & { rows: { login: string; rank: number }[] };
      expect(body.rows.map(({ login, rank }) => ({ login, rank }))).toEqual(expected.order);
      const { rows: _rows, gapToPass: _gap, login: _login, ...summary } = body;
      expect(summary).toEqual(expected.liveRankState);
    });
  }

  it("reads only the relay's cache: never GitHub, with updatedAt from when the data was fetched", async () => {
    github.set("me", { "2026-11-05": 5 });
    github.set("alice", { "2026-11-05": 9 });
    github.set("bob", { "2026-11-05": 1 });
    await register(ID);
    await mint(TOKEN, ID);
    await relay.runCycle();
    github.requests.length = 0;
    github.set("me", { "2026-11-05": 50 }); // GitHub moved on; the board shows the cycle's view
    clock.advance(12 * MINUTE);

    const res = await board();
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      window: "daily",
      login: "me",
      rank: 2,
      competitorCount: 3,
      contributions: 5,
      above: { login: "alice", contributions: 9, movementToday: 0 },
      below: { login: "bob", contributions: 1, movementToday: 0 },
      movementToday: 0,
      gapToPass: 4,
      updatedAt: T0,
      rows: [
        { rank: 1, login: "alice", contributions: 9, movementToday: 0, isSelf: false },
        { rank: 2, login: "me", contributions: 5, movementToday: 0, isSelf: true },
        { rank: 3, login: "bob", contributions: 1, movementToday: 0, isSelf: false },
      ],
    });
    expect(github.requests).toEqual([]);
  });

  it("reports each row's movement since the cycle's baseline, and changes nothing when read", async () => {
    github.set("me", { "2026-11-05": 5 });
    github.set("alice", { "2026-11-05": 9 });
    github.set("bob", { "2026-11-05": 1 });
    await register(ID);
    await mint(TOKEN, ID);
    await relay.runCycle(); // baseline: alice 1, me 2, bob 3
    clock.advance(6 * MINUTE);
    github.set("bob", { "2026-11-05": 7 });
    await relay.runCycle(); // bob passes me
    const before = await env.DB.prepare("SELECT * FROM installations WHERE id = ?").bind(ID).first();

    const body = (await (await board()).json()) as { rows: { login: string; movementToday: number }[]; movementToday: number };
    expect(body.rows.map(({ login, movementToday }) => [login, movementToday])).toEqual([
      ["alice", 0],
      ["bob", 1],
      ["me", -1],
    ]);
    expect(body.movementToday).toBe(-1);
    expect(await env.DB.prepare("SELECT * FROM installations WHERE id = ?").bind(ID).first()).toEqual(before);
  });

  it("starts Today at midnight in the installation's time zone", async () => {
    // T0 is 00:00 on Nov 6 in Tokyo and 10:00 on Nov 5 in New York.
    await register(ID, { timeZone: "Asia/Tokyo" });
    await register(OTHER_ID, { timeZone: "America/New_York" });
    await mint(TOKEN, ID);
    await mint(OTHER_TOKEN, OTHER_ID);
    await seedCache("me", { "2026-11-05": 9, "2026-11-06": 2 }, T0);

    const contributions = async (id: string, token: string) =>
      ((await (await board(id, "", token)).json()) as { contributions: number }).contributions;
    expect(await contributions(ID, TOKEN)).toBe(2);
    expect(await contributions(OTHER_ID, OTHER_TOKEN)).toBe(9);
    clock.seconds = T0 - 1;
    expect(await contributions(ID, TOKEN)).toBe(9);
  });

  it("sums weekly and monthly windows", async () => {
    await register(ID, { competitors: ["me"] });
    await mint(TOKEN, ID);
    await seedCache("me", { "2026-11-05": 1, "2026-10-30": 10, "2026-10-29": 100, "2026-10-06": 1000 }, T0);

    const read = async (window: string) => (await (await board(ID, `?window=${window}`)).json()) as Record<string, unknown>;
    expect(await read("weekly")).toMatchObject({ window: "weekly", contributions: 11, rank: null, competitorCount: 1 });
    expect(await read("monthly")).toMatchObject({ window: "monthly", contributions: 111 });
  });

  it("has no rank and nobody to pass with no visible rivals", async () => {
    await register(ID, { competitors: ["me"] });
    await mint(TOKEN, ID);
    await seedCache("me", { "2026-11-05": 7 }, T0);

    expect(await (await board()).json()).toMatchObject({ rank: null, contributions: 7, gapToPass: null, above: null, below: null });
  });

  it("has a null updatedAt when nothing on the board has data yet", async () => {
    await register(ID);
    await mint(TOKEN, ID);

    const body = (await (await board()).json()) as { updatedAt: number | null; rows: { contributions: number | null }[] };
    expect(body.updatedAt).toBeNull();
    expect(body.rows.map((row) => row.contributions)).toEqual([null, null, null]);
  });

  describe("errors", () => {
    async function expectError(res: Response, status: number, error: string) {
      expect(res.status).toBe(status);
      const body = (await res.json()) as Record<string, unknown>;
      expect(Object.keys(body).sort()).toEqual(["error", "message"]);
      expect(body.error).toBe(error);
      expect(typeof body.message).toBe("string");
    }

    beforeEach(async () => {
      await register(ID);
      await register(OTHER_ID);
      await mint(TOKEN, ID);
      await mint(OTHER_TOKEN, OTHER_ID);
    });

    it("401 without a token, with a malformed one, or with an unknown one", async () => {
      await expectError(await board(ID, "", null), 401, "unauthorized");
      await expectError(await board(ID, "", null, `Basic ${TOKEN}`), 401, "unauthorized");
      await expectError(await board(ID, "", "short"), 401, "unauthorized");
      await expectError(await board(ID, "", "u".repeat(43)), 401, "unauthorized");
    });

    it("401 for the installation secret: it isn't a board read token", async () => {
      await expectError(await board(ID, "", SECRET), 401, "unauthorized");
    });

    it("403 for a revoked token", async () => {
      await env.DB.prepare("UPDATE board_tokens SET revoked_at = ?").bind(T0).run();
      await expectError(await board(), 403, "revoked");
    });

    it("403 for another installation's token", async () => {
      await expectError(await board(ID, "", OTHER_TOKEN), 403, "forbidden");
    });

    it("404 once the installation is deleted, which deletes its tokens", async () => {
      expect((await deviceCall("DELETE", ID)).status).toBe(204);
      await expectError(await board(), 404, "not_found");
      const left = await env.DB.prepare("SELECT installation_id FROM board_tokens").all();
      expect(left.results).toEqual([{ installation_id: OTHER_ID }]);
    });

    it("400 for an unknown window", async () => {
      await expectError(await board(ID, "?window=yearly"), 400, "invalid_window");
      expect((await board(ID, "?window=weekly")).status).toBe(200);
    });

    it("leaves the device API alone: a board token can't write", async () => {
      const res = await relay.fetch(
        new Request(`https://relay.test/v1/installations/${ID}`, { method: "DELETE", headers: { authorization: `Bearer ${TOKEN}` } }),
      );
      expect(res.status).toBe(401);
      expect((await board(ID, "", TOKEN)).status).toBe(200);
    });
  });
});
