#!/usr/bin/env python3
"""Serialize cooperating native Apple development sessions across repositories."""
import argparse
import importlib.util
from contextlib import contextmanager
import fcntl
from functools import wraps
import math
import os
from pathlib import Path
import stat
import time

STATE = Path.home() / 'Library/Application Support/AppleDevelopment'
_depth = 0
_shared_runtime = None


@contextmanager
def native_session(state=None, wait_seconds=1800):
    """Hold one machine-wide lease for an entire build/test or interactive session.

    All participating repos must use this same flock path. Never unlink the lock:
    deleting it would let two processes lock different inodes. The OS releases it
    after exit, including a crash; no PID-based stale-lock deletion is needed.
    """
    global _depth
    if not math.isfinite(wait_seconds) or wait_seconds < 0:
        raise ValueError('Queue wait must be finite and nonnegative.')
    if _depth:
        _depth += 1
        try:
            yield
        finally:
            _depth -= 1
        return
    # Explicit test states retain the standalone mutex. Installed workstations
    # use the same shared FIFO runtime as Expo apps; CI needs no local install.
    runtime_path = Path.home() / '.local/share/apple-session/apple_session.py'
    if state is None and runtime_path.exists():
        global _shared_runtime
        if _shared_runtime is None:
            spec = importlib.util.spec_from_file_location('apple_session', runtime_path)
            _shared_runtime = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(_shared_runtime)
        with _shared_runtime.session(app='Committed',
                                     worktree=Path(__file__).resolve().parents[1],
                                     wait_seconds=wait_seconds):
            yield
        return
    state = Path(state or STATE).absolute()
    if any(p.is_symlink() for p in [state, *state.parents]):
        raise RuntimeError('Native session directory must not traverse symlinks.')
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = state.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError('Native session directory must be private to the current user.')
    fd = os.open(state / 'native-session.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise RuntimeError('Native session lock must be a private regular file.')
        deadline = time.monotonic() + wait_seconds
        announced = False
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if not announced:
                    print('Another agent owns the native development session; waiting. Do independent work; do not create another simulator or bypass the queue.', flush=True)
                    announced = True
                if time.monotonic() >= deadline:
                    raise RuntimeError('Native development session is busy. Wait for its owner and retry; no work was started.')
                time.sleep(min(0.2, max(0, deadline - time.monotonic())))
        _depth = 1
        try:
            yield
        finally:
            _depth = 0
    finally:
        os.close(fd)


def serialized_native(function):
    @wraps(function)
    def serialized(*args, **kwargs):
        with native_session():
            return function(*args, **kwargs)
    return serialized


def main():
    # Wrap an entire interactive script (build/install/launch/capture), not each
    # simctl command individually. Do not nest this CLI around ios.py/ios_check.py.
    from ios_tools import ROOT, preflight, run_bounded, termination_cleanup
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wait-seconds', type=float, default=1800)
    parser.add_argument('--timeout', type=float, default=1800)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('Supply a session script after --.')
    with termination_cleanup(), native_session(wait_seconds=args.wait_seconds):
        report = preflight(ROOT)
        print(report['message'], flush=True)
        if not report['ok']:
            return 1
        log = ROOT / 'build' / f'interactive-{time.time_ns()}.log'
        print(f'Interactive session output and receipt: {log}', flush=True)
        return run_bounded(command, log,
                           timeout=args.timeout, minimum_free_gib=5, capacity_path=ROOT)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except (OSError, RuntimeError, ValueError) as error:
        raise SystemExit(str(error))
