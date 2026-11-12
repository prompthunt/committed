import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('appstore_submit', Path(__file__).with_name('appstore_submit.py'))
submit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(submit)


def version(string, state):
    return {'id': f'id-{string}', 'attributes': {'versionString': string, 'platform': 'IOS',
                                                 'appVersionState': state, 'appStoreState': state}}


class PlanTests(unittest.TestCase):
    """Which App Store version a new build goes to, or what's in the way."""

    def test_creates_the_version_when_every_other_one_is_live(self):
        versions = [version('1.0.2', 'READY_FOR_DISTRIBUTION'), version('1.0.1', 'READY_FOR_DISTRIBUTION')]
        self.assertEqual(submit.plan(versions, '1.0.3'), ('create', None))

    def test_reuses_an_editable_version(self):
        for state in ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'):
            with self.subTest(state=state):
                mine = version('1.0.3', state)
                self.assertEqual(submit.plan([mine, version('1.0.2', 'READY_FOR_DISTRIBUTION')], '1.0.3'),
                                 ('use', mine))

    def test_waits_while_the_previous_version_is_in_flight(self):
        for state in ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_DEVELOPER_RELEASE', 'PROCESSING_FOR_DISTRIBUTION'):
            with self.subTest(state=state):
                action, reason = submit.plan([version('1.0.2', state)], '1.0.3')
                self.assertEqual(action, 'blocked')
                self.assertIn(f'1.0.2 ({state})', reason)

    def test_never_swaps_the_build_of_a_submitted_version(self):
        action, reason = submit.plan([version('1.0.3', 'WAITING_FOR_REVIEW')], '1.0.3')
        self.assertEqual(action, 'blocked')
        self.assertIn('cancel that submission', reason)

    def test_a_released_version_needs_a_new_number(self):
        action, reason = submit.plan([version('1.0.3', 'READY_FOR_DISTRIBUTION')], '1.0.3')
        self.assertEqual(action, 'blocked')
        self.assertIn('new version', reason)


if __name__ == '__main__':
    unittest.main()
