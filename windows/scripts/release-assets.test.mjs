import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { digest, verifyRelease } from "./release-assets.mjs";

function fixture() {
  const directory = mkdtempSync(join(tmpdir(), "committed-release-test-"));
  const version = "0.1.50";
  const commit = "a".repeat(40);
  const installer = `Committed-${version}-aaaaaaaa-x64-setup.exe`;
  const url = `https://github.com/prompthunt/commit-standings-releases/releases/download/v${version}/${installer}`;
  writeFileSync(join(directory, installer), "installer fixture");
  writeFileSync(join(directory, "Committed-Setup.exe"), "installer fixture");
  writeFileSync(
    join(directory, "latest-windows.json"),
    JSON.stringify({
      version,
      platforms: { "windows-x86_64": { signature: "fixture-signature", url } },
    }),
  );
  const metadata = { version, commit, installer, sha256: {} };
  for (const file of [installer, "Committed-Setup.exe", "latest-windows.json"])
    metadata.sha256[file] = digest(join(directory, file));
  writeFileSync(join(directory, "release.json"), JSON.stringify(metadata));
  return { directory, version, commit, installer };
}
test("an exact-version, exact-commit release verifies all three Windows assets", () => {
  const f = fixture();
  assert.equal(verifyRelease(f.directory, f.version, f.commit), f.installer);
});
test("a stale Windows artifact blocks publishing", () => {
  const f = fixture();
  assert.throws(
    () => verifyRelease(f.directory, f.version, "b".repeat(40)),
    /exact version and source commit/,
  );
});
test("a missing or modified stable installer blocks publishing", () => {
  const f = fixture();
  writeFileSync(join(f.directory, "Committed-Setup.exe"), "different bytes");
  assert.throws(
    () => verifyRelease(f.directory, f.version, f.commit),
    /changed Windows release asset/,
  );
});
test("a latest-download payload URL blocks publishing even if digests are updated", () => {
  const f = fixture();
  const manifestPath = join(f.directory, "latest-windows.json");
  const manifest = JSON.parse(readFileSync(manifestPath));
  manifest.platforms["windows-x86_64"].url =
    `https://github.com/prompthunt/commit-standings-releases/releases/latest/download/${f.installer}`;
  writeFileSync(manifestPath, JSON.stringify(manifest));
  const metadataPath = join(f.directory, "release.json");
  const metadata = JSON.parse(readFileSync(metadataPath));
  metadata.sha256["latest-windows.json"] = digest(manifestPath);
  writeFileSync(metadataPath, JSON.stringify(metadata));
  assert.throws(
    () => verifyRelease(f.directory, f.version, f.commit),
    /Invalid signed Windows update manifest/,
  );
});
