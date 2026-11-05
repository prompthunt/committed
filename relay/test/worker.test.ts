import { createScheduledController, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import worker from "../src/index";

describe("worker entrypoint", () => {
  it("serves the device API", async () => {
    const health = await exports.default.fetch("https://relay.test/");
    expect(health.status).toBe(200);
    const unauthorized = await exports.default.fetch("https://relay.test/v1/installations/inst-0001", { method: "PUT", body: "{}" });
    expect(unauthorized.status).toBe(401);
  });

  it("runs the cycle on the cron trigger", async () => {
    const ctx = createExecutionContext();
    worker.scheduled!(createScheduledController({ cron: "*/5 * * * *" }), env, ctx);
    await waitOnExecutionContext(ctx);
  });
});
