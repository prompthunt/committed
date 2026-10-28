import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const root = new URL('../', import.meta.url);
const plist = readFileSync(new URL('../CommitStandings/Info.plist', root), 'utf8');
export const version = plist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)?.[1];
if (!version || !/^\d+\.\d+\.\d+$/.test(version)) throw Error('Missing Mac release version');
for (const path of ['package.json', 'src-tauri/tauri.conf.json', 'src-tauri/Cargo.toml']) {
  const url = new URL(path, root);
  const text = readFileSync(url, 'utf8');
  const next = path.endsWith('.toml')
    ? text.replace(/^version = "[^"]+"/m, `version = "${version}"`)
    : text.replace(/"version": "[^"]+"/, `"version": "${version}"`);
  if (text !== next) {
    if (process.argv.includes('--check')) throw Error(`Version mismatch: ${fileURLToPath(url)}`);
    writeFileSync(url, next);
  }
}
