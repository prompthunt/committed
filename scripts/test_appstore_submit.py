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


class ScreenshotTests(unittest.TestCase):
    """Which screenshots a submission uploads."""

    shots = [('01-board.png', 10), ('02-live-rank.png', 20), ('03-widgets.png', 30)]

    def test_nothing_when_the_version_already_shows_them(self):
        listed = [(name, size, 'COMPLETE') for name, size in self.shots]
        self.assertEqual(submit.screenshots_to_upload(self.shots, listed), ([], False))

    def test_only_the_missing_tail_after_a_partial_upload(self):
        listed = [('01-board.png', 10, 'COMPLETE')]
        self.assertEqual(submit.screenshots_to_upload(self.shots, listed), (self.shots[1:], False))

    def test_everything_into_an_empty_set(self):
        self.assertEqual(submit.screenshots_to_upload(self.shots, []), (self.shots, False))

    def test_a_screenshot_still_processing_counts_as_there(self):
        listed = [('01-board.png', 10, 'UPLOAD_COMPLETE')]
        self.assertEqual(submit.screenshots_to_upload(self.shots, listed), (self.shots[1:], False))

    def test_replaces_a_changed_set(self):
        for listed in ([('01-board.png', 11, 'COMPLETE')],
                       [('02-live-rank.png', 20, 'COMPLETE')],
                       [(name, size, 'COMPLETE') for name, size in self.shots] + [('07-extra.png', 5, 'COMPLETE')]):
            with self.subTest(listed=listed):
                self.assertEqual(submit.screenshots_to_upload(self.shots, listed), (self.shots, True))


if __name__ == '__main__':
    unittest.main()
