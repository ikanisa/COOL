"""Prevent obsolete product designs from returning through gallery refreshes."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    'gallery', Path(__file__).resolve().parents[1] / 'qa/revolut_review_gallery.py')
gallery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gallery)


class FreshnessTest(unittest.TestCase):
    def test_recapture_permission_requires_exact_verified_path_and_bytes(self):
        verified = {'/current/home.png': 'current-pixels'}
        self.assertTrue(gallery.reviewed_recapture(Path('/current/home.png'), 'current-pixels', verified))
        self.assertFalse(gallery.reviewed_recapture(Path('/retired/home.png'), 'current-pixels', verified))
        self.assertFalse(gallery.reviewed_recapture(Path('/current/home.png'), 'old-pixels', verified))

    def test_only_declared_assets_affect_runtime_freshness(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'assets').mkdir()
            (root / 'pubspec.yaml').write_text('flutter:\n  assets:\n    - assets/photo.png\n')
            (root / 'assets/photo.png').write_bytes(b'current photo')
            before = gallery.runtime_fingerprint(root)
            (root / 'assets/README.md').write_text('An unbundled image-production plan')
            self.assertEqual(before, gallery.runtime_fingerprint(root))
            (root / 'assets/photo.png').write_bytes(b'new photo')
            self.assertNotEqual(before, gallery.runtime_fingerprint(root))

    def test_native_run_requires_current_unchanged_build_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)
            def record(name, digest):
                (run / name).write_text(json.dumps({'source_sha256': digest}))
            record('source-after.json', 'current')
            self.assertFalse(gallery.native_run_current(run, 'current'))
            record('source-before.json', 'old')
            self.assertFalse(gallery.native_run_current(run, 'current'))
            record('source-before.json', 'current')
            self.assertTrue(gallery.native_run_current(run, 'current'))
            self.assertFalse(gallery.native_run_current(run, 'next-edit'))
            self.assertFalse(gallery.native_run_current(run, None))

    def test_old_design_is_rejected_even_when_its_render_passed(self):
        self.assertFalse(gallery.current_capture({
            'check': 'Native fixture render passed; Historical capture; predates the current UI update'}))
        self.assertFalse(gallery.current_capture({'kind': 'Before correction'}))
        self.assertTrue(gallery.current_capture({'kind': 'Native OS keyboard'}))

    def test_runtime_or_photo_change_invalidates_capture_but_report_edit_does_not(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'lib').mkdir()
            (root / 'assets').mkdir()
            code = root / 'lib/card.dart'
            code.write_text('photo card')
            first = gallery.runtime_fingerprint(root)
            (root / 'notes.md').write_text('QA commentary')
            self.assertEqual(first, gallery.runtime_fingerprint(root))
            code.write_text('different card')
            second = gallery.runtime_fingerprint(root)
            self.assertNotEqual(first, second)
            (root / 'assets/photo.png').write_bytes(b'changed image')
            self.assertNotEqual(second, gallery.runtime_fingerprint(root))


if __name__ == '__main__':
    unittest.main()
