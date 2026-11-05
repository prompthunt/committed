#!/usr/bin/env python3
"""Shared local iOS capacity preflight. Never deletes resources."""
import argparse
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import re
import signal
import time
from contextlib import contextmanager


@contextmanager
def termination_cleanup():
    """Let finally blocks stop owned children and release leases on SIGTERM too."""
    previous = signal.getsignal(signal.SIGTERM)
    def interrupted(signum, frame):
        raise KeyboardInterrupt('Termination requested')
    signal.signal(signal.SIGTERM, interrupted)
    try:
        yield
    finally:
        signal.signal(signal.SIGTERM, previous)


def run_bounded(command, log, timeout=1800, startup_timeout=None, minimum_free_gib=None, capacity_path=None):
    """Retain output and stop only the process group created by this invocation."""
    if not math.isfinite(timeout) or timeout <= 0 or (startup_timeout is not None and (not math.isfinite(startup_timeout) or startup_timeout <= 0)):
        raise ValueError('Runner deadlines must be positive.')
    if minimum_free_gib is not None and (not math.isfinite(minimum_free_gib) or minimum_free_gib <= 0):
        raise ValueError('Runtime disk floor must be positive and finite.')
    log = Path(log)
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    timed_out = False
    capacity_limited = False
    next_capacity_check = 0
    suite_started = False
    with log.open('w') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        receipt = {'pid': process.pid, 'command': command, 'cwd': str(Path.cwd()), 'timedOut': False}
        log.with_suffix('.json').write_text(json.dumps(receipt, indent=2))
        try:
            while process.poll() is None:
                elapsed = time.monotonic() - started
                if minimum_free_gib is not None and elapsed >= next_capacity_check:
                    available = shutil.disk_usage(capacity_path or log.parent).free / 1024**3
                    next_capacity_check = elapsed + 2
                    if available < minimum_free_gib:
                        capacity_limited = True
                        receipt.update(reason=f'Free disk below {minimum_free_gib:g} GiB runtime floor',
                                       availableGiB=round(available, 2))
                        break
                if startup_timeout is not None and not suite_started and elapsed >= startup_timeout:
                    suite_started = 'Test Suite ' in log.read_text(errors='replace')
                startup_expired = startup_timeout is not None and elapsed >= startup_timeout and not suite_started
                if elapsed >= timeout or startup_expired:
                    timed_out = True
                    receipt['reason'] = 'Test runner startup deadline' if startup_expired else 'Execution deadline'
                    break
                time.sleep(min(0.1, timeout))
        finally:
            if process.poll() is None:
                # The child is still alive, so its PID/session cannot have been reused.
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=10)
            receipt.update(timedOut=timed_out, capacityLimited=capacity_limited,
                           exitCode=125 if capacity_limited else 124 if timed_out else process.returncode,
                           elapsedSeconds=round(time.monotonic() - started, 2))
            if timed_out:
                try:
                    receipt['processes'] = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,comm='], text=True, timeout=5)
                except (OSError, subprocess.SubprocessError):
                    receipt['processes'] = 'Process diagnostic unavailable'
            log.with_suffix('.json').write_text(json.dumps(receipt, indent=2))
    return receipt['exitCode']

ROOT = Path(__file__).resolve().parents[1]


def record_cache_owner(root, cache):
    root, cache = Path(root).resolve(), Path(cache).absolute()
    if cache != root / 'build' / 'DerivedData' or cache.is_symlink():
        raise ValueError('Only this checkout\'s build/DerivedData can be registered.')
    marker = cache / '.committed-cache-owner.json'
    if cache.exists():
        if not marker.is_file() or json.loads(marker.read_text()).get('repository') != str(root):
            raise ValueError('Existing cache has unknown ownership; leave it intact and choose a fresh checkout.')
        return
    cache.mkdir(parents=True)
    marker.write_text(json.dumps({'repository': str(root), 'kind': 'DerivedData',
                                 'inode': cache.stat().st_ino}))


def inactive_caches(root, processes):
    # A failed process probe is uncertainty, not proof of inactivity.
    if processes is None:
        try:
            processes = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True, timeout=5).splitlines()
        except (OSError, subprocess.SubprocessError):
            return []
    if any(re.search(r'(xcodebuild|XCBBuildService|swift-frontend|clang|xctest|testmanagerd)', p) for p in processes):
        return []
    cache = root / 'build' / 'DerivedData'
    marker = cache / '.committed-cache-owner.json'
    if cache.is_symlink() or not marker.is_file() or cache.resolve() != cache:
        return []
    try:
        owner = json.loads(marker.read_text())
        if owner != {'repository': str(root), 'kind': 'DerivedData', 'inode': cache.stat().st_ino}:
            return []
        files = list(cache.rglob('*'))
        if any(p.is_symlink() for p in files):
            return []
        # Retention is based on the newest file, not the checkout's age.
        newest = max((p.stat().st_mtime for p in files if p.is_file()), default=cache.stat().st_mtime)
        if newest > time.time() - 7 * 86400:
            return []
        return [{'path': str(cache), 'bytes': sum(p.stat().st_size for p in files if p.is_file()),
                 'reason': 'Registered reproducible DerivedData for this checkout; inactive cache older than seven days; no native build/test process observed.'}]
    except (OSError, ValueError):
        return []


def preflight(root, minimum_gib=20, available_bytes=None, processes=None):
    root = Path(root).resolve()
    if not math.isfinite(minimum_gib) or minimum_gib <= 0:
        raise ValueError('Minimum free GiB must be a positive finite number.')
    available = shutil.disk_usage(root).free if available_bytes is None else available_bytes
    ok = available >= minimum_gib * 1024**3
    return {'ok': ok, 'availableGiB': round(available / 1024**3, 2),
            'minimumGiB': minimum_gib, 'candidates': [] if ok else inactive_caches(root, processes),
            'message': f'{available / 1024**3:.2f} GiB free; require {minimum_gib:g} GiB. '
                       + ('Capacity check passed.' if ok else
                          'Build blocked. Review inactive owned caches; preserve archives and Simulator data. '
                          'See .agents/rules/resource-cleanup.md, then rerun preflight.')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--minimum-gib', type=float, default=float(os.environ.get('COMMITTED_MIN_FREE_GIB', '20')))
    args = parser.parse_args()
    result = preflight(ROOT, args.minimum_gib)
    print(json.dumps(result, indent=2))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
