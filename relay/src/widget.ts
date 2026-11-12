import standbyCss from "../widget/standby.css";
import standbyHtml from "../widget/standby.html";
import standbyJs from "../widget/standby.js";
import interTightExtraBold from "../widget/fonts/InterTight-ExtraBold.ttf";
import interTightRegular from "../widget/fonts/InterTight-Regular.ttf";
import jetBrainsMonoMedium from "../widget/fonts/JetBrainsMono-Medium.ttf";
import { boardError } from "./board";

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
  /** The eyebrows' monospace (the TV has none), subset to Basic Latin, · and …. */
  "/v1/widget/fonts/JetBrainsMono-Medium.ttf": { body: jetBrainsMonoMedium, type: "font/ttf", cache: LONG },
};

/**
 * Tile sizes this widget comes in (Glance's ADR 0002: Apple's widget sizes, asked for with `size`),
 * the iPhone widget's own families: small is its rank card (`CommittedWidgetSmall`), medium the
 * StandBy pair, large the top of the board (`CommittedWidgetLarge`). One page serves all three;
 * standby.js reads `size` and lays itself out for it. `layout=standby`, the address before sizes,
 * still serves medium.
 */
export const WIDGET_SIZES = ["small", "medium", "large"];
export const WIDGET_LAYOUTS = ["standby"];

/** Replaces `find` in the page, failing at startup (and in tests) if the page no longer has it. */
function replaceOnce(source: string, find: string, replacement: string): string {
  if (!source.includes(find)) throw new Error(`widget/standby.html no longer contains ${find}`);
  return source.replace(find, replacement);
}

/**
 * Any other size gets the same page, already in its quiet "size not supported" state: the widget's
 * look, scaled to the tile, in place of an error page. The asked-for size is never echoed back.
 */
const unsupportedHtml = [
  ['data-state="loading"', 'data-state="unsupported"'],
  ['<p class="message-title" id="message-title"></p>', '<p class="message-title" id="message-title">Size not supported</p>'],
  [
    '<p class="message-detail" id="message-detail"></p>',
    '<p class="message-detail" id="message-detail">Committed\'s widget comes in small, medium and large. Open it as /v1/widget?size=medium.</p>',
  ],
].reduce((page, [find, replacement]) => replaceOnce(page, find!, replacement!), standbyHtml);

/** The served text, for the runtime-limit checks in test/widget-runtime.test.ts. */
export { standbyCss, standbyHtml, standbyJs, unsupportedHtml };

/** `GET /v1/widget[?size=small|medium|large]` (or the old `?layout=standby`) and its files, or null when the path isn't the widget's. */
export function widgetResponse(request: Request, url: URL): Response | null {
  if (url.pathname !== "/v1/widget" && !url.pathname.startsWith("/v1/widget/")) return null;
  if (request.method !== "GET" && request.method !== "HEAD") {
    return boardError(405, "method_not_allowed", "Use GET.");
  }
  if (url.pathname === "/v1/widget") {
    const size = url.searchParams.get("size");
    const layout = url.searchParams.get("layout");
    let page = standbyHtml;
    if (size !== null) {
      if (!WIDGET_SIZES.includes(size)) page = unsupportedHtml;
    } else if (layout !== null && !WIDGET_LAYOUTS.includes(layout)) {
      return boardError(404, "invalid_layout", "layout must be standby; ask for size=medium instead.");
    }
    return new Response(page, {
      headers: { "content-type": "text/html; charset=utf-8", "cache-control": SHORT, "referrer-policy": "no-referrer" },
    });
  }
  const file = WIDGET_FILES[url.pathname];
  if (!file) return boardError(404, "not_found", "No such widget file.");
  return new Response(file.body, { headers: { "content-type": file.type, "cache-control": file.cache } });
}
