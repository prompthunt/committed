// APNs HTTP/2 spike (ticket #44). Deploy once on the real account to confirm the Workers
// edge reaches APNs over HTTP/2. No credentials are needed: an HTTP/2 connection with a
// garbage provider token gets `403 {"reason":"InvalidProviderToken"}` from Apple; an
// HTTP/1.1-only transport fails at the protocol level instead. See relay/README.md.
//
//   npx wrangler deploy -c spike/wrangler.spike.jsonc
//   curl https://committed-apns-spike.<subdomain>.workers.dev/
//   npx wrangler delete -c spike/wrangler.spike.jsonc

async function probe(withAuth) {
  const headers = {
    "apns-push-type": "liveactivity",
    "apns-topic": "com.addisonk.CommitStandings.iOS.push-type.liveactivity",
    "apns-priority": "5",
    "content-type": "application/json",
  };
  if (withAuth) headers.authorization = "bearer eyJhbGciOiJFUzI1NiJ9.garbage.garbage";
  const started = Date.now();
  try {
    const res = await fetch(`https://api.sandbox.push.apple.com/3/device/${"0".repeat(64)}`, {
      method: "POST",
      headers,
      body: JSON.stringify({ aps: { timestamp: Math.floor(Date.now() / 1000), event: "update", "content-state": {} } }),
    });
    return { withAuth, ok: true, status: res.status, body: await res.text(), ms: Date.now() - started };
  } catch (error) {
    return { withAuth, ok: false, error: String(error), ms: Date.now() - started };
  }
}

export default {
  async fetch() {
    const results = [await probe(true), await probe(false)];
    const http2 = results.every((r) => r.ok && r.status === 403);
    return Response.json({ http2, results });
  },
};
