import type { ApnsRequest, ApnsResult, ApnsSender } from "../../src/apns";

/** Records every push and answers from a per-token script (default 200). */
export class FakeApns implements ApnsSender {
  readonly sent: ApnsRequest[] = [];
  private readonly responses = new Map<string, ApnsResult>();

  respond(token: string, result: ApnsResult): void {
    this.responses.set(token, result);
  }

  async send(request: ApnsRequest): Promise<ApnsResult> {
    this.sent.push(request);
    return this.responses.get(request.token) ?? { status: 200 };
  }

  events(): string[] {
    return this.sent.map((push) => `${push.payload.aps.event}:${push.token}`);
  }

  clear(): void {
    this.sent.length = 0;
  }
}

/** A fake github.com that serves a contributions calendar per login from a day map. */
export class FakeGitHub {
  readonly requests: string[] = [];
  private readonly calendars = new Map<string, Record<string, number>>();
  private readonly failing = new Set<string>();

  set(login: string, days: Record<string, number>): void {
    this.calendars.set(login, days);
    this.failing.delete(login);
  }

  fail(login: string): void {
    this.failing.add(login);
  }

  fetch = async (login: string): Promise<string> => {
    this.requests.push(login);
    if (this.failing.has(login)) throw new Error(`HTTP 502 for ${login}`);
    const days = this.calendars.get(login);
    if (!days) throw new Error(`HTTP 404 for ${login}`);
    const cells = Object.entries(days)
      .map(([date, count], i) => `<td data-date="${date}" id="c-${i}"></td>`)
      .join("\n");
    const tips = Object.entries(days)
      .map(([date, count], i) =>
        `<tool-tip for="c-${i}">${count === 0 ? "No contributions" : `${count} contributions`} on ${date}</tool-tip>`,
      )
      .join("\n");
    return `<table>${cells}</table>${tips}`;
  };

  /** api.github.com/users/<login> `name`s, logged apart from the contribution pages. */
  readonly nameRequests: string[] = [];
  private readonly names = new Map<string, string | null>();
  private readonly failingNames = new Set<string>();

  setName(login: string, name: string | null): void {
    this.names.set(login, name);
    this.failingNames.delete(login);
  }

  failName(login: string): void {
    this.failingNames.add(login);
  }

  name = async (login: string): Promise<string | null> => {
    this.nameRequests.push(login);
    if (this.failingNames.has(login)) throw new Error(`HTTP 403 for ${login}`);
    if (!this.names.has(login)) throw new Error(`HTTP 404 for ${login}`);
    return this.names.get(login) ?? null;
  };
}

export class Clock {
  constructor(public seconds: number) {}
  now = (): number => this.seconds;
  advance(seconds: number): void {
    this.seconds += seconds;
  }
}

export const HOUR = 3600;
export const MINUTE = 60;
