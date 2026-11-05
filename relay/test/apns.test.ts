import { describe, expect, it } from "vitest";
import { createHttpApnsSender, JWT_LIFETIME_SECONDS, updatePayload } from "../src/apns";
import type { LiveRankState } from "../src/liveRank";
import { Clock, MINUTE } from "./support/fakes";

const state: LiveRankState = {
  window: "daily",
  rank: 1,
  competitorCount: 2,
  contributions: 3,
  above: null,
  below: { login: "alice", contributions: 1, movementToday: 0 },
  movementToday: 0,
  updatedAt: 1_793_800_000,
};

async function p8(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  const b64 = btoa(String.fromCharCode(...pkcs8)).replace(/(.{64})/g, "$1\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

function decode(part: string): unknown {
  const b64 = part.replaceAll("-", "+").replaceAll("_", "/");
  return JSON.parse(atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4)));
}

function bytes(part: string): Uint8Array {
  const b64 = part.replaceAll("-", "+").replaceAll("_", "/");
  return Uint8Array.from(atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4)), (c) => c.charCodeAt(0));
}

describe("HTTP APNs sender", () => {
  it("posts a liveactivity push to the right host and topic with an ES256 provider token", async () => {
    const { pem, publicKey } = await p8();
    const clock = new Clock(1_793_800_000);
    const calls: { url: string; init: RequestInit }[] = [];
    const sender = createHttpApnsSender({
      keyId: "KEY1234567",
      teamId: "TEAM123456",
      privateKey: pem,
      bundleId: "com.example.app",
      now: clock.now,
      fetch: async (input, init) => {
        calls.push({ url: String(input), init: init! });
        return new Response(null, { status: 200 });
      },
    });

    const result = await sender.send({
      token: "ab".repeat(32),
      environment: "sandbox",
      priority: 10,
      payload: updatePayload(state, clock.seconds),
    });
    expect(result).toEqual({ status: 200 });

    const { url, init } = calls[0]!;
    expect(url).toBe(`https://api.sandbox.push.apple.com/3/device/${"ab".repeat(32)}`);
    const headers = init.headers as Record<string, string>;
    expect(headers["apns-push-type"]).toBe("liveactivity");
    expect(headers["apns-topic"]).toBe("com.example.app.push-type.liveactivity");
    expect(headers["apns-priority"]).toBe("10");
    expect(JSON.parse(init.body as string)).toEqual(updatePayload(state, clock.seconds));

    const jwt = headers.authorization!.replace(/^bearer /, "");
    const [header, claims, signature] = jwt.split(".");
    expect(decode(header!)).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(decode(claims!)).toEqual({ iss: "TEAM123456", iat: clock.seconds });
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      bytes(signature!),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);

    await sender.send({ token: "cd".repeat(32), environment: "production", priority: 5, payload: updatePayload(state, clock.seconds) });
    expect(calls[1]!.url.startsWith("https://api.push.apple.com/3/device/")).toBe(true);
  });

  it("caches the provider token for under an hour", async () => {
    const { pem } = await p8();
    const clock = new Clock(1_793_800_000);
    const tokens: string[] = [];
    const sender = createHttpApnsSender({
      keyId: "K",
      teamId: "T",
      privateKey: pem,
      bundleId: "b",
      now: clock.now,
      fetch: async (_input, init) => {
        tokens.push((init!.headers as Record<string, string>).authorization!);
        return new Response(null, { status: 200 });
      },
    });
    const push = () => sender.send({ token: "ab", environment: "sandbox", priority: 5, payload: updatePayload(state, clock.seconds) });

    await push();
    clock.advance(30 * MINUTE);
    await push();
    expect(tokens[1]).toBe(tokens[0]);

    expect(JWT_LIFETIME_SECONDS).toBeLessThan(60 * MINUTE);
    clock.advance(JWT_LIFETIME_SECONDS - 30 * MINUTE);
    await push();
    expect(tokens[2]).not.toBe(tokens[0]);
  });

  it("reports APNs's reason on failure", async () => {
    const { pem } = await p8();
    const sender = createHttpApnsSender({
      keyId: "K",
      teamId: "T",
      privateKey: pem,
      bundleId: "b",
      now: () => 1,
      fetch: async () => Response.json({ reason: "Unregistered" }, { status: 410 }),
    });
    expect(await sender.send({ token: "ab", environment: "sandbox", priority: 5, payload: updatePayload(state, 1) })).toEqual({
      status: 410,
      reason: "Unregistered",
    });
  });

  it("sends to a local fake APNs when an origin override is set (local development only)", async () => {
    const { pem } = await p8();
    const urls: string[] = [];
    const sender = createHttpApnsSender({
      keyId: "KEY1234567",
      teamId: "TEAM123456",
      privateKey: pem,
      bundleId: "com.example.app",
      now: () => 1_793_800_000,
      origin: "http://127.0.0.1:8788/",
      fetch: async (input) => {
        urls.push(String(input));
        return new Response(null, { status: 200 });
      },
    });

    await sender.send({ token: "cd".repeat(32), environment: "production", priority: 5, payload: updatePayload(state, 1) });

    expect(urls).toEqual([`http://127.0.0.1:8788/3/device/${"cd".repeat(32)}`]);
  });
});
