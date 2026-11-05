// APNs HTTP/2 probe. APNs speaks only HTTP/2: over HTTP/2 an unauthenticated POST gets
// `403 {"reason":"MissingProviderToken"}`; over HTTP/1.1 the connection is dropped. So the answer
// shows which protocol this runtime's outbound fetch() used, without any APNs key.
//
//   npx wrangler dev --config spike/wrangler.jsonc             # local workerd
//   npx wrangler dev --config spike/wrangler.jsonc --remote    # Cloudflare's edge (needs an account)
//   curl http://localhost:8787/

const PROBE_URL = "https://api.sandbox.push.apple.com/3/device/00";

export default {
  async fetch(): Promise<Response> {
    const started = Date.now();
    try {
      const response = await fetch(PROBE_URL, { method: "POST", body: "{}" });
      const body = await response.text();
      const http2 = response.status === 403 && body.includes("MissingProviderToken");
      return Response.json({
        probe: PROBE_URL,
        status: response.status,
        body: body.slice(0, 200),
        verdict: http2 ? "PASS: APNs answered over HTTP/2" : "FAIL: unexpected APNs answer",
        ms: Date.now() - started,
      });
    } catch (cause) {
      return Response.json(
        {
          probe: PROBE_URL,
          error: String(cause),
          verdict: "FAIL: request failed (APNs drops HTTP/1.1 connections)",
          ms: Date.now() - started,
        },
        { status: 502 },
      );
    }
  },
};
