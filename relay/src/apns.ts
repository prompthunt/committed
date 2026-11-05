// APNs delivery for ActivityKit pushes.
//
// The transport is an interface so the runtime is a swap: `FetchApnsTransport` uses the Workers
// `fetch()`; a Vercel Node function would implement the same interface over `node:http2`
// (see relay/README.md, "APNs HTTP/2 spike").

import type { Env } from "./env";

export type ApnsEnvironment = "sandbox" | "production";

export const APNS_HOSTS: Record<ApnsEnvironment, string> = {
  sandbox: "api.sandbox.push.apple.com",
  production: "api.push.apple.com",
};

export interface ApnsRequest {
  environment: ApnsEnvironment;
  /** Hex device token (a push-to-start or activity update token). Never log it. */
  deviceToken: string;
  headers: Record<string, string>;
  body: string;
}

export interface ApnsResponse {
  status: number;
  /** APNs `reason` string on failure, e.g. `BadDeviceToken`. */
  reason?: string;
}

export interface ApnsTransport {
  send(request: ApnsRequest): Promise<ApnsResponse>;
}

/** POST https://<host>/3/device/<token> with the Workers fetch API. */
export class FetchApnsTransport implements ApnsTransport {
  async send(request: ApnsRequest): Promise<ApnsResponse> {
    const url = `https://${APNS_HOSTS[request.environment]}/3/device/${request.deviceToken}`;
    const response = await fetch(url, { method: "POST", headers: request.headers, body: request.body });
    if (response.ok) return { status: response.status };
    let reason: string | undefined;
    try {
      reason = ((await response.json()) as { reason?: string }).reason;
    } catch {
      reason = undefined;
    }
    return reason === undefined ? { status: response.status } : { status: response.status, reason };
  }
}

/** What to do with the token after a push. */
export type PushOutcome = "delivered" | "token-gone" | "retry";

export interface PushSender {
  apns: ApnsTransport;
  providerToken(env: Env): Promise<string>;
  invalidateProviderToken(env: Env): Promise<void>;
}

export interface Push {
  environment: ApnsEnvironment;
  token: string;
  priority: 5 | 10;
  payload: unknown;
}

const GONE_REASONS = new Set(["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered", "ExpiredToken"]);
const PROVIDER_TOKEN_REASONS = new Set(["ExpiredProviderToken", "InvalidProviderToken"]);

/** Sends one Live Activity push and classifies the response. */
export async function sendPush(sender: PushSender, env: Env, push: Push): Promise<{ outcome: PushOutcome; status: number; reason?: string }> {
  const response = await sender.apns.send({
    environment: push.environment,
    deviceToken: push.token,
    headers: {
      authorization: `bearer ${await sender.providerToken(env)}`,
      "apns-push-type": "liveactivity",
      "apns-topic": `${env.APNS_BUNDLE_ID}.push-type.liveactivity`,
      "apns-priority": String(push.priority),
      "content-type": "application/json",
    },
    body: JSON.stringify(push.payload),
  });
  const result = { status: response.status, ...(response.reason === undefined ? {} : { reason: response.reason }) };
  if (response.status >= 200 && response.status < 300) return { outcome: "delivered", ...result };
  if (response.status === 410 || (response.status === 400 && GONE_REASONS.has(response.reason ?? ""))) {
    return { outcome: "token-gone", ...result };
  }
  if (response.status === 403 && PROVIDER_TOKEN_REASONS.has(response.reason ?? "")) {
    await sender.invalidateProviderToken(env);
  }
  return { outcome: "retry", ...result };
}
