#!/usr/bin/env python3
"""Bounded, cross-worktree ownership of the single disposable Committed test simulator."""
import argparse
from contextlib import contextmanager, ExitStack
import fcntl
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid


STATE = Path.home() / 'Library/Application Support/Committed/agent-simulators'
OWNER = 'committed-ios-check/v1'
PREFIX = 'CommittedAgent-'
SLOTS = 1  # at most one automated-test simulator across Committed worktrees


class Simctl:
    def call(self, *arguments):
        return subprocess.check_output(['xcrun', 'simctl', *arguments], text=True, timeout=60).strip()

    def devices(self):
        return {d['udid']: dict(d, runtime=runtime)
                for runtime, devices in json.loads(self.call('list', 'devices', '-j'))['devices'].items()
                for d in devices}

    def create(self, record):
        return self.call('create', record['name'], record['deviceTypeIdentifier'], record['runtime'])

    def shutdown(self, udid):
        self.call('shutdown', udid)

    def delete(self, udid):
        self.call('delete', udid)

    def inactive(self, udid):
        # Shutdown alone does not prove that another task has finished using a device.
        try:
            opened = subprocess.run(['lsof', '-nP', '-Fpn'], capture_output=True, text=True, timeout=30)
            processes = subprocess.check_output(['ps', '-axo', 'args='], text=True, timeout=10)
            return opened.returncode == 0 and udid not in opened.stdout and udid not in processes
        except (OSError, subprocess.SubprocessError):
            return False


class SimulatorPool:
    def __init__(self, state=STATE, backend=None, minimum_gib=20):
        if not math.isfinite(minimum_gib) or minimum_gib <= 0:
            raise ValueError('Minimum free GiB must be positive and finite.')
        self.state = Path(state).absolute()
        self.backend = backend or Simctl()
        self.minimum_gib = minimum_gib

    def _prepare(self):
        for p in [self.state, *self.state.parents]:
            if p.is_symlink():
                raise RuntimeError('Simulator ownership directory must not traverse symlinks.')
        self.state.mkdir(parents=True, mode=0o700, exist_ok=True)
        if self.state.stat().st_uid != os.getuid() or self.state.stat().st_mode & 0o077:
            raise RuntimeError('Simulator ownership directory must be private to the current user.')

    @contextmanager
    def _slot(self, number):
        flags = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW
        fd = os.open(self.state / f'{number}.lock', flags, 0o600)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                yield None
                return
            yield self.state / f'{number}.json'
        finally:
            os.close(fd)

    def _read(self, path):
        if path.is_symlink():
            raise RuntimeError('Refusing symlinked simulator ownership receipt.')
        if not path.exists():
            return None
        with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW)) as receipt:
            record = json.load(receipt)
        token = record.get('token', '')
        if (record.get('owner') != OWNER or not re.fullmatch('[a-f0-9]{32}', token)
                or record.get('name') != PREFIX + token):
            raise RuntimeError('Unknown simulator ownership receipt; preserved.')
        return record

    def _write(self, path, record):
        temporary = path.with_suffix('.' + uuid.uuid4().hex + '.tmp')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'w') as receipt:
            json.dump(record, receipt, indent=2)
            receipt.flush()
            os.fsync(receipt.fileno())
        os.replace(temporary, path)

    def _device(self, record):
        devices = self.backend.devices()
        if record.get('udid'):
            device = devices.get(record['udid'])
        else:
            matches = [d for d in devices.values() if d['name'] == record['name']]
            if len(matches) > 1:
                raise RuntimeError('Ambiguous simulator creation receipt; preserved.')
            device = matches[0] if matches else None
        if device and any(device.get(k) != record[k]
                          for k in ['name', 'runtime', 'deviceTypeIdentifier']):
            raise RuntimeError('Simulator identity changed; preserved.')
        return device

    def _retire(self, path, record, current_owner=False, apply=True):
        device = self._device(record)
        if device is None:
            if apply:
                path.unlink(missing_ok=True)
            return 'already absent'
        udid = device['udid']
        if device['state'] != 'Shutdown':
            if not current_owner:
                raise RuntimeError('Abandoned device is booted; current use is uncertain. Preserved.')
            self.backend.shutdown(udid)
            device = self._device(record)
        if device is None or device['state'] != 'Shutdown' or not self.backend.inactive(udid):
            raise RuntimeError('Simulator inactivity cannot be verified; ownership receipt preserved.')
        if not apply:
            return 'eligible owned disposable device'
        self.backend.delete(udid)
        if self._device(record) is not None:
            raise RuntimeError('Simulator deletion could not be verified; receipt preserved.')
        path.unlink()
        return 'deleted'

    @contextmanager
    def lease(self, runtime, device_type, checkout, timeout=120):
        self._prepare()
        deadline = time.monotonic() + timeout
        blockers = []
        while True:
            with ExitStack() as held:
                paths = [held.enter_context(self._slot(number)) for number in range(SLOTS)]
                if all(path is not None for path in paths):
                    try:
                        # Recover an abandoned device before provisioning its replacement.
                        for old_path in paths:
                            previous = self._read(old_path)
                            if previous:
                                self._retire(old_path, previous)
                    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
                        blockers.append(str(error))
                    else:
                        path = paths[0]
                        if shutil.disk_usage(self.state).free < self.minimum_gib * 1024**3:
                            raise RuntimeError(f'Simulator creation requires {self.minimum_gib:g} GiB free.')
                        token = uuid.uuid4().hex
                        record = dict(owner=OWNER, token=token, name=PREFIX + token,
                                      runtime=runtime, deviceTypeIdentifier=device_type,
                                      checkout=str(Path(checkout).resolve()), pid=os.getpid(),
                                      createdAt=time.time(), udid=None)
                        # Write intent before create: a crash immediately after simctl still has provenance.
                        self._write(path, record)
                        try:
                            created = self.backend.create(record)
                            uuid.UUID(created)
                            record['udid'] = created
                            self._write(path, record)
                            yield record
                        finally:
                            try:
                                record['cleanupStatus'] = self._retire(path, record, current_owner=True)
                            except Exception:
                                record['cleanupStatus'] = 'preserved; see durable ownership receipt'
                                raise
                        return
            if time.monotonic() >= deadline:
                detail = '; '.join(sorted(set(blockers))) or 'the single test simulator is leased; wait for its owner'
                raise RuntimeError('Disposable simulator capacity reached: ' + detail)
            time.sleep(min(0.2, max(0, deadline - time.monotonic())))

    def cleanup(self, apply=False):
        if not self.state.exists():
            return []
        self._prepare()
        result = []
        for number in range(SLOTS):
            with self._slot(number) as path:
                if path is None:
                    result.append(dict(slot=number, status='active lease; preserved'))
                    continue
                try:
                    record = self._read(path)
                    if record:
                        result.append(dict(slot=number, udid=record.get('udid'),
                                           status=self._retire(path, record, apply=apply)))
                except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
                    result.append(dict(slot=number, status='preserved: ' + str(error)))
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['status', 'cleanup'])
    parser.add_argument('--apply', action='store_true', help='Delete only verified inactive pool-owned devices.')
    args = parser.parse_args()
    if args.apply and args.command != 'cleanup':
        parser.error('--apply is only valid with cleanup.')
    result = SimulatorPool().cleanup(apply=args.apply)
    print(json.dumps(result, indent=2))
    return int(args.apply and any(r['status'].startswith('preserved:') for r in result))


if __name__ == '__main__':
    raise SystemExit(main())
