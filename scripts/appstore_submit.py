#!/usr/bin/env python3
"""Submit an uploaded iPhone build to the App Store, after TestFlight.

scripts/testflight.sh runs this for every build unless it's given --testflight-only, so each
TestFlight build also goes to App Review. Run it by hand to finish a submission that was
blocked, for example while the previous version was still in review:

  python3 scripts/appstore_submit.py --build-number 13
  python3 scripts/appstore_submit.py --build-number 13 --dry-run   # check, change nothing

The version is the one appstore/metadata is for (appstore_apply.VERSION), which must match the
build's. In order it:

  1. Creates that App Store version, unless it exists and can still be edited.
  2. Applies the listing (scripts/appstore_apply.py).
  3. Uploads the screenshots in docs/screenshots/app-store/.
  4. Validates the version, then attaches the build and submits it for App Review. Apple
     releases it as soon as it's approved (release type AFTER_APPROVAL).

Exits 3 without changing anything when App Store Connect can't take the build yet: another
version is still in review or waiting for release, or this version was already submitted.
It prints what's in the way and the command to run once it clears.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('appstore_apply', HERE / 'appstore_apply.py')
appstore = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(appstore)

APP_ID = appstore.APP_ID
PLATFORM = appstore.PLATFORM
SCREENSHOTS = HERE.parent / 'docs' / 'screenshots' / 'app-store'
DEVICE_TYPE = 'IPHONE_69'
BLOCKED = 3

# App Store version states. A version in EDITABLE takes a new build and listing; a version in
# LIVE is on the store or gone. Any other state (waiting for review, in review, pending
# release, processing) holds the app's one slot for an unreleased version.
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY'}
LIVE = {'READY_FOR_DISTRIBUTION', 'READY_FOR_SALE', 'REPLACED_WITH_NEW_VERSION', 'REMOVED_FROM_SALE',
        'DEVELOPER_REMOVED_FROM_SALE', 'NOT_APPLICABLE'}


def state(version):
    attributes = version['attributes']
    return attributes.get('appVersionState') or attributes.get('appStoreState')


def plan(versions, version_string):
    """What to do for version_string, given the app's versions on this platform.

    Returns ('create', None), ('use', version) or ('blocked', reason).
    """
    mine = next((v for v in versions if v['attributes']['versionString'] == version_string), None)
    if mine:
        if state(mine) in EDITABLE:
            return 'use', mine
        if state(mine) in LIVE:
            return 'blocked', f'{version_string} is already {state(mine)}. Number the next build as a new version.'
        return 'blocked', (f'{version_string} is {state(mine)} with another build. To ship this build instead, '
                           'cancel that submission in App Store Connect, then run this again.')
    in_flight = [v for v in versions if state(v) not in LIVE]
    if in_flight:
        names = ', '.join(f'{v["attributes"]["versionString"]} ({state(v)})' for v in in_flight)
        return 'blocked', (f'{names} must be released before App Store Connect creates {version_string}. '
                           'Its release type is after approval, so that happens once Apple approves it.')
    return 'create', None


def build_version(build_number):
    for build in appstore.asc_json('builds', 'list', '--app', APP_ID, '--paginate')['data']:
        if build['attributes'].get('version') == str(build_number):
            return build['id'], build['attributes'].get('processingState')
    sys.exit(f'App Store Connect has no build {build_number}.')


def build_marketing_version(build_id):
    data = appstore.asc_json('builds', 'pre-release-version', 'view', '--build-id', build_id).get('data') or {}
    return (data.get('attributes') or {}).get('version')


def listed_screenshots(version_string):
    """The version's screenshots in order, as (file name, size, delivery state)."""
    data = appstore.asc_json('screenshots', 'list', '--app', APP_ID, '--version', version_string,
                             '--locale', appstore.LOCALE)
    return [(a.get('fileName'), a.get('fileSize'), (a.get('assetDeliveryState') or {}).get('state'))
            for found in data.get('sets') or [] for a in (s['attributes'] for s in found.get('screenshots') or [])]


def screenshots_to_upload(shots, listed):
    """What to send, and whether to replace the set: nothing when the version already shows these
    files, only the missing tail when an earlier upload stopped partway, otherwise all of them.
    `shots` is [(name, size)]. Apple's screenshot processing can be slow enough that a full replace
    times out again and again, so a resubmission shouldn't redo it."""
    # A screenshot Apple is still processing counts as there; replacing it restarts the wait.
    there = [(name, size) for name, size, _ in listed]
    if there == shots[:len(there)]:
        return shots[len(there):], False
    return shots, True


def upload_screenshots(version_string):
    files = sorted(SCREENSHOTS.glob('[0-9][0-9]-*.png'))
    if not files:
        sys.exit(f'No screenshots in {SCREENSHOTS}.')
    shots = [(f.name, f.stat().st_size) for f in files]
    send, replace = screenshots_to_upload(shots, listed_screenshots(version_string))
    if not send:
        print(f'  unchanged ({len(shots)} screenshots)')
        return
    with tempfile.TemporaryDirectory(prefix='appstore-shots-') as stage:
        for name, _ in send:
            shutil.copy2(SCREENSHOTS / name, stage)
        appstore.asc('screenshots', 'upload', '--app', APP_ID, '--version', version_string, '--locale',
                     appstore.LOCALE, '--device-type', DEVICE_TYPE, '--path', stage,
                     *(['--replace', '--confirm'] if replace else []))
    print(f'  {len(send)} of {len(shots)} screenshots uploaded' + (' (replaced the set)' if replace else ''))


def blocking_checks(version_id):
    result = appstore.asc('validate', '--app', APP_ID, '--version-id', version_id, '--platform', PLATFORM,
                          '--output', 'json', ok=range(256))
    report = json.loads(result.stdout or '{}')
    steps = (report.get('remediation') or {}).get('steps') or []
    # The build isn't attached until `review submit`, so a missing build isn't a problem yet.
    return [s for s in steps if s.get('blocking') and 'build' not in (s.get('checkId') or '').split('.')[0]]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--build-number', required=True, help='the uploaded build to submit (CFBundleVersion)')
    parser.add_argument('--dry-run', action='store_true', help='show what would happen; change nothing')
    args = parser.parse_args(argv)
    version_string = appstore.VERSION
    retry = f'python3 scripts/appstore_submit.py --build-number {args.build_number}'

    build_id, processing = build_version(args.build_number)
    built_as = build_marketing_version(build_id)
    if built_as and built_as != version_string:
        sys.exit(f'Build {args.build_number} is version {built_as}, but appstore/metadata is for {version_string}.')

    versions = [v for v in appstore.asc_json('versions', 'list', '--app', APP_ID, '--paginate')['data']
                if v['attributes']['platform'] == PLATFORM]
    action, detail = plan(versions, version_string)
    if action == 'blocked':
        print(f'App Store: build {args.build_number} not submitted. {detail}')
        print(f'Then run: {retry}')
        return BLOCKED
    if args.dry_run:
        verb = 'create' if action == 'create' else 'update'
        print(f'Would {verb} App Store version {version_string}, apply the listing and screenshots, '
              f'and submit build {args.build_number} ({processing}) for App Review.')
        return 0

    if action == 'create':
        print(f'Creating App Store version {version_string}')
        appstore.asc('versions', 'create', '--app', APP_ID, '--version', version_string, '--platform', PLATFORM,
                     '--copyright', appstore.COPYRIGHT, '--release-type', appstore.RELEASE_TYPE, '--if-exists', 'skip')

    status = appstore.main([])
    if status:
        print(f'App Store: the listing needs you before build {args.build_number} can be submitted. Then run: {retry}')
        return status

    print('Screenshots')
    upload_screenshots(version_string)

    version_id = appstore.version_id()
    problems = blocking_checks(version_id)
    if problems:
        sys.exit('App Store Connect would refuse the submission:\n- ' +
                 '\n- '.join(f'{p.get("message")} ({p.get("remediation")})' for p in problems))

    print(f'Submitting {version_string} ({args.build_number}) for App Review')
    appstore.asc('review', 'submit', '--app', APP_ID, '--version', version_string, '--platform', PLATFORM,
                 '--build-number', str(args.build_number), '--wait', '--timeout', '45m', '--confirm')
    after = appstore.asc_json('versions', 'view', '--version-id', version_id)['data']
    print(f'App Store: {version_string} ({args.build_number}) is {state(after)}; '
          'Apple releases it as soon as it\'s approved.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
