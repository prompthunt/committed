import assert from "node:assert/strict";
import { test } from "node:test";
import { detectDownloadPlatform, downloadTargets } from "./download-platform.ts";

const browser = { userAgent: "", platform: "", maxTouchPoints: 0 };

test("desktop visitors see only their matching download; unknown visitors retain both choices", () => {
  assert.deepEqual(downloadTargets("windows"), ["Windows"]);
  assert.deepEqual(downloadTargets("mac"), ["Mac"]);
  assert.deepEqual(downloadTargets("unknown"), ["Mac", "Windows"]);
});

test("desktop client hints choose the corresponding installer", () => {
  for (const [platform, expected] of [["Windows", "windows"], ["macOS", "mac"], ["Linux", "unknown"], ["", "unknown"]]) {
    assert.equal(detectDownloadPlatform({ ...browser, userAgentData: { platform, mobile: false } }), expected);
  }
});

test("browsers without client hints recognize desktop Windows and Mac user agents", () => {
  assert.equal(detectDownloadPlatform({ ...browser, userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" }), "windows");
  assert.equal(detectDownloadPlatform({ ...browser, userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15" }), "mac");
  assert.equal(detectDownloadPlatform(browser), "unknown");
});

test("phones and tablets retain both choices, including iPad desktop mode", () => {
  for (const userAgent of ["Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)", "Mozilla/5.0 (Linux; Android 15; Pixel)", "Mozilla/5.0 (Windows Phone 10.0; Windows NT 10.0; Android)"]) {
    assert.equal(detectDownloadPlatform({ ...browser, userAgent }), "unknown");
  }
  assert.equal(detectDownloadPlatform({ ...browser, platform: "MacIntel", maxTouchPoints: 5, userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15" }), "unknown");
  assert.equal(detectDownloadPlatform({ ...browser, userAgentData: { platform: "macOS", mobile: true } }), "unknown");
});

test("an explicit unsupported client platform doesn't fall through to a spoofed desktop UA", () => {
  assert.equal(detectDownloadPlatform({ ...browser, userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", userAgentData: { platform: "Linux", mobile: false } }), "unknown");
});
