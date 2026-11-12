import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { createRelay } from "../src/relay";
import { WIDGET_SIZES } from "../src/widget";
import { Clock, FakeApns, FakeGitHub } from "./support/fakes";

let github: FakeGitHub;
let relay: ReturnType<typeof createRelay>;

beforeEach(() => {
  github = new FakeGitHub();
  relay = createRelay({
    db: env.DB,
    apns: new FakeApns(),
    github: github.fetch,
    githubName: github.name,
    now: new Clock(1_793_804_400).now,
    bundleId: "b",
    log: () => {},
  });
});

function get(path: string, init?: RequestInit): Promise<Response> {
  return relay.fetch(new Request(`https://relay.test${path}`, init));
}

describe("GET /v1/widget", () => {
  it("serves the page for small, medium and large, the default and the old layout=standby", async () => {
    expect(WIDGET_SIZES).toEqual(["small", "medium", "large"]);
    for (const path of [
      "/v1/widget?size=small",
      "/v1/widget?size=medium",
      "/v1/widget?size=large",
      "/v1/widget",
      "/v1/widget?layout=standby",
    ]) {
      const res = await get(path);
      expect(res.status).toBe(200);
      expect(res.headers.get("content-type")).toMatch(/^text\/html/);
      const html = await res.text();
      expect(html).toMatch(/<!doctype html>/i);
      expect(html).toContain("/v1/widget/standby.js");
      expect(html).toContain("/v1/widget/standby.css");
      // The page lays itself out for the size (standby.js reads ?size=); it's never "unsupported".
      expect(html, path).toMatch(/<html[^>]*data-state="loading"/);
      expect(html, path).not.toContain("Size not supported");
    }
  });

  it("shows a quiet size-not-supported state, not an error, for any other size", async () => {
    for (const size of ["extraLarge", "Small", "Medium", "LARGE", "", "<b>x</b>"]) {
      const res = await get(`/v1/widget?size=${encodeURIComponent(size)}`);
      expect(res.status, size).toBe(200);
      expect(res.headers.get("content-type")).toMatch(/^text\/html/);
      const html = await res.text();
      expect(html).toMatch(/<html[^>]*data-state="unsupported"/);
      expect(html).toContain("Size not supported");
      expect(html).toContain("small, medium and large");
      expect(html).toContain("size=medium");
      // The same page and files, so it looks like the widget and fits the tile.
      expect(html).toContain("/v1/widget/standby.css");
      // What was asked for is never echoed into the page.
      expect(html).not.toContain("<b>x</b>");
    }
  });

  it("decides by size when both size and layout are given", async () => {
    const unsupported = await get("/v1/widget?size=extraLarge&layout=standby");
    expect(await unsupported.text()).toContain("Size not supported");
    for (const size of ["small", "medium", "large"]) {
      const served = await get(`/v1/widget?size=${size}&layout=standby`);
      expect(await served.text(), size).not.toContain("Size not supported");
    }
  });

  it("serves its stylesheet, script and fonts from the relay", async () => {
    const css = await get("/v1/widget/standby.css");
    expect(css.status).toBe(200);
    expect(css.headers.get("content-type")).toMatch(/^text\/css/);
    const js = await get("/v1/widget/standby.js");
    expect(js.status).toBe(200);
    expect(js.headers.get("content-type")).toMatch(/^text\/javascript/);
    expect(await js.text()).toContain("use strict");
    for (const face of ["Regular", "ExtraBold"]) {
      const font = await get(`/v1/widget/fonts/InterTight-${face}.ttf`);
      expect(font.status).toBe(200);
      expect(font.headers.get("content-type")).toBe("font/ttf");
      const bytes = new Uint8Array(await font.arrayBuffer());
      expect(bytes.byteLength).toBeGreaterThan(100_000);
      // A TrueType file starts with the sfnt version 0x00010000.
      expect([...bytes.slice(0, 4)]).toEqual([0, 1, 0, 0]);
    }
    // The eyebrows' monospace face: JetBrains Mono Medium, subset to Basic Latin, so it's small.
    const mono = await get("/v1/widget/fonts/JetBrainsMono-Medium.ttf");
    expect(mono.status).toBe(200);
    expect(mono.headers.get("content-type")).toBe("font/ttf");
    const bytes = new Uint8Array(await mono.arrayBuffer());
    expect(bytes.byteLength).toBeGreaterThan(4_000);
    expect(bytes.byteLength).toBeLessThan(40_000);
    expect([...bytes.slice(0, 4)]).toEqual([0, 1, 0, 0]);
  });

  it("can be framed by another screen", async () => {
    const res = await get("/v1/widget");
    expect(res.headers.get("x-frame-options")).toBeNull();
    expect(res.headers.get("content-security-policy") ?? "").not.toMatch(/frame-ancestors/);
  });

  it("404s an unknown layout or file in the board route's error shape", async () => {
    const layout = await get("/v1/widget?layout=poster");
    expect(layout.status).toBe(404);
    expect(layout.headers.get("cache-control")).toBe("no-store");
    expect(await layout.json()).toMatchObject({ error: "invalid_layout" });
    const file = await get("/v1/widget/secrets.txt");
    expect(file.status).toBe(404);
    expect(file.headers.get("cache-control")).toBe("no-store");
    expect(await file.json()).toMatchObject({ error: "not_found", message: expect.any(String) });
  });

  it("only answers GET", async () => {
    const res = await get("/v1/widget", { method: "POST" });
    expect(res.status).toBe(405);
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(await res.json()).toEqual({ error: "method_not_allowed", message: expect.any(String) });
  });
});
