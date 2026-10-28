import { createHash } from 'node:crypto';
import { copyFileSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export function digest(path) { return createHash('sha256').update(readFileSync(path)).digest('hex'); }
export function verifyRelease(directory, version, commit) {
  const metadata = JSON.parse(readFileSync(join(directory, 'release.json'), 'utf8'));
  const expected = `Committed-${version}-${commit.slice(0, 8)}-x64-setup.exe`;
  if (metadata.version !== version || metadata.commit !== commit || metadata.installer !== expected) throw Error('Windows assets must match this exact version and source commit');
  for (const filename of [expected, 'Committed-Setup.exe', 'latest-windows.json']) {
    if (!metadata.sha256?.[filename] || digest(join(directory, filename)) !== metadata.sha256[filename]) throw Error(`Missing or changed Windows release asset: ${filename}`);
  }
  if (digest(join(directory, expected)) !== digest(join(directory, 'Committed-Setup.exe'))) throw Error('Stable installer differs from versioned installer');
  const manifest = JSON.parse(readFileSync(join(directory, 'latest-windows.json'), 'utf8'));
  const platform = manifest.platforms?.['windows-x86_64'];
  const url = `https://github.com/prompthunt/commit-standings-releases/releases/download/v${version}/${expected}`;
  if (manifest.version !== version || platform?.url !== url || !platform?.signature?.trim()) throw Error('Invalid signed Windows update manifest');
  return expected;
}
export function prepareRelease(root, commit) {
  if (!/^[0-9a-f]{40}$/.test(commit)) throw Error('A full source commit is required');
  const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
  const bundle = join(root, 'src-tauri/target/release/bundle/nsis');
  const candidates = readdirSync(bundle).filter(f => f.endsWith(`_${version}_x64-setup.exe`));
  if (candidates.length !== 1) throw Error('Expected exactly one x64 installer for the current version');
  const source = join(bundle, candidates[0]);
  const signature = readFileSync(`${source}.sig`, 'utf8').trim();
  if (!signature) throw Error('Missing Tauri updater signature');
  const directory = join(root, 'release');
  mkdirSync(directory, { recursive: true });
  const installer = `Committed-${version}-${commit.slice(0, 8)}-x64-setup.exe`;
  copyFileSync(source, join(directory, installer));
  copyFileSync(source, join(directory, 'Committed-Setup.exe'));
  writeFileSync(join(directory, 'latest-windows.json'), JSON.stringify({ version, notes: `Committed ${version}`, pub_date: new Date().toISOString(), platforms: {
    'windows-x86_64': { signature, url: `https://github.com/prompthunt/commit-standings-releases/releases/download/v${version}/${installer}` },
  } }, null, 2) + '\n');
  const files = [installer, 'Committed-Setup.exe', 'latest-windows.json'];
  writeFileSync(join(directory, 'release.json'), JSON.stringify({ version, commit, installer, sha256: Object.fromEntries(files.map(f => [f, digest(join(directory, f))])) }, null, 2) + '\n');
  verifyRelease(directory, version, commit);
  return directory;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const commit = process.env.GITHUB_SHA ?? execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
  console.log(prepareRelease(root, commit));
}
