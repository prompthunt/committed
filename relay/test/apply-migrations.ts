import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { beforeEach } from "vitest";

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

// Start every test from empty tables.
beforeEach(async () => {
  await env.DB.batch([env.DB.prepare("DELETE FROM installations"), env.DB.prepare("DELETE FROM contribution_cache")]);
});
