import type { LiveRankState } from "./liveRank";

/**
 * APNs for Live Activities: token-based auth (ES256 JWT from a `.p8` key, signed with
 * WebCrypto) and the three ActivityKit events the relay sends: `update`, `end`, `start`
 * (push-to-start). See relay/README.md for the HTTP/2 spike and runtime choice.
 */

export type ApnsEnvironment = "sandbox" | "production";

export interface ApnsPayload {
  aps: {
    timestamp: number;
    event: "update" | "end" | "start";
    "content-state": LiveRankState;
    "stale-date"?: number;
    "dismissal-date"?: number;
    "attributes-type"?: string;
    attributes?: { selfLogin: string };
    alert?: { title: string; body: string };
  };
}

export interface ApnsRequest {
  token: string;
  environment: ApnsEnvironment;
  priority: 5 | 10;
  payload: ApnsPayload;
}

export interface ApnsResult {
  status: number;
  reason?: string;
}

export interface ApnsSender {
  send(request: ApnsRequest): Promise<ApnsResult>;
}

/** Each pushed state goes stale 20 minutes after its data (spec #39, "Staleness"). */
export const STALE_AFTER_SECONDS = 20 * 60;

export function updatePayload(state: LiveRankState, now: number): ApnsPayload {
  return {
    aps: {
      timestamp: now,
      event: "update",
      "content-state": state,
      "stale-date": state.updatedAt + STALE_AFTER_SECONDS,
    },
  };
}

export function endPayload(state: LiveRankState, now: number): ApnsPayload {
  return { aps: { timestamp: now, event: "end", "content-state": state, "dismissal-date": now } };
}

export function startPayload(state: LiveRankState, selfLogin: string, now: number): ApnsPayload {
  return {
    aps: {
      timestamp: now,
      event: "start",
      "content-state": state,
      "stale-date": state.updatedAt + STALE_AFTER_SECONDS,
      "attributes-type": "LiveRankAttributes",
      attributes: { selfLogin },
      // ActivityKit requires an alert to start an activity by push. No sound is set.
      alert: { title: "Committed", body: "Live rank is back on." },
    },
  };
}

/** True when APNs says the token will never work again, so the relay should forget it. */
export function isDeadToken(result: ApnsResult): boolean {
  if (result.status === 410) return true;
  return result.status === 400 && (result.reason === "BadDeviceToken" || result.reason === "DeviceTokenNotForTopic");
}

// MARK: - Provider token (JWT)

/** APNs accepts a provider token for up to an hour; refresh well before that. */
export const JWT_LIFETIME_SECONDS = 50 * 60;

export class ProviderToken {
  private cached: { token: string; issuedAt: number } | null = null;
  private key: Promise<CryptoKey> | null = null;

  constructor(
    private readonly keyId: string,
    private readonly teamId: string,
    private readonly privateKeyPem: string,
    private readonly now: () => number,
  ) {}

  async get(): Promise<string> {
    const now = this.now();
    if (this.cached && now - this.cached.issuedAt < JWT_LIFETIME_SECONDS) return this.cached.token;
    const header = base64url(JSON.stringify({ alg: "ES256", kid: this.keyId }));
    const claims = base64url(JSON.stringify({ iss: this.teamId, iat: now }));
    const signingInput = `${header}.${claims}`;
    // WebCrypto's ECDSA output is IEEE P1363 (r || s), which is exactly JWS's ES256 format.
    const signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      await this.signingKey(),
      new TextEncoder().encode(signingInput),
    );
    const token = `${signingInput}.${base64url(new Uint8Array(signature))}`;
    this.cached = { token, issuedAt: now };
    return token;
  }

  private signingKey(): Promise<CryptoKey> {
    this.key ??= crypto.subtle.importKey(
      "pkcs8",
      pemToBytes(this.privateKeyPem),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
    return this.key;
  }
}

// MARK: - HTTP sender

export interface HttpApnsConfig {
  keyId: string;
  teamId: string;
  privateKey: string;
  bundleId: string;
  now: () => number;
  fetch?: typeof fetch;
  /**
   * Local development only: send every push to this origin (a fake APNs, see `dev/fake-apns.mjs`)
   * instead of Apple's hosts. Local workerd can't speak HTTP/2 to APNs.
   */
  origin?: string;
}

const HOSTS: Record<ApnsEnvironment, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

export function createHttpApnsSender(config: HttpApnsConfig): ApnsSender {
  const provider = new ProviderToken(config.keyId, config.teamId, config.privateKey, config.now);
  const doFetch = config.fetch ?? fetch;
  return {
    async send(request) {
      const host = config.origin ? config.origin.replace(/\/+$/, "") : HOSTS[request.environment];
      const response = await doFetch(`${host}/3/device/${request.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${await provider.get()}`,
          "apns-push-type": "liveactivity",
          "apns-topic": `${config.bundleId}.push-type.liveactivity`,
          "apns-priority": String(request.priority),
          "content-type": "application/json",
        },
        body: JSON.stringify(request.payload),
      });
      if (response.status === 200) return { status: 200 };
      let reason: string | undefined;
      try {
        reason = ((await response.json()) as { reason?: string }).reason;
      } catch {
        reason = undefined;
      }
      return { status: response.status, reason };
    },
  };
}

function base64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function pemToBytes(pem: string): Uint8Array {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (char) => char.charCodeAt(0));
}
