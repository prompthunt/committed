import standbyCss from "../widget/standby.css";
import standbyHtml from "../widget/standby.html";
import standbyJs from "../widget/standby.js";
import interTightExtraBold from "../widget/fonts/InterTight-ExtraBold.ttf";
import interTightRegular from "../widget/fonts/InterTight-Regular.ttf";

/**
 * The web widget (ticket #83): static HTML, CSS, ES5 JS and fonts with no data in them, served
 * publicly so another screen (Glance on the office Frame) can iframe it. The page reads the
 * installation ID and board read token from its URL fragment, which never reaches this server,
 * and calls the board route with a bearer header from this same origin.
 */

/** The page, stylesheet and script: short, so a fix reaches screens within a poll or two. */
const SHORT = "public, max-age=300";
/** The fonts never change. */
const LONG = "public, max-age=604800";

export const WIDGET_FILES: Record<string, { body: string | ArrayBuffer; type: string; cache: string }> = {
  "/v1/widget/standby.css": { body: standbyCss, type: "text/css; charset=utf-8", cache: SHORT },
  "/v1/widget/standby.js": { body: standbyJs, type: "text/javascript; charset=utf-8", cache: SHORT },
  "/v1/widget/fonts/InterTight-Regular.ttf": { body: interTightRegular, type: "font/ttf", cache: LONG },
  "/v1/widget/fonts/InterTight-ExtraBold.ttf": { body: interTightExtraBold, type: "font/ttf", cache: LONG },
};

export const WIDGET_LAYOUTS = ["standby"];

/** The served text, for the runtime-limit checks in test/widget-runtime.test.ts. */
export { standbyCss, standbyHtml, standbyJs };

/** `GET /v1/widget[?layout=standby]` and its files, or null when the path isn't the widget's. */
export function widgetResponse(request: Request, url: URL): Response | null {
  if (url.pathname !== "/v1/widget" && !url.pathname.startsWith("/v1/widget/")) return null;
  if (request.method !== "GET" && request.method !== "HEAD") {
    return Response.json({ error: "method_not_allowed", message: "Use GET." }, { status: 405 });
  }
  if (url.pathname === "/v1/widget") {
    const layout = url.searchParams.get("layout") ?? "standby";
    if (!WIDGET_LAYOUTS.includes(layout)) {
      return Response.json({ error: "invalid_layout", message: "layout must be standby." }, { status: 404 });
    }
    return new Response(standbyHtml, {
      headers: { "content-type": "text/html; charset=utf-8", "cache-control": SHORT, "referrer-policy": "no-referrer" },
    });
  }
  const file = WIDGET_FILES[url.pathname];
  if (!file) return Response.json({ error: "not_found", message: "No such widget file." }, { status: 404 });
  return new Response(file.body, { headers: { "content-type": file.type, "cache-control": file.cache } });
}
