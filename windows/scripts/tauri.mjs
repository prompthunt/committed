import "./sync-version.mjs";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const cli = require.resolve("@tauri-apps/cli/tauri.js");
const args = process.argv.slice(2);
if (args[0] === "build") {
  if (!args.includes("--")) args.push("--");
  if (!args.includes("--locked")) args.push("--locked");
}
const result = spawnSync(process.execPath, [cli, ...args], {
  stdio: "inherit",
});
process.exit(result.status ?? 1);
