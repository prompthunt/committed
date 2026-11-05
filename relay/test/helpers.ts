import { env } from "cloudflare:workers";
import { createRelay, type RelayDeps } from "../src/app";
import type { ApnsRequest, ApnsResponse, ApnsTransport } from "../src/apns";
import type { Env } from "../src/env";

/** Records every APNs request and answers from a script (default 200). */
export class FakeApns implements ApnsTransport {
  readonly requests: ApnsRequest[] = [];
  private readonly scripted: ((request: ApnsRequest) => ApnsResponse | undefined)[] = [];

  /** Answer matching requests with `response` (first matching rule wins). */
  respond(match: (request: ApnsRequest) => boolean, response: ApnsResponse): void {
    this.scripted.push((request) => (match(request) ? response : undefined));
  }

  async send(request: ApnsRequest): Promise<ApnsResponse> {
    this.requests.push(request);
    for (const rule of this.scripted) {
      const response = rule(request);
      if (response) return response;
    }
    return { status: 200 };
  }

  payloads(): { token: string; priority: string | undefined; aps: Record<string, unknown> }[] {
    return this.requests.map((request) => ({
      token: request.deviceToken,
      priority: request.headers["apns-priority"],
      aps: (JSON.parse(request.body) as { aps: Record<string, unknown> }).aps,
    }));
  }

  clear(): void {
    this.requests.length = 0;
  }
}

/** Serves contributions pages from an in-memory map of login -> { date: count }. */
export class FakeGitHub {
  readonly calendars = new Map<string, Record<string, number>>();
  readonly fetched: string[] = [];
  failing = new Set<string>();

  set(login: string, days: Record<string, number>): void {
    this.calendars.set(login, days);
  }

  fetch = async (login: string): Promise<Response> => {
    this.fetched.push(login);
    if (this.failing.has(login)) return new Response("unavailable", { status: 503 });
    const days = this.calendars.get(login);
    if (!days) return new Response("not found", { status: 404 });
    const cells = Object.entries(days)
      .map(([date, count], index) => `<td data-date="${date}" id="c-${index}"></td>`)
      .join("\n");
    const tips = Object.entries(days)
      .map(([date, count], index) =>
        `<tool-tip for="c-${index}">${count === 0 ? "No contributions" : `${count} contributions`} on ${date}</tool-tip>`,
      )
      .join("\n");
    return new Response(`<table>${cells}</table>\n${tips}`, { status: 200 });
  };
}

export class Clock {
  constructor(public seconds: number) {}
  now = (): number => this.seconds;
  advance(seconds: number): void {
    this.seconds += seconds;
  }
}

export interface TestRelay {
  apns: FakeApns;
  github: FakeGitHub;
  clock: Clock;
  logs: string[];
  providerTokens: number;
  request(method: string, path: string, options?: { secret?: string | null; body?: unknown }): Promise<Response>;
  cron(): Promise<void>;
}

/** 2026-11-04 17:00:00 UTC — 09:00 in Los Angeles, 18:00 in London. */
export const T0 = Date.UTC(2026, 10, 4, 17, 0, 0) / 1000;

/** `vars` overrides Worker vars (wrangler.jsonc), e.g. `{ GITHUB_FETCH_BUDGET: "3" }`. */
export function makeRelay(overrides: Partial<RelayDeps> = {}, vars: Partial<Record<keyof Env, string>> = {}): TestRelay {
  const relayEnv = { ...env, ...vars } as Env;
  const apns = new FakeApns();
  const github = new FakeGitHub();
  const clock = new Clock(T0);
  const logs: string[] = [];
  const relay: TestRelay = {
    apns,
    github,
    clock,
    logs,
    providerTokens: 0,
    async request(method, path, options = {}) {
      const headers = new Headers({ "content-type": "application/json" });
      const secret = options.secret === undefined ? SECRET : options.secret;
      if (secret !== null) headers.set("authorization", `Bearer ${secret}`);
      const init: RequestInit = { method, headers };
      if (options.body !== undefined) init.body = JSON.stringify(options.body);
      return worker.fetch!(new Request(`https://relay.test${path}`, init) as never, relayEnv, ctx());
    },
    async cron() {
      await worker.scheduled!({ cron: "*/5 * * * *", scheduledTime: clock.seconds * 1000 } as never, relayEnv, ctx());
    },
  };
  const worker = createRelay({
    apns,
    fetchContributions: github.fetch,
    now: clock.now,
    log: (line) => logs.push(line),
    providerToken: async () => {
      relay.providerTokens += 1;
      return "test-provider-token";
    },
    invalidateProviderToken: async () => {},
    ...overrides,
  });
  return relay;
}

function ctx(): ExecutionContext {
  return { waitUntil: () => {}, passThroughOnException: () => {}, props: {} } as unknown as ExecutionContext;
}

export const SECRET = "s3cret-0123456789abcdef0123456789abcdef";
export const INSTALL = "8F14E45F-CEA7-4B5B-9D0A-7C5E2B1A0001";
export const PTS_TOKEN = "a1".repeat(40);
export const ACTIVITY_TOKEN = "b2".repeat(40);

export function registration(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    login: "me",
    competitors: ["me", "alice", "bob"],
    window: "daily",
    timeZone: "America/Los_Angeles",
    environment: "sandbox",
    pushToStartToken: PTS_TOKEN,
    ...overrides,
  };
}
