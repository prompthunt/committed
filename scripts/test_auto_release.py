import tempfile
import unittest
from pathlib import Path

import auto_release as ar
from auto_release import Release


class CompareTests(unittest.TestCase):
    def test_newer_version_and_build_publishes(self):
        self.assertEqual(ar.compare(Release("0.1.55", 57), Release("0.1.54", 56)), "publish")

    def test_same_version_is_current(self):
        self.assertEqual(ar.compare(Release("0.1.54", 56), Release("0.1.54", 56)), "current")

    def test_older_main_never_publishes(self):
        self.assertEqual(ar.compare(Release("0.1.53", 55), Release("0.1.54", 56)), "behind")

    def test_version_bump_without_build_bump_is_refused(self):
        self.assertEqual(ar.compare(Release("0.1.55", 56), Release("0.1.54", 56)), "build-not-bumped")

    def test_versions_compare_numerically(self):
        self.assertEqual(ar.compare(Release("0.1.100", 200), Release("0.1.99", 199)), "publish")
        self.assertEqual(ar.compare(Release("0.2", 60), Release("0.1.54", 56)), "publish")

    def test_rejects_non_numeric_versions(self):
        with self.assertRaises(ValueError):
            ar.parse_version("0.1.54-beta")


class AppcastTests(unittest.TestCase):
    def test_reads_newest_item(self):
        xml = """<rss><channel>
          <item><sparkle:version>55</sparkle:version><sparkle:shortVersionString>0.1.53</sparkle:shortVersionString></item>
          <item><sparkle:version>56</sparkle:version><sparkle:shortVersionString>0.1.54</sparkle:shortVersionString></item>
        </channel></rss>"""
        self.assertEqual(ar.parse_appcast(xml), Release("0.1.54", 56))

    def test_unreadable_appcast_raises(self):
        with self.assertRaises(ValueError):
            ar.parse_appcast("<rss></rss>")


class WindowsStateTests(unittest.TestCase):
    sha = "abc123"

    def test_no_runs(self):
        self.assertEqual(ar.windows_state([], self.sha), "none")

    def test_runs_for_other_commits_do_not_count(self):
        runs = [{"headSha": "other", "status": "completed", "conclusion": "success"}]
        self.assertEqual(ar.windows_state(runs, self.sha), "none")

    def test_any_success_wins(self):
        runs = [{"headSha": self.sha, "status": "completed", "conclusion": "failure"},
                {"headSha": self.sha, "status": "completed", "conclusion": "success"}]
        self.assertEqual(ar.windows_state(runs, self.sha), "success")

    def test_in_progress(self):
        runs = [{"headSha": self.sha, "status": "in_progress", "conclusion": ""}]
        self.assertEqual(ar.windows_state(runs, self.sha), "running")

    def test_only_failures(self):
        runs = [{"headSha": self.sha, "status": "completed", "conclusion": "failure"}]
        self.assertEqual(ar.windows_state(runs, self.sha), "failed")


class SafeCheckoutTests(unittest.TestCase):
    def test_needs_the_dedicated_path_and_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            dedicated = Path(tmp) / "checkout"
            dedicated.mkdir()
            self.assertFalse(ar.safe_checkout(dedicated, dedicated))
            (dedicated / ar.MARKER).write_text("x")
            self.assertTrue(ar.safe_checkout(dedicated, dedicated))
            other = Path(tmp) / "other"
            other.mkdir()
            (other / ar.MARKER).write_text("x")
            self.assertFalse(ar.safe_checkout(other, dedicated))


if __name__ == "__main__":
    unittest.main()
