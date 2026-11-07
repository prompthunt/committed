#!/usr/bin/env python3
"""Validate only newly added runtime screenshot evidence, never attachment delivery."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

IMAGES = {'.png', '.jpg', '.jpeg', '.webp', '.heic'}
# App assets, design references, avatars and icons are not runtime captures.
# Keep exceptions explicit; never exempt docs/screenshots/.
ASSETS = ('CommitStandings/Assets.xcassets/', 'CommitStandingsiOS/Assets.xcassets/',
          'CommitStandingsLiveRank/Assets.xcassets/', 'docs/design/', 'fixtures/',
          'site/public/', 'site/src/assets/', 'video/', 'windows/src-tauri/icons/')


def check(root, added):
    errors = []
    for filename in added:
        path = Path(filename)
        if path.suffix.lower() not in IMAGES or filename.startswith(ASSETS):
            continue
        if not filename.startswith('docs/screenshots/') or len(path.parts) < 4:
            errors.append(f'{filename}: runtime screenshots belong under docs/screenshots/<change>/ with manifest.json.')
            continue
        manifest_path = root / Path(*path.parts[:3]) / 'manifest.json'
        try:
            manifest = json.loads(manifest_path.read_text())
            if not isinstance(manifest, dict) or not isinstance(manifest.get('screenshots'), list):
                raise ValueError('manifest must contain a screenshots array')
            if any(not isinstance(entry, dict) for entry in manifest['screenshots']):
                raise ValueError('each screenshots entry must be an object')
            relative = path.relative_to(Path(*path.parts[:3])).as_posix()
            records = [s for s in manifest['screenshots'] if s.get('file') == relative]
            if len(records) != 1:
                raise ValueError('exactly one matching screenshots[].file entry is required')
            entry = records[0]
            capture = entry.get('capture', {})
            if not isinstance(capture, dict):
                raise ValueError('capture must be an object with device, os, sourceCommit and fixture provenance')
            requirements = {
                'device': capture.get('device', manifest.get('device')),
                'OS/runtime': capture.get('os', manifest.get('os')),
                'screen/state caption': entry.get('caption'),
            }
            for requirement, value in requirements.items():
                if not isinstance(value, str) or not value.strip():
                    errors.append(f'{filename}: missing {requirement} provenance.')
            commit = capture.get('sourceCommit', manifest.get('sourceCommit', ''))
            if not isinstance(commit, str) or not re.fullmatch(r'[0-9a-f]{40}', commit):
                errors.append(f'{filename}: sourceCommit must be the full capture revision (40 hex characters).')
            if type(capture.get('fixture')) is not bool:
                errors.append(f'{filename}: capture.fixture must explicitly identify fixture (true) or live (false) data.')
        except (OSError, ValueError, KeyError, TypeError) as error:
            errors.append(f'{filename}: invalid or missing {manifest_path.relative_to(root)}: {error}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True, help='PR base revision; compare its merge-base to HEAD')
    args = parser.parse_args()
    root = Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip())
    added = subprocess.check_output(['git', 'diff', '--no-renames', '--name-only', '--diff-filter=A', '-z', f'{args.base}...HEAD'], cwd=root).decode().split('\0')
    errors = check(root, added)
    for error in errors:
        print(error, file=sys.stderr)
    if not errors:
        print('New screenshot storage/provenance passed. GitHub attachment upload and inline rendering remain separate checks.')
    return int(bool(errors))


if __name__ == '__main__':
    raise SystemExit(main())
