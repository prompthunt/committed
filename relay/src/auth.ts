import type { Env } from "./env";

export async function cachedProviderToken(_env: Env, _now: number): Promise<string> {
  throw new Error("APNs provider token not implemented");
}

export async function invalidateCachedProviderToken(_env: Env): Promise<void> {}
