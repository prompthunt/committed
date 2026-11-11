import { parse } from "acorn";
import { describe, expect, it } from "vitest";
import { standbyCss, standbyHtml, standbyJs, unsupportedHtml } from "../src/widget";

/**
 * The widget runs on the Samsung Frame's browser, Chromium 76 (ADR 0001 in addisonk/glance).
 * These checks read the exact files the route serves, so they can't drift from what's deployed.
 * The "size not supported" page is served too, so it's checked alongside the StandBy page.
 */

const pages = [standbyHtml, unsupportedHtml];

function parsesAsEs5(source: string): void {
  parse(source, { ecmaVersion: 5, sourceType: "script" });
}

/** CSS with comments removed, plus every inline `style="…"` in the page. */
const css = [standbyCss, ...pages.flatMap((html) => [...html.matchAll(/style="([^"]*)"/g)].map((m) => m[1]!))]
  .join("\n")
  .replace(/\/\*[\s\S]*?\*\//g, "");

const inlineScripts = pages.flatMap((html) =>
  [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map((m) => m[1]!),
);

describe("widget runtime limits (Chromium 76)", () => {
  it("parses its JavaScript as ES5", () => {
    expect(() => parsesAsEs5(standbyJs)).not.toThrow();
    for (const script of inlineScripts) expect(() => parsesAsEs5(script)).not.toThrow();
  });

  it("would catch ES2015 syntax", () => {
    for (const modern of ["const a = 1;", "let a = 1;", "var f = () => 1;", "var s = `x`;", "class A {}", "var {a} = b;"]) {
      expect(() => parsesAsEs5(modern), modern).toThrow();
    }
  });

  /** Chromium 76 lacks these (flex `gap` is 84, `inset` 87, `aspect-ratio` 88, `clamp()`/`min()`/`max()` 79). */
  const CHROMIUM_76_MISSING: [string, RegExp, string][] = [
    ["flex/grid gap", /(^|[\s;{])(row-|column-)?gap\s*:/m, ".a{display:flex;gap:8px}"],
    ["inset", /(^|[\s;{])inset\s*:/m, ".a{position:absolute;inset:0}"],
    ["aspect-ratio", /aspect-ratio/, ".a{aspect-ratio:1/1}"],
    ["clamp()", /\bclamp\(/, ".a{font-size:clamp(12px,2vw,20px)}"],
    ["min()", /\bmin\(/, ".a{width:min(100%,400px)}"],
    ["max()", /\bmax\(/, ".a{width:max(50%,200px)}"],
  ];
  /** Allowed on Chromium 76 but kept out for the Frame's GPU budget. */
  const TOO_HEAVY: [string, RegExp][] = [
    ["gradients", /gradient\(/],
    ["box-shadow", /box-shadow/],
    ["text-shadow", /text-shadow/],
    ["filter / blur", /(^|[\s;{-])filter\s*:|blur\(/m],
    ["CSS variables", /var\(--|(^|[\s;{])--[\w-]+\s*:/m],
  ];

  it.each(CHROMIUM_76_MISSING)("avoids %s in CSS (missing in Chromium 76)", (_name, banned) => {
    expect(css).not.toMatch(banned);
  });

  it.each(CHROMIUM_76_MISSING)("would catch %s", (_name, banned, sample) => {
    expect(sample).toMatch(banned);
  });

  it("would not flag what Chromium 76 has: margins, row-reverse, max-width", () => {
    const fine = ".a{margin:0 8px;flex-direction:row-reverse;max-width:400px;min-height:10px}";
    for (const [name, banned] of CHROMIUM_76_MISSING) expect(fine, name).not.toMatch(banned);
  });

  it.each(TOO_HEAVY)("avoids %s in CSS", (_name, banned) => {
    expect(css).not.toMatch(banned);
  });

  it("animates only opacity and transform", () => {
    const transitions = [...css.matchAll(/transition(?:-property)?\s*:\s*([^;}]+)/g)].map((m) => m[1]!);
    expect(transitions.length).toBeGreaterThan(0);
    for (const value of transitions) {
      for (const part of value.split(/,(?![^(]*\))/)) {
        const property = part.trim().split(/\s+/)[0];
        expect(["opacity", "transform", "-webkit-transform", "none"], value).toContain(property);
      }
    }
    for (const block of css.matchAll(/@(?:-webkit-)?keyframes[^{]+\{((?:[^{}]*\{[^}]*\})*)\s*\}/g)) {
      for (const declaration of block[1]!.matchAll(/([\w-]+)\s*:/g)) {
        expect(["opacity", "transform", "-webkit-transform"]).toContain(declaration[1]);
      }
    }
    // Inline transitions set from script go through the same two properties.
    for (const m of standbyJs.matchAll(/\.style\.(\w+)\s*=/g)) {
      expect(["transform", "webkitTransform", "opacity", "transition", "webkitTransition", "fontSize"]).toContain(m[1]);
    }
  });

  it("loads fonts and icons from the relay, and only avatars from GitHub", () => {
    for (const m of css.matchAll(/url\(\s*['"]?([^'")]+)/g)) expect(m[1]).toMatch(/^\/v1\/widget\//);
    for (const source of [...pages, standbyCss, standbyJs]) {
      for (const m of source.matchAll(/(?:https?:)?\/\/[\w.-]+\.[a-z]{2,}[^\s"')]*/g)) {
        expect(m[0]).toMatch(/^https:\/\/(github\.com|avatars\.githubusercontent\.com)\//);
      }
    }
    // The page's own files, or a reference inside the page (the trophy symbol).
    for (const html of pages) {
      for (const m of html.matchAll(/(?:src|href)="([^"]+)"/g)) expect(m[1]).toMatch(/^(\/v1\/widget\/|#)/);
    }
  });
});
