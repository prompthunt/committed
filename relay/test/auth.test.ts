import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { ApnsNotConfiguredError, cachedProviderToken, invalidateCachedProviderToken, signProviderToken } from "../src/auth";
import type { Env } from "../src/env";
import { T0 } from "./helpers";

async function p8Key(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  const base64 = btoa(String.fromCharCode(...pkcs8)).replace(/(.{64})/g, "$1\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

function decodeSegment(segment: string): unknown {
  const base64 = segment.replaceAll("-", "+").replaceAll("_", "/");
  return JSON.parse(atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4)));
}

function bytes(segment: string): Uint8Array {
  const base64 = segment.replaceAll("-", "+").replaceAll("_", "/");
  return Uint8Array.from(atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4)), (c) => c.charCodeAt(0));
}

describe("APNs provider token", () => {
  it("is an ES256 JWT that verifies against the key", async () => {
    const { pem, publicKey } = await p8Key();
    const token = await signProviderToken({ teamId: "TEAM123456", keyId: "KEY1234567", privateKeyPem: pem, issuedAt: T0 });
    const [header, claims, signature] = token.split(".");
    expect(decodeSegment(header!)).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(decodeSegment(claims!)).toEqual({ iss: "TEAM123456", iat: Math.floor(T0) });
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      bytes(signature!),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);
  });

  it("is reused for 50 minutes, then reissued", async () => {
    const { pem } = await p8Key();
    const configured: Env = { ...env, APNS_TEAM_ID: "TEAM123456", APNS_KEY_ID: "KEY1234567", APNS_PRIVATE_KEY: pem };
    const first = await cachedProviderToken(configured, T0);
    expect(await cachedProviderToken(configured, T0 + 49 * 60)).toBe(first);
    const later = await cachedProviderToken(configured, T0 + 50 * 60);
    expect(later).not.toBe(first);
    expect((decodeSegment(later.split(".")[1]!) as { iat: number }).iat).toBe(T0 + 50 * 60);
  });

  it("is reissued after APNs rejects it", async () => {
    const { pem } = await p8Key();
    const configured: Env = { ...env, APNS_TEAM_ID: "TEAM123456", APNS_KEY_ID: "KEY1234567", APNS_PRIVATE_KEY: pem };
    const first = await cachedProviderToken(configured, T0);
    await invalidateCachedProviderToken(configured);
    expect(await cachedProviderToken(configured, T0 + 60)).not.toBe(first);
  });

  it("fails clearly without the secrets", async () => {
    await expect(cachedProviderToken({ ...env, APNS_KEY_ID: undefined }, T0)).rejects.toBeInstanceOf(ApnsNotConfiguredError);
  });
});
