import importlib.util
from pathlib import Path
import tempfile
import unittest
import json

spec = importlib.util.spec_from_file_location('evidence', Path(__file__).with_name('screenshot_evidence.py'))
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class EvidenceTests(unittest.TestCase):
    def test_app_assets_and_design_references_are_exempt_but_not_screenshots(self):
        root = Path('.')
        exempt = ['CommitStandings/Assets.xcassets/AppIcon.appiconset/icon_512.png',
                  'CommitStandingsiOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png',
                  'docs/design/site-bento-desktop.png', 'site/public/avatars/a.png',
                  'video/launch/assets/avatars/a.png', 'windows/src-tauri/icons/32x32.png']
        self.assertEqual(evidence.check(root, exempt), [])
        self.assertTrue(evidence.check(root, ['docs/board.png']))
        self.assertTrue(evidence.check(root, ['CommitStandingsiOS/board.png']))

    def test_malformed_and_incomplete_provenance_reports_the_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / 'docs/screenshots/board-rank'
            folder.mkdir(parents=True)
            filename = 'docs/screenshots/board-rank/board.png'
            for manifest in [[], {'screenshots': [None]}, {'screenshots': [{'file': 'board.png', 'capture': None}]}]:
                (folder / 'manifest.json').write_text(json.dumps(manifest))
                errors = evidence.check(root, [filename])
                self.assertIn(filename, ' '.join(errors))
                self.assertIn('manifest.json', ' '.join(errors))
            (folder / 'manifest.json').write_text(json.dumps({'screenshots': [{'file': 'board.png'}]}))
            errors = ' '.join(evidence.check(root, [filename]))
            for required in ['device', 'OS/runtime', 'caption', 'sourceCommit', 'capture.fixture']:
                self.assertIn(required, errors)

    def test_new_evidence_requires_location_and_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / 'docs/screenshots/board-rank/board.png'
            image.parent.mkdir(parents=True)
            image.write_bytes(b'capture fixture')
            self.assertIn('manifest', ' '.join(evidence.check(root, ['docs/screenshots/board-rank/board.png'])))
            (image.parent / 'manifest.json').write_text(json.dumps({'device': 'iPhone Duo Simulator', 'os': 'iOS 27.1',
                'screenshots': [{'file': 'board.png', 'caption': 'Board / ranked, signed in', 'capture': {'sourceCommit': 'a'*40, 'fixture': True}}]}))
            self.assertEqual(evidence.check(root, ['docs/screenshots/board-rank/board.png']), [])
            self.assertIn('docs/screenshots', ' '.join(evidence.check(root, ['screenshots/new.png'])))
            self.assertEqual(evidence.check(root, ['CommitStandings/Assets.xcassets/AppIcon.appiconset/icon.png', 'docs/distribution.md']), [])
            self.assertEqual(evidence.check(root, []), [])  # Unchanged historical evidence is not inspected.


if __name__ == '__main__':
    unittest.main()
