// Token-based APNs auth: an ES256 JWT signed with the `.p8` key through WebCrypto.
// Apple: refresh no more than once every 20 minutes and no less than once every 60 minutes. The
// relay reuses a token for 50 minutes, cached in D1 so short-lived isolates share it, and drops it
// when APNs answers ExpiredProviderToken or InvalidProviderToken.

import type { Env } from "./env";

export const PROVIDER_TOKEN_LIFETIME_SECONDS = 50 * 60;
const CACHE_KEY = "apns_provider_token";

export class ApnsNotConfiguredError extends Error {
  constructor() {
    super("APNS_TEAM_ID, APNS_KEY_ID, and APNS_PRIVATE_KEY must be set");
    this.name = "ApnsNotConfiguredError";
  }
}

export interface ProviderTokenInput {
  teamId: string;
  keyId: string;
  /** PKCS #8 PEM, as in the `.p8` file Apple issues. */
  privateKeyPem: string;
  /** Unix seconds. */
  issuedAt: number;
}

export async function signProviderToken(input: ProviderTokenInput): Promise<string> {
  const key = await crypto.subtle.importKey("pkcs8", pemBytes(input.privateKeyPem), { name: "ECDSA", namedCurve: "P-256" }, false, [
    "sign",
  ]);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: input.keyId }));
  const claims = base64url(JSON.stringify({ iss: input.teamId, iat: Math.floor(input.issuedAt) }));
  const signingInput = `${header}.${claims}`;
  // WebCrypto ECDSA signatures are already raw r || s (IEEE P1363), the form JWS ES256 wants.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

interface CachedToken {
  token: string;
  issuedAt: number;
  keyId: string;
  teamId: string;
}

let memo: (CachedToken & { pem: string }) | null = null;

export async function cachedProviderToken(env: Env, now: number): Promise<string> {
  const { APNS_TEAM_ID: teamId, APNS_KEY_ID: keyId, APNS_PRIVATE_KEY: pem } = env;
  if (!teamId || !keyId || !pem) throw new ApnsNotConfiguredError();

  const fresh = (cached: CachedToken | null): cached is CachedToken =>
    cached !== null &&
    cached.keyId === keyId &&
    cached.teamId === teamId &&
    now - cached.issuedAt >= 0 &&
    now - cached.issuedAt < PROVIDER_TOKEN_LIFETIME_SECONDS;

  if (memo && memo.pem === pem && fresh(memo)) return memo.token;

  const row = await env.DB.prepare("SELECT value FROM relay_state WHERE key = ?").bind(CACHE_KEY).first<{ value: string }>();
  const stored = row ? (JSON.parse(row.value) as CachedToken) : null;
  if (fresh(stored)) {
    memo = { ...stored, pem };
    return stored.token;
  }

  const issuedAt = Math.floor(now);
  const token = await signProviderToken({ teamId, keyId, privateKeyPem: pem, issuedAt });
  const cached: CachedToken = { token, issuedAt, keyId, teamId };
  await env.DB.prepare(
    "INSERT INTO relay_state (key, value, updated_at) VALUES (?1, ?2, ?3) ON CONFLICT (key) DO UPDATE SET value = ?2, updated_at = ?3",
  )
    .bind(CACHE_KEY, JSON.stringify(cached), issuedAt)
    .run();
  memo = { ...cached, pem };
  return token;
}

export async function invalidateCachedProviderToken(env: Env): Promise<void> {
  memo = null;
  await env.DB.prepare("DELETE FROM relay_state WHERE key = ?").bind(CACHE_KEY).run();
}

function pemBytes(pem: string): ArrayBuffer {
  const base64 = pem.replace(/-----(BEGIN|END) [A-Z ]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0)).buffer;
}

function base64url(input: string | Uint8Array): string {
  const data = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of data) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}
