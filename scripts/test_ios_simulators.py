import copy
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import uuid

from ios_simulators import SimulatorPool, OWNER, PREFIX
from ios_tools import termination_cleanup


RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-27-1'
TYPE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-Duo'


class Devices:
    def __init__(self):
        self.inventory = {}
        self.deleted = []
        self.stopped = []
        self.busy = set()
        self.fail_delete = False

    def devices(self):
        return copy.deepcopy(self.inventory)

    def create(self, record):
        udid = str(uuid.uuid4()).upper()
        self.inventory[udid] = dict(udid=udid, name=record['name'], runtime=record['runtime'],
                                    deviceTypeIdentifier=record['deviceTypeIdentifier'], state='Shutdown')
        return udid

    def shutdown(self, udid):
        self.stopped.append(udid)
        self.inventory[udid]['state'] = 'Shutdown'

    def delete(self, udid):
        if self.fail_delete:
            raise RuntimeError('simctl deletion failed')
        self.deleted.append(udid)
        self.inventory.pop(udid)

    def inactive(self, udid):
        return udid not in self.busy


class PoolTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.state = Path(self.temporary.name).resolve() / 'state'
        self.devices = Devices()
        self.pool = SimulatorPool(self.state, self.devices)
        self.capacity = patch('ios_simulators.shutil.disk_usage', return_value=SimpleNamespace(free=100 * 1024**3))
        self.capacity.start()
        self.addCleanup(self.capacity.stop)

    def lease(self, pool=None, timeout=0):
        return (pool or self.pool).lease(RUNTIME, TYPE, '/a/worktree', timeout=timeout)

    def orphan(self, state='Shutdown', complete=True):
        self.pool._prepare()
        token = uuid.uuid4().hex
        record = dict(owner=OWNER, token=token, name=PREFIX + token,
                      runtime=RUNTIME, deviceTypeIdentifier=TYPE, udid=None)
        udid = self.devices.create(record)
        self.devices.inventory[udid]['state'] = state
        if complete:
            record['udid'] = udid
        self.pool._write(self.state / '0.json', record)
        return udid

    def test_completion_deletes_only_the_owned_device_and_retains_diagnostics(self):
        personal = self.devices.create(dict(name='iPhone Duo (persistent development device)', runtime=RUNTIME, deviceTypeIdentifier=TYPE))
        with self.lease() as receipt:
            udid = receipt['udid']
            self.devices.inventory[udid]['state'] = 'Booted'
            self.assertTrue((self.state / '0.json').exists())
        self.assertEqual(self.devices.deleted, [udid])
        self.assertIn(personal, self.devices.inventory)
        self.assertEqual(receipt['cleanupStatus'], 'deleted')
        self.assertFalse((self.state / '0.json').exists())

    def test_second_worktree_must_wait_until_the_only_device_is_released(self):
        other = SimulatorPool(self.state, self.devices)
        with self.lease() as first:
            with self.assertRaisesRegex(RuntimeError, 'wait for its owner'):
                with self.lease(other):
                    self.fail('A second test device must not be created')
            self.assertEqual(list(self.devices.inventory), [first['udid']])
            self.assertTrue(all('active lease' in r['status'] for r in other.cleanup(apply=True)))
        with self.lease(other):
            self.assertEqual(len(self.devices.inventory), 1)
        self.assertFalse(self.devices.inventory)

    def test_abandoned_shutdown_device_is_recovered_before_creating_its_replacement(self):
        old = self.orphan()
        with self.lease() as record:
            self.assertIn(old, self.devices.deleted)
            self.assertEqual(list(self.devices.inventory), [record['udid']])
        self.assertFalse(self.devices.inventory)

    def test_booted_abandoned_device_blocks_replacement(self):
        old = self.orphan(state='Booted')
        with self.assertRaisesRegex(RuntimeError, 'booted'):
            with self.lease():
                self.fail('An abandoned device still consumes the only capacity')
        self.assertEqual(list(self.devices.inventory), [old])

    def test_receipts_use_committed_identity_and_state_outside_checkouts(self):
        import ios_simulators
        self.assertEqual(OWNER, 'committed-ios-check/v1')
        self.assertTrue(str(ios_simulators.STATE).endswith('Library/Application Support/Committed/agent-simulators'))
        with self.lease() as record:
            self.assertTrue(record['name'].startswith('CommittedAgent-'))

    def test_exception_and_cancellation_release_the_device(self):
        for error in [RuntimeError('test failed'), KeyboardInterrupt()]:
            with self.assertRaises(type(error)):
                with self.lease():
                    raise error
            self.assertFalse(self.devices.inventory)

    def test_crash_between_creation_and_receipt_update_is_recoverable(self):
        old = self.orphan(complete=False)
        with self.lease() as record:
            self.assertNotEqual(record['udid'], old)
            self.assertIn(old, self.devices.deleted)

    def test_booted_or_in_use_abandoned_devices_are_preserved(self):
        old = self.orphan(state='Booted')
        result = self.pool.cleanup(apply=True)
        self.assertIn('booted', result[0]['status'])
        self.assertIn(old, self.devices.inventory)
        self.devices.inventory[old]['state'] = 'Shutdown'
        self.devices.busy.add(old)
        self.assertIn('inactivity', self.pool.cleanup(apply=True)[0]['status'])
        self.assertTrue((self.state / '0.json').exists())
        self.assertEqual(self.devices.deleted, [])

    def test_unknown_or_changed_identity_is_never_deleted(self):
        old = self.orphan()
        self.devices.inventory[old]['name'] = 'User repurposed this device'
        self.assertIn('identity changed', self.pool.cleanup(apply=True)[0]['status'])
        self.assertIn(old, self.devices.inventory)

    def test_dry_run_preserves_device_and_receipt_then_apply_verifies_removal(self):
        old = self.orphan()
        self.assertIn('eligible', self.pool.cleanup()[0]['status'])
        self.assertIn(old, self.devices.inventory)
        self.assertTrue((self.state / '0.json').exists())
        self.assertEqual(self.pool.cleanup(apply=True)[0]['status'], 'deleted')
        self.assertNotIn(old, self.devices.inventory)

    def test_failed_delete_retains_receipt_and_blocks_replacement(self):
        old = self.orphan()
        self.devices.fail_delete = True
        self.assertIn('deletion failed', self.pool.cleanup(apply=True)[0]['status'])
        self.assertTrue((self.state / '0.json').exists())
        self.assertIn(old, self.devices.inventory)
        with self.assertRaisesRegex(RuntimeError, 'deletion failed'):
            with self.lease():
                self.fail('A failed cleanup must block replacement, not create another device')
        self.assertEqual(list(self.devices.inventory), [old])
        self.devices.fail_delete = False
        with self.lease():
            self.assertEqual(len(self.devices.inventory), 1)

    def test_low_capacity_prevents_creation(self):
        with patch('ios_simulators.shutil.disk_usage', return_value=SimpleNamespace(free=0)):
            with self.assertRaisesRegex(RuntimeError, 'GiB free'):
                with self.lease():
                    self.fail('No device should be provisioned')
        self.assertFalse(self.devices.inventory)

    def test_symlinked_state_or_receipt_is_rejected_without_touching_target(self):
        real = self.state.parent / 'real'
        real.mkdir(mode=0o700)
        self.state.symlink_to(real, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'symlinks'):
            with self.lease():
                self.fail('Symlinked state must fail closed')
        self.state.unlink()
        self.pool._prepare()
        target = self.state.parent / 'personal.json'
        target.write_text('personal data')
        (self.state / '0.json').symlink_to(target)
        self.pool.cleanup(apply=True)
        self.assertEqual(target.read_text(), 'personal data')

    def test_corrupt_receipt_is_preserved(self):
        self.pool._prepare()
        receipt = self.state / '0.json'
        receipt.write_text('{invalid')
        self.assertIn('preserved', self.pool.cleanup(apply=True)[0]['status'])
        self.assertTrue(receipt.exists())
        self.assertFalse(self.devices.deleted)

    def test_unrecognized_owner_is_not_adopted(self):
        old = self.orphan()
        path = self.state / '0.json'
        record = json.loads(path.read_text())
        record['owner'] = 'another project'
        path.write_text(json.dumps(record))
        self.assertIn('Unknown simulator ownership', self.pool.cleanup(apply=True)[0]['status'])
        self.assertIn(old, self.devices.inventory)
        self.assertTrue(path.exists())

    def test_invalid_capacity_cannot_bypass_disk_check(self):
        for minimum in [0, -1, float('nan'), float('inf')]:
            with self.assertRaises(ValueError):
                SimulatorPool(self.state, self.devices, minimum_gib=minimum)

    def test_sigterm_runs_finally_and_restores_previous_signal_handler(self):
        previous = signal.getsignal(signal.SIGTERM)
        with self.assertRaises(KeyboardInterrupt):
            with termination_cleanup():
                with self.lease():
                    os.kill(os.getpid(), signal.SIGTERM)
        self.assertFalse(self.devices.inventory)
        self.assertEqual(signal.getsignal(signal.SIGTERM), previous)

    def test_cli_status_has_no_side_effects_for_a_new_registry(self):
        self.assertEqual(self.pool.cleanup(), [])
        self.assertFalse(self.state.exists())

    def test_sigterm_of_runner_process_stops_its_child(self):
        log = self.state.parent / 'cancel.log'
        code = ('from ios_tools import run_bounded, termination_cleanup\n'
                'import sys\n'
                'try:\n'
                '    with termination_cleanup():\n'
                f'        run_bounded([sys.executable, "-c", "import time; time.sleep(30)"], {str(log)!r})\n'
                'except KeyboardInterrupt:\n'
                '    sys.exit(130)\n')
        process = subprocess.Popen([sys.executable, '-c', code], cwd=Path(__file__).parent,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 10
            while not log.with_suffix('.json').exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(log.with_suffix('.json').exists())
            child = json.loads(log.with_suffix('.json').read_text())['pid']
            process.send_signal(signal.SIGTERM)
            _, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 130, stderr)
            with self.assertRaises(ProcessLookupError):
                os.kill(child, 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == '__main__':
    unittest.main()
