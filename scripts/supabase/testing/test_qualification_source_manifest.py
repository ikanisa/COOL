import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from scripts.supabase.testing import qualification_source_manifest as manifest


class QualificationSourceManifestTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / 'fixture').mkdir()
        (self.root / 'fixture' / 'source.js').write_text('synthetic')
        self.roots = patch.object(manifest, 'ROOTS', ('fixture',))
        self.roots.start()
        self.addCleanup(self.roots.stop)

    def test_source_bytes_are_bound_and_drift_changes_digest(self):
        first = manifest.source_manifest(self.root)
        row = first['files'][0]
        self.assertEqual(row['path'], 'fixture/source.js')
        self.assertEqual(row['sha256'], hashlib.sha256(b'synthetic').hexdigest())
        self.assertEqual(first['sha256'], hashlib.sha256(json.dumps(first['files'], sort_keys=True, separators=(',', ':')).encode()).hexdigest())
        (self.root / 'fixture' / 'source.js').write_text('changed')
        self.assertNotEqual(manifest.source_manifest(self.root)['sha256'], first['sha256'])

    def test_symlinks_are_refused(self):
        (self.root / 'fixture' / 'alias').symlink_to(self.root / 'fixture' / 'source.js')
        with self.assertRaises(ValueError):
            manifest.source_manifest(self.root)


if __name__ == '__main__':
    unittest.main()
