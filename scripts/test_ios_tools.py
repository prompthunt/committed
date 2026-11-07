import importlib.util
from pathlib import Path
import tempfile
import unittest
import json
import os
import time
import sys
from types import SimpleNamespace
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('ios_tools', Path(__file__).with_name('ios_tools.py'))
ios = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ios)


class PreflightTests(unittest.TestCase):
    def test_runtime_disk_floor_stops_owned_process_and_retains_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'runner.log'
            with patch.object(ios.shutil, 'disk_usage', return_value=SimpleNamespace(free=0)):
                result = ios.run_bounded([sys.executable, '-c', 'import time; time.sleep(30)'],
                                         log, timeout=10, minimum_free_gib=5)
            self.assertEqual(result, 125)
            receipt = json.loads(log.with_suffix('.json').read_text())
            self.assertTrue(receipt['capacityLimited'])
            self.assertFalse(receipt['timedOut'])
            self.assertIn('runtime floor', receipt['reason'])

    def test_runner_retains_output_and_fails_with_diagnostics_at_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'runner.log'
            result = ios.run_bounded([sys.executable, '-u', '-c', 'import time; print("runner fixture"); time.sleep(30)'],
                                     log, timeout=0.2)
            self.assertEqual(result, 124)
            self.assertIn('runner fixture', log.read_text())
            receipt = json.loads(log.with_suffix('.json').read_text())
            self.assertTrue(receipt['timedOut'])
            self.assertIn('pid', receipt)
            self.assertEqual(ios.run_bounded([sys.executable, '-c', 'raise SystemExit(7)'], log, timeout=5), 7)

    def test_only_owned_inactive_reproducible_cache_is_recommended(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            cache = root / 'build' / 'DerivedData'
            cache.mkdir(parents=True)
            (cache / 'reproducible').write_bytes(b'x' * 4096)
            probe = lambda processes: ios.preflight(root, available_bytes=0, processes=processes)
            self.assertEqual(probe([])['candidates'], [])
            with self.assertRaises(ValueError):
                ios.record_cache_owner(root, cache)
            (cache / 'reproducible').unlink()
            cache.rmdir()
            ios.record_cache_owner(root, cache)
            (cache / 'reproducible').write_bytes(b'x' * 4096)
            self.assertEqual(probe([])['candidates'], [])  # recent owned caches stay protected
            for file in cache.iterdir():
                os.utime(file, (time.time() - 8 * 86400, time.time() - 8 * 86400))
            self.assertEqual(probe([])['candidates'][0]['path'], str(cache))
            self.assertGreaterEqual(probe([])['candidates'][0]['bytes'], 4096)
            self.assertEqual(probe(['123 /Applications/Xcode.app/usr/bin/xcodebuild test'])['candidates'], [])
            marker = cache / '.committed-cache-owner.json'
            owner = json.loads(marker.read_text())
            owner['repository'] = '/another/task'
            marker.write_text(json.dumps(owner))
            self.assertEqual(probe([])['candidates'], [])
            self.assertTrue((cache / 'reproducible').exists())

    def test_capacity_rejects_below_threshold_and_passes_at_threshold(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            low = ios.preflight(root, minimum_gib=20, available_bytes=19 * 1024**3, processes=[])
            self.assertFalse(low['ok'])
            self.assertIn('20', low['message'])
            self.assertEqual(low['candidates'], [])
            self.assertTrue(ios.preflight(root, minimum_gib=20, available_bytes=20 * 1024**3, processes=[])['ok'])


if __name__ == '__main__':
    unittest.main()
