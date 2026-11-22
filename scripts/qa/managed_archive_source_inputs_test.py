"""Exercise historical Git, local dependency and external source custody without a runtime."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import managed_archive_source_inputs as custody


class ManagedArchiveSourceInputsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.git('init', '--quiet')
        self.tracked = 'scripts/supabase/fixture.mjs'
        self.source = self.repo / self.tracked
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(b'original fixture\n')
        self.modules = self.root / 'modules'
        self.dependency = self.modules / 'pg/index.js'
        self.dependency.parent.mkdir(parents=True)
        self.dependency.write_bytes(b'original dependency\n')
        self.log = self.root / 'recovered.log'
        self.log.write_bytes(b'original external log\n')
        self.original_log = '/archive-fixture/external.log'
        self.pins = self.repo / custody.MANIFEST
        self.pins.parent.mkdir(parents=True)
        entries = [(custody.ORIGINAL / self.tracked, self.source), (custody.MODULES / 'pg/index.js', self.dependency),
                   (self.original_log, self.log)]
        manifest = {'format': 'collect.managed-archive-operator.source-pins.v2',
                    'inputs': [{'path': str(name), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                               for name, path in sorted(entries, key=lambda entry: str(entry[0]))]}
        self.pins.write_text(json.dumps(manifest, indent=2) + '\n')
        self.patch = patch.object(custody, 'MANIFEST_SHA256', hashlib.sha256(self.pins.read_bytes()).hexdigest())
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.commit()
        self.original_revision = self.git('rev-parse', 'HEAD').strip()

    def git(self, *arguments):
        return subprocess.check_output(
            ['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', *arguments],
            cwd=self.repo, text=True,
        )

    def commit(self):
        self.git('add', '--all')
        self.git('commit', '--quiet', '-m', 'synthetic source custody')

    def check(self, revision=None, replacements=None):
        return custody.inventory(self.repo, revision or self.original_revision, self.modules,
                                 replacements if replacements is not None else [(self.original_log, self.log)], True)

    def test_uses_git_bytes_and_relocated_exact_files_without_modifying_originals(self):
        self.source.write_bytes(b'new checkout bytes\n')
        report = self.check()
        self.assertEqual((report['status'], report['verified_inputs'], report['input_count']), ('verified', 3, 3))
        self.assertEqual(report['commit'], self.original_revision)
        self.assertEqual(report['scope'], 'source_bytes_only')
        self.assertEqual({row['kind'] for row in report['inputs']}, {'git', 'npm', 'external'})
        self.assertEqual(self.source.read_bytes(), b'new checkout bytes\n')
        self.assertEqual(report['unresolved'], [])

    def test_reports_missing_external_and_changed_dependency_independently(self):
        self.dependency.write_bytes(b'corrupt dependency\n')
        report = self.check(replacements=[])
        self.assertEqual((report['status'], report['verified_inputs']), ('incomplete', 1))
        self.assertEqual({(row['kind'], row['status']) for row in report['unresolved']},
                         {('external', 'missing'), ('npm', 'digest_mismatch')})
        self.log.write_bytes(b'replacement log\n')
        self.assertEqual(self.check()['counts']['external'], {'digest_mismatch': 1})

    def test_wrong_git_revision_and_nonregular_substitutes_remain_incomplete(self):
        self.source.write_bytes(b'different committed fixture\n')
        self.commit()
        self.assertEqual(self.check('HEAD')['counts']['git'], {'digest_mismatch': 1})
        self.source.unlink()
        self.commit()
        self.assertEqual(self.check('HEAD')['counts']['git'], {'missing': 1})
        self.source.symlink_to(self.log)
        self.commit()
        self.assertEqual(self.check('HEAD')['counts']['git'], {'invalid_file': 1})
        self.dependency.unlink()
        self.dependency.symlink_to(self.log)
        self.assertEqual(self.check()['counts']['npm'], {'not_physical': 1})

    def test_rejects_manifest_drift_and_remaps_outside_its_external_inputs(self):
        self.pins.write_text('{}\n')
        self.commit()
        with self.assertRaisesRegex(ValueError, 'manifest digest'):
            self.check('HEAD')
        for replacements in [[(str(custody.ORIGINAL / self.tracked), self.source)],
                             [(self.original_log, self.log), (self.original_log, self.log)]]:
            with self.subTest(replacements=replacements), self.assertRaisesRegex(ValueError, 'unique external'):
                self.check(replacements=replacements)


if __name__ == '__main__':
    unittest.main()
