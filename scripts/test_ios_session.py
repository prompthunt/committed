import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from ios_session import native_session


class NativeSessionTests(unittest.TestCase):
    def child(self, state, wait=0):
        code = ('from ios_session import native_session; '
                'from pathlib import Path; '
                f'lease=native_session(Path({str(state)!r}), wait_seconds={wait}); '
                'lease.__enter__(); print("acquired", flush=True); lease.__exit__(None,None,None)')
        return subprocess.run([sys.executable, '-c', code], cwd=Path(__file__).parent,
                              text=True, capture_output=True, timeout=5)

    def test_second_process_waits_without_entering_and_crash_releases_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory).resolve() / 'queue'
            code = ('from ios_session import native_session; from pathlib import Path; '
                    f'lease=native_session(Path({str(state)!r})); '
                    'lease.__enter__(); print("ready", flush=True); import time; time.sleep(30)')
            owner = subprocess.Popen([sys.executable, '-c', code], cwd=Path(__file__).parent,
                                     stdout=subprocess.PIPE, text=True)
            try:
                self.assertEqual(owner.stdout.readline().strip(), 'ready')
                second = self.child(state, 0.1)
                self.assertNotEqual(second.returncode, 0)
                self.assertIn('waiting', second.stdout)
                self.assertNotIn('acquired', second.stdout)
            finally:
                owner.kill()
                owner.wait(timeout=5)
                owner.stdout.close()
            self.assertEqual(self.child(state).returncode, 0)

    def test_waiting_agent_acquires_only_after_owner_finishes(self):
        import time
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory).resolve() / 'queue'
            code = ('from ios_session import native_session; from pathlib import Path; '
                    f'lease=native_session(Path({str(state)!r})); '
                    'lease.__enter__(); print("ready", flush=True); import time; time.sleep(0.3); '
                    'lease.__exit__(None,None,None)')
            owner = subprocess.Popen([sys.executable, '-c', code], cwd=Path(__file__).parent,
                                     stdout=subprocess.PIPE, text=True)
            try:
                self.assertEqual(owner.stdout.readline().strip(), 'ready')
                started = time.monotonic()
                second = self.child(state, 2)
                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertIn('waiting', second.stdout)
                self.assertIn('acquired', second.stdout)
                self.assertGreater(time.monotonic() - started, 0.2)
            finally:
                owner.wait(timeout=5)
                owner.stdout.close()

    def test_nested_calls_do_not_release_outer_session(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory).resolve() / 'queue'
            with native_session(state):
                with native_session(state):
                    pass
                self.assertNotEqual(self.child(state).returncode, 0)
            self.assertEqual(self.child(state).returncode, 0)

    def test_symlink_state_and_lock_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            actual = root / 'actual'
            actual.mkdir(mode=0o700)
            alias = root / 'alias'
            alias.symlink_to(actual, target_is_directory=True)
            with self.assertRaises(RuntimeError), native_session(alias):
                pass
            target = root / 'target'
            target.write_text('preserved')
            (actual / 'native-session.lock').symlink_to(target)
            with self.assertRaises(OSError), native_session(actual):
                pass
            self.assertEqual(target.read_text(), 'preserved')


class SharedQueueBridgeTests(unittest.TestCase):
    def test_installed_queue_is_used_and_nested_sessions_keep_owner(self):
        from unittest.mock import patch
        import ios_session
        # Load a fake installed runtime with a context manager so CI needs no
        # user installation; assert the bridge forwards identity and wait bound.
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve()
            runtime = home / '.local/share/apple-session/apple_session.py'
            runtime.parent.mkdir(parents=True)
            runtime.write_text('from contextlib import contextmanager\ncalls=[]\n'
                               '@contextmanager\ndef session(**kwargs):\n'
                               ' calls.append(kwargs)\n yield\n')
            with patch('ios_session.Path.home', return_value=home), patch.object(ios_session, '_shared_runtime', None):
                with ios_session.native_session(wait_seconds=7):
                    self.assertEqual(ios_session._shared_runtime.calls[0]['app'], 'Committed')
                    self.assertEqual(ios_session._shared_runtime.calls[0]['wait_seconds'], 7)
                    self.assertEqual(ios_session._shared_runtime.calls[0]['worktree'], Path(__file__).resolve().parents[1])
                self.assertFalse((home/'Library/Application Support/AppleDevelopment/native-session.lock').exists())

    def test_broken_installed_runtime_fails_instead_of_falling_back(self):
        from unittest.mock import patch
        import ios_session
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve()
            runtime = home / '.local/share/apple-session/apple_session.py'
            runtime.parent.mkdir(parents=True)
            runtime.write_text('raise RuntimeError("broken runtime")')
            with patch('ios_session.Path.home', return_value=home), patch.object(ios_session, '_shared_runtime', None):
                with self.assertRaises(RuntimeError), ios_session.native_session():
                    self.fail('Must not bypass the installed queue.')


class EntrypointContractTests(unittest.TestCase):
    def test_all_public_native_wrappers_hold_the_session(self):
        import ast
        root = Path(__file__).resolve().parent
        for file, function in [('ios.py', 'run_xcode'), ('ios_check.py', 'run_mac'), ('ios_check.py', 'run_ios')]:
            tree = ast.parse((root / file).read_text())
            target = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == function)
            self.assertIn('serialized_native', [ast.unparse(n) for n in target.decorator_list], function)

    def test_build_cli_rejects_tests_before_preflight_or_native_work(self):
        script = Path(__file__).with_name('ios.py')
        for action in ['test', 'test-without-building', 'build-for-testing']:
            result = subprocess.run([sys.executable, str(script), '--', action],
                                    text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 2)
            self.assertIn('scripts/ios_check.py', result.stderr)
            self.assertNotIn('Build output', result.stdout)

    def test_missing_iphone_app_fails_before_joining_the_queue(self):
        from unittest.mock import patch
        import ios_check
        with patch.object(ios_check, 'ios_scheme_present', return_value=False), \
                patch.object(ios_check, 'run_ios', side_effect=AssertionError('queued')), \
                patch('ios_session.native_session', side_effect=AssertionError('leased')):
            from io import StringIO
            with patch('sys.stderr', new=StringIO()) as stderr:
                self.assertEqual(ios_check.main(['ios']), 2)
            self.assertIn('iPhone app not in this checkout', stderr.getvalue())

    def test_iphone_scheme_detection_matches_the_shared_scheme_file(self):
        import ios_check
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertFalse(ios_check.ios_scheme_present(root))
            scheme = root / 'CommitStandings.xcodeproj/xcshareddata/xcschemes/CommitStandingsiOS.xcscheme'
            scheme.parent.mkdir(parents=True)
            scheme.write_text('<Scheme/>')
            self.assertTrue(ios_check.ios_scheme_present(root))

    def test_suite_options_are_validated_before_native_work(self):
        script = Path(__file__).with_name('ios_check.py')
        for arguments in [['mac', '--only-testing', 'CommitStandingsiOSTests/X'], ['ios', '--package']]:
            result = subprocess.run([sys.executable, str(script), *arguments],
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertNotIn('Simulator owner', result.stderr)

    def test_agent_docs_route_native_tests_through_the_wrappers(self):
        import re
        root = Path(__file__).resolve().parents[1]
        # CONTRIBUTING.md and README.md keep raw xcodebuild for external contributors.
        for name in ['AGENTS.md', 'docs/IOS_CHECKS.md', 'docs/IOS_WORKTREE_HYGIENE.md',
                     '.agents/rules/resource-cleanup.md', '.agents/skills/simulator-resource-hygiene/SKILL.md']:
            text = (root / name).read_text()
            self.assertIn('scripts/ios_check.py', text, name)
            for code in re.findall(r'```(?:sh|bash)?\n(.*?)```', text, re.S):
                self.assertNotIn('simctl create', code, name)
                self.assertNotRegex(code, r'(?s)(?:xcodebuild|scripts/ios\.py).*?\s(?:test|test-without-building)(?:\s|$)', name)


if __name__ == '__main__':
    unittest.main()
