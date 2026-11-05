// Fake APNs for local development: the local relay (wrangler dev) can't speak HTTP/2 to Apple,
// so point it here with APNS_ORIGIN=http://127.0.0.1:8788 in .dev.vars. Every push is printed
// (token shortened) and answered 200, so you can see exactly what the relay would send.
//
//   node dev/fake-apns.mjs            # listens on 127.0.0.1:8788
//   PORT=9000 node dev/fake-apns.mjs
import { createServer } from "node:http";

const port = Number(process.env.PORT ?? 8788);

createServer((request, response) => {
  let body = "";
  request.on("data", (chunk) => (body += chunk));
  request.on("end", () => {
    const token = request.url?.split("/").pop() ?? "";
    let payload;
    try {
      payload = JSON.parse(body);
    } catch {
      payload = body;
    }
    console.log(
      JSON.stringify({
        at: new Date().toISOString(),
        method: request.method,
        token: `${token.slice(0, 8)}…(${token.length} hex)`,
        pushType: request.headers["apns-push-type"],
        topic: request.headers["apns-topic"],
        priority: request.headers["apns-priority"],
        hasProviderToken: String(request.headers.authorization ?? "").startsWith("bearer "),
        payload,
      }),
    );
    response.writeHead(200, { "apns-id": crypto.randomUUID() });
    response.end();
  });
}).listen(port, "127.0.0.1", () => console.log(`fake APNs on http://127.0.0.1:${port}`));
