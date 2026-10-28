import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
const root = new URL("../", import.meta.url);
const plist = readFileSync(
  new URL("../CommitStandings/Info.plist", root),
  "utf8",
);
export const version = plist.match(
  /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/,
)?.[1];
if (!version || !/^\d+\.\d+\.\d+$/.test(version))
  throw Error("Missing Mac release version");
for (const path of [
  "package.json",
  "src-tauri/tauri.conf.json",
  "src-tauri/Cargo.toml",
  "src-tauri/Cargo.lock",
  "package-lock.json",
]) {
  const url = new URL(path, root);
  const text = readFileSync(url, "utf8");
  let next = path.endsWith(".toml")
    ? text.replace(/^version = "[^"]+"/m, `version = "${version}"`)
    : text.replace(/"version": "[^"]+"/, `"version": "${version}"`);
  if (path.endsWith("Cargo.lock")) {
    next = text.replace(
      /(\[\[package\]\]\r?\nname = "committed-desktop"\r?\nversion = ")[^"]+"/,
      `$1${version}"`,
    );
  }
  if (path === "package-lock.json") {
    const lock = JSON.parse(text);
    lock.version = version;
    lock.packages[""].version = version;
    next = JSON.stringify(lock, null, 2) + "\n";
  }
  if (text !== next) {
    if (process.argv.includes("--check"))
      throw Error(`Version mismatch: ${fileURLToPath(url)}`);
    writeFileSync(url, next);
  }
}
