import { handleRequest } from "./api";
import { FetchApnsTransport, type ApnsTransport, type PushSender } from "./apns";
import { cachedProviderToken, invalidateCachedProviderToken } from "./auth";
import { runCron } from "./cron";
import type { Env } from "./env";
import type { Log } from "./log";

/** Everything the relay touches outside D1, injectable for tests. */
export interface RelayDeps extends PushSender {
  apns: ApnsTransport;
  /** GET the public contributions page for a login. */
  fetchContributions(login: string): Promise<Response>;
  /** Unix seconds. */
  now(): number;
  log: Log;
}

export function defaultDeps(): RelayDeps {
  return {
    apns: new FetchApnsTransport(),
    fetchContributions: (login) =>
      fetch(`https://github.com/users/${encodeURIComponent(login)}/contributions`, {
        headers: { "user-agent": "CommittedRelay/1.0 (+https://github.com/prompthunt/committed)", accept: "text/html" },
        signal: AbortSignal.timeout(15_000),
      }),
    now: () => Date.now() / 1000,
    log: (line) => console.log(line),
    providerToken: (env) => cachedProviderToken(env, Date.now() / 1000),
    invalidateProviderToken: (env) => invalidateCachedProviderToken(env),
  };
}

export function createRelay(deps: RelayDeps): ExportedHandler<Env> {
  return {
    fetch: (request, env) => handleRequest(request as unknown as Request, env, deps),
    scheduled: async (_controller, env) => {
      await runCron(env, deps);
    },
  };
}
