import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

test("version verification accepts Windows CRLF without changing files", () => {
  const root = mkdtempSync(join(tmpdir(), "committed-version-test-"));
  const windows = join(root, "windows");
  mkdirSync(join(windows, "scripts"), { recursive: true });
  mkdirSync(join(windows, "src-tauri"), { recursive: true });
  mkdirSync(join(root, "CommitStandings"));
  copyFileSync(
    new URL("./sync-version.mjs", import.meta.url),
    join(windows, "scripts/sync-version.mjs"),
  );
  writeFileSync(
    join(root, "CommitStandings/Info.plist"),
    "<key>CFBundleShortVersionString</key>\n<string>0.1.50</string>",
  );
  writeFileSync(join(windows, "package.json"), '{"version": "0.1.50"}\r\n');
  writeFileSync(
    join(windows, "src-tauri/tauri.conf.json"),
    '{"version": "0.1.50"}\r\n',
  );
  writeFileSync(
    join(windows, "src-tauri/Cargo.toml"),
    'version = "0.1.50"\r\n',
  );
  writeFileSync(
    join(windows, "src-tauri/Cargo.lock"),
    '[[package]]\r\nname = "committed-desktop"\r\nversion = "0.1.50"\r\n',
  );
  const lock =
    JSON.stringify(
      { version: "0.1.50", packages: { "": { version: "0.1.50" } } },
      null,
      2,
    ).replace(/\n/g, "\r\n") + "\r\n";
  writeFileSync(join(windows, "package-lock.json"), lock);
  assert.doesNotThrow(() =>
    execFileSync(process.execPath, [
      join(windows, "scripts/sync-version.mjs"),
      "--check",
    ]),
  );
  assert.equal(readFileSync(join(windows, "package-lock.json"), "utf8"), lock);
});
