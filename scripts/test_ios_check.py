import importlib.util
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
spec = importlib.util.spec_from_file_location('ios_check', Path(__file__).with_name('ios_check.py'))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class CapacityFloorTests(unittest.TestCase):
    def test_iphone_runs_keep_the_20_gib_start_floor(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(check.minimum_gib(), 20)

    def test_mac_gate_has_its_own_lower_start_floor(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(check.mac_minimum_gib(), 8)
            self.assertLess(check.mac_minimum_gib(), check.minimum_gib())

    def test_each_floor_is_overridden_only_by_its_own_variable(self):
        with patch.dict(os.environ, {'COMMITTED_MAC_MIN_FREE_GIB': '12'}, clear=True):
            self.assertEqual(check.mac_minimum_gib(), 12)
            self.assertEqual(check.minimum_gib(), 20)

    def test_mac_gate_passes_its_floor_to_the_build_preflight(self):
        calls = []
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(check, 'run_xcode', side_effect=lambda *a, **k: calls.append(k) or 1), \
                patch.object(check, 'new_run_directory', return_value=Path('/tmp')), \
                patch.object(check.os, 'chdir'):
            check.run_mac.__wrapped__()
        self.assertEqual(calls[0]['minimum_gib'], 8)


if __name__ == '__main__':
    unittest.main()
