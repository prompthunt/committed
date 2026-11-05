#!/usr/bin/env python3
"""Run xcodebuild with capacity preflight, a deadline and retained diagnostics.

python3 scripts/ios.py -- <normal xcodebuild build/archive/export arguments>

Tests use scripts/ios_check.py (mac or ios), which owns test devices and results.
"""
import argparse
import json
import os
from pathlib import Path
import time
from ios_session import serialized_native
from ios_tools import ROOT, preflight, run_bounded, record_cache_owner, termination_cleanup

TEST_ACTIONS = ['test', 'test-without-building', 'build-for-testing']


@serialized_native
def run_xcode(arguments, log=None, timeout=1800, startup_timeout=None, minimum_gib=None):
    if minimum_gib is None:
        minimum_gib = float(os.environ.get('COMMITTED_MIN_FREE_GIB', '20'))
    report = preflight(ROOT, minimum_gib)
    print(json.dumps(report), flush=True)
    if not report['ok']:
        return 1
    if '-derivedDataPath' in arguments:
        cache = Path(arguments[arguments.index('-derivedDataPath') + 1]).absolute()
        if cache == ROOT / 'build' / 'DerivedData' and not cache.exists():
            record_cache_owner(ROOT, cache)
    log = Path(log) if log else ROOT / 'build' / f'ios-{time.time_ns()}.log'
    print(f'Build output: {log}', flush=True)
    result = run_bounded(['xcodebuild', *arguments], log, timeout, startup_timeout,
                         minimum_free_gib=5, capacity_path=ROOT)
    print(log.read_text(errors='replace')[-6000:], flush=True)
    print(f'Exit {result}; diagnostics: {log.with_suffix(".json")}', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--timeout', type=float, default=1800)
    parser.add_argument('--startup-timeout', type=float)
    parser.add_argument('--log', type=Path)
    parser.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    arguments = args.arguments[1:] if args.arguments[:1] == ['--'] else args.arguments
    if not arguments:
        parser.error('Supply xcodebuild arguments after --.')
    if any(action in arguments for action in TEST_ACTIONS):
        parser.error('Tests must use scripts/ios_check.py mac (Mac gate) or scripts/ios_check.py ios '
                     '(iPhone app, disposable simulator).')
    return run_xcode(arguments, args.log, args.timeout, args.startup_timeout)


if __name__ == '__main__':
    try:
        with termination_cleanup():
            raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except (OSError, RuntimeError, ValueError) as error:
        raise SystemExit(str(error))
