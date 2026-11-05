#!/usr/bin/env python3
"""Committed's native checks, serialized through the machine-wide native session.

  mac  Mac gate: CommitStandings build + test (same flags as CI), optionally the
       local packaging smoke test (--package).
  ios  iPhone app: CommitStandingsiOS tests on one disposable iPhone Duo / iOS 27.1
       simulator that is deleted afterwards.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from ios_tools import ROOT, preflight, run_bounded, termination_cleanup
from ios import run_xcode
from ios_simulators import SimulatorPool
from ios_session import serialized_native

PROJECT = 'CommitStandings.xcodeproj'
IOS_SCHEME = 'CommitStandingsiOS'
IOS_TESTS = 'CommitStandingsiOSTests'
IOS_RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-27-1'
IOS_DEVICE_TYPE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-Duo'
# Ad hoc signing without a team: identical to .github/workflows/ci.yml, no credentials.
UNSIGNED = ['CODE_SIGN_STYLE=Manual', 'CODE_SIGN_IDENTITY=-', 'DEVELOPMENT_TEAM=']


def minimum_gib():
    return float(os.environ.get('COMMITTED_MIN_FREE_GIB', '20'))


def ios_scheme_present(root=ROOT):
    return (root / PROJECT / 'xcshareddata' / 'xcschemes' / f'{IOS_SCHEME}.xcscheme').is_file()


def new_run_directory(suite):
    run = ROOT / 'build' / f'check-{suite}-{time.time_ns()}'
    run.mkdir(parents=True)
    return run


@serialized_native
def run_mac(package=False, test_timeout=1800):
    os.chdir(ROOT)
    run = new_run_directory('mac')
    result_path = run / 'tests.xcresult'
    status = run_xcode(['-project', PROJECT, '-scheme', 'CommitStandings', '-configuration', 'Debug',
                        '-destination', 'platform=macOS',
                        '-derivedDataPath', str(ROOT / 'build' / 'DerivedData'),
                        '-resultBundlePath', str(result_path), *UNSIGNED, 'build', 'test'],
                       run / 'mac.log', timeout=test_timeout)
    print(f'Mac gate exit {status}; diagnostics: {run}', flush=True)
    if status or not package:
        return status
    # package-release.sh drives xcodebuild itself; it runs inside this same lease.
    packaged = run_bounded([str(ROOT / 'scripts' / 'package-release.sh'),
                            '--skip-notarization', '--skip-git-check'],
                           run / 'package.log', timeout=1800, minimum_free_gib=5, capacity_path=ROOT)
    print((run / 'package.log').read_text(errors='replace')[-4000:], flush=True)
    print(f'Packaging smoke test exit {packaged}; log: {run / "package.log"}', flush=True)
    return packaged


@serialized_native
def run_ios(only_testing, test_timeout=1800):
    os.chdir(ROOT)
    report = preflight(ROOT, minimum_gib())
    print(json.dumps(report), flush=True)
    if not report['ok']:
        return 1
    xcode = subprocess.check_output(['xcodebuild', '-version'], text=True)
    print(xcode, flush=True)
    runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j']))['runtimes']
    runtime = next((r for r in runtimes if r['identifier'] == IOS_RUNTIME and r.get('isAvailable')), None)
    if not runtime:
        raise RuntimeError('The iPhone app needs the iOS 27.1 Simulator runtime. Install it through Xcode '
                           'Settings → Components; do not lower the deployment target. Available: '
                           + ', '.join(r['name'] for r in runtimes))
    print(json.dumps({key: runtime[key] for key in ['name', 'version', 'buildversion', 'identifier']}), flush=True)
    run = new_run_directory('ios')
    ownership = {}
    try:
        with SimulatorPool(minimum_gib=minimum_gib()).lease(IOS_RUNTIME, IOS_DEVICE_TYPE, ROOT) as ownership:
            device = ownership['udid']
            ownership.update(sourceRevision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                             suite='ios', xcode=xcode)
            (run / 'device.json').write_text(json.dumps(ownership, indent=2))
            base = ['-project', PROJECT, '-scheme', IOS_SCHEME,
                    '-destination', f'platform=iOS Simulator,id={device}',
                    '-derivedDataPath', str(ROOT / 'build' / 'DerivedData'), *UNSIGNED,
                    '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1']

            def execute(arguments, name, startup=None, timeout=1800):
                return run_xcode([*base, *arguments], run / f'{name}.log', startup_timeout=startup, timeout=timeout)

            if run_bounded(['xcrun', 'simctl', 'bootstatus', device, '-b'], run / 'boot.log', timeout=180):
                return 1
            compiled = execute(['build-for-testing'], 'compile')
            if compiled:
                return compiled
            selected = only_testing or [IOS_TESTS]
            print(json.dumps({'tests': selected}), flush=True)
            result_path = run / 'tests.xcresult'
            status = execute(['test-without-building', *[f'-only-testing:{t}' for t in selected],
                              '-resultBundlePath', str(result_path), '-test-timeouts-enabled', 'YES',
                              '-default-test-execution-time-allowance', '120',
                              '-maximum-test-execution-time-allowance', '180'],
                             'tests', startup=180, timeout=test_timeout)
            if result_path.exists():
                subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result_path),
                                '--output-path', str(run / 'attachments')], check=True, timeout=60)
                summary = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                          '--path', str(result_path)], capture_output=True, text=True, timeout=30)
                (run / 'summary.json').write_text(summary.stdout or summary.stderr)
                print(summary.stdout, flush=True)
            return status
    finally:
        if ownership:
            (run / 'device.json').write_text(json.dumps(ownership, indent=2))
            print(f'Diagnostics: {run}; disposable Simulator cleanup: {ownership.get("cleanupStatus", "unverified")}.',
                  flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('suite', choices=['mac', 'ios'])
    parser.add_argument('--package', action='store_true',
                        help='mac only: also run scripts/package-release.sh --skip-notarization --skip-git-check.')
    parser.add_argument('--only-testing', action='append', default=[],
                        help=f'ios only: a {IOS_TESTS}/... identifier; repeatable.')
    parser.add_argument('--test-timeout', type=int, default=1800,
                        help='Overall build/test execution budget in seconds.')
    args = parser.parse_args(argv)
    if args.test_timeout <= 0:
        parser.error('--test-timeout must be positive')
    # Validate before joining the queue so a wrong checkout never waits behind other apps.
    if args.suite == 'mac':
        if args.only_testing:
            parser.error('--only-testing applies to the ios suite.')
        return run_mac(args.package, args.test_timeout)
    if args.package:
        parser.error('--package applies to the mac suite.')
    if not ios_scheme_present():
        print(f'iPhone app not in this checkout: {PROJECT} has no shared {IOS_SCHEME} scheme. '
              'It lands with the iPhone app (spec #39); run this from a branch that contains it. '
              'No simulator was created and the native session was not requested.', file=sys.stderr)
        return 2
    requested = args.only_testing or os.environ.get('COMMITTED_IOS_ONLY_TESTING', '').split()
    if any(not value.startswith(IOS_TESTS + '/') for value in requested):
        parser.error(f'--only-testing identifiers must start with {IOS_TESTS}/')
    return run_ios(requested, args.test_timeout)


if __name__ == '__main__':
    try:
        with termination_cleanup():
            raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
