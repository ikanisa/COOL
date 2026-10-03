import importlib.util
import hashlib
import json
import os
import pathlib
import plistlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('prepare', ROOT / 'tools/collect-notification-mcp/scripts/prepare_unattended_launchd.py')
PREPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARE)


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='collect-launchd-')
        self.parent = pathlib.Path(self.temporary.name).resolve()
        self.source = self.parent / 'source with spaces'
        (self.source / 'src').mkdir(parents=True)
        (self.source / 'node_modules/dependency').mkdir(parents=True)
        (self.source / 'src/unattended_host_tick.ts').write_text('// synthetic gated entrypoint\n')
        (self.source / 'node_modules/dependency/runtime.js').write_text('// synthetic dependency\n')
        (self.source / 'package.json').write_text('{}\n')
        (self.source / 'pnpm-lock.yaml').write_text('{}\n')
        self.node = self.parent / 'synthetic node'
        self.marker = self.parent / 'invoked'
        self.node.write_text('#!/bin/sh\nprintf invoked > ' + str(self.marker) + '\n')
        self.node.chmod(0o700)
        self.helper = self.parent / 'synthetic helper'
        self.helper.write_text('#!/bin/sh\nexit 70\n')
        self.helper.chmod(0o700)
        self.journal = self.parent / 'journal'
        self.journal.mkdir(mode=0o700)
        self.profile = self.parent / 'profile.json'
        self.profile.write_text(json.dumps({'contract_version': 2, 'scope': 'rw_receipt_operations',
            'identity': {'principalId': '99850000-0000-4000-8000-000000000001',
                         'keySha256': 'a' * 64, 'expiresAt': '2060-01-01T00:00:00.000Z'},
            'helper_path': str(self.helper), 'helper_sha256': hashlib.sha256(self.helper.read_bytes()).hexdigest(),
            'journal_directory': str(self.journal)}, separators=(',', ':')) + '\n')
        self.profile.chmod(0o600)
        self.output = self.parent / 'prepared'

    def tearDown(self):
        self.temporary.cleanup()

    def prepare(self, **kwargs):
        return PREPARE.prepare(str(self.profile), str(self.node),
                               str(self.source), str(self.output), **kwargs)

    def test_private_hash_bound_job_is_prepared_without_start_or_remote_profile_proof(self):
        result = self.prepare()
        self.assertFalse(self.marker.exists())
        self.assertFalse(result['installed'])
        self.assertFalse(result['started'])
        self.assertFalse(result['profile_verified'])
        self.assertEqual(result['profile_sha256'], hashlib.sha256(self.profile.read_bytes()).hexdigest())
        self.assertEqual(result['helper_sha256'], hashlib.sha256(self.helper.read_bytes()).hexdigest())
        self.assertIn('unattended_host_tick.ts', (self.output / 'tick.sh').read_text())
        self.assertIn('--deployment', (self.output / 'tick.sh').read_text())
        job = plistlib.loads((self.output / 'com.ikanisa.collect.receipt-operations.plist').read_bytes())
        self.assertEqual(job['ProgramArguments'], ['/bin/sh', str(self.output / 'tick.sh')])
        self.assertFalse(job['KeepAlive'])
        self.assertFalse(job['RunAtLoad'])
        self.assertEqual(job['Umask'], 63)
        self.assertEqual(job['StandardOutPath'], '/dev/null')
        self.assertEqual(job['StandardErrorPath'], '/dev/null')
        self.assertTrue((self.output / 'diagnostics').is_dir())
        for file in self.output.iterdir():
            self.assertEqual(file.stat().st_mode & 0o777, 0o700 if file.is_dir() else 0o600)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)

    def test_runtime_or_dependency_drift_prevents_actual_wrapper_invocation(self):
        self.prepare()
        (self.source / 'node_modules/dependency/runtime.js').write_text('// changed\n')
        process = subprocess.run(['/bin/sh', str(self.output / 'tick.sh')], capture_output=True)
        self.assertEqual(process.returncode, 78)
        self.assertFalse(self.marker.exists())
        self.assertEqual(process.stdout, b'')
        self.assertEqual(process.stderr, b'')

    def test_unchanged_runtime_executes_exact_quoted_path(self):
        self.prepare()
        process = subprocess.run(['/bin/sh', str(self.output / 'tick.sh')], capture_output=True)
        self.assertEqual(process.returncode, 0)
        self.assertEqual(self.marker.read_text(), 'invoked')

    def test_existing_output_is_never_overwritten(self):
        self.prepare()
        original = (self.output / 'PREPARATION.json').read_bytes()
        with self.assertRaisesRegex(ValueError, 'ALREADY_EXISTS'):
            self.prepare()
        self.assertEqual((self.output / 'PREPARATION.json').read_bytes(), original)

    def test_runtime_link_is_refused_before_publication(self):
        target = self.source / 'node_modules/dependency/runtime.js'
        linked = self.parent / 'linked-runtime.js'
        target.rename(linked)
        target.symlink_to(linked)
        with self.assertRaisesRegex(ValueError, 'SOURCE_LINK_REFUSED'):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_ambient_runtime_options_are_not_inherited(self):
        self.node.write_text('#!/bin/sh\nprintf "%s" "${NODE_OPTIONS-unset}" > ' + str(self.marker) + '\n')
        self.prepare()
        environment = dict(os.environ, NODE_OPTIONS='PRIVATE_OPTIONS_CANARY',
                           PERL5OPT='-MNonexistentInjectionModule')
        process = subprocess.run(['/bin/sh', str(self.output / 'tick.sh')],
                                 capture_output=True, env=environment)
        self.assertEqual(process.returncode, 0)
        self.assertEqual(self.marker.read_text(), 'unset')

    def test_invalid_limits_refuse_before_output_creation(self):
        for values in [{'interval_seconds': 59}, {'max_events': 11}]:
            with self.assertRaisesRegex(ValueError, 'LIMIT_INVALID'):
                self.prepare(**values)
        self.assertFalse(self.output.exists())

    def test_profile_or_helper_drift_blocks_wrapper_before_node(self):
        for target in [self.profile, self.helper]:
            with self.subTest(target=target.name):
                if self.output.exists():
                    import shutil
                    shutil.rmtree(self.output)
                original = target.read_bytes()
                self.prepare()
                target.write_bytes(original + b' ')
                process = subprocess.run(['/bin/sh', str(self.output / 'tick.sh')], capture_output=True)
                self.assertEqual(process.returncode, 78)
                self.assertFalse(self.marker.exists())
                target.write_bytes(original)

    def test_nonprivate_profile_is_refused(self):
        self.profile.chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'PROFILE_NOT_PRIVATE'):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_wrong_helper_hash_is_refused_without_executing_helper(self):
        self.helper.write_text('#!/bin/sh\nexit 99\n')
        with self.assertRaisesRegex(ValueError, 'HELPER_UNVERIFIED'):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_in_tree_pnpm_link_is_bound_and_later_substitution_blocks_node(self):
        link = self.source / 'node_modules/dependency-link'
        link.symlink_to('dependency', target_is_directory=True)
        result = self.prepare()
        self.assertEqual(result['dependency_links'][str(link)], 'dependency')
        link.unlink()
        link.symlink_to('../outside', target_is_directory=True)
        process = subprocess.run(['/bin/sh', str(self.output / 'tick.sh')], capture_output=True)
        self.assertEqual(process.returncode, 78)
        self.assertFalse(self.marker.exists())

    def test_outside_tree_dependency_link_is_refused(self):
        (self.source / 'node_modules/outside-link').symlink_to(self.parent, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'SOURCE_LINK_REFUSED'):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_continuous_retention_pins_policy_and_both_source_modules_without_starting(self):
        for name in ['unattended_retained.ts', 'unattended_retention.ts']:
            (self.source / 'src' / name).write_text('// synthetic retained module binding\n')
        result = self.prepare(retention_policy_sha256='b' * 64)
        self.assertEqual(result['retention_policy_sha256'], 'b' * 64)
        manifest = json.loads((self.output / 'PREPARATION.json').read_text())
        self.assertEqual(manifest['retention_policy_sha256'], 'b' * 64)
        for name in ['unattended_retained.ts', 'unattended_retention.ts']:
            self.assertIn(str(self.source / 'src' / name), manifest['runtime_inputs'])
        self.assertFalse(self.marker.exists())
        self.assertFalse(result['installed'])
        self.assertFalse(result['started'])

    def test_continuous_retention_requires_both_modules_before_any_output(self):
        with self.assertRaisesRegex(ValueError, 'SCHEDULER_RETENTION_SOURCE_UNAVAILABLE'):
            self.prepare(retention_policy_sha256='b' * 64)
        self.assertFalse(self.output.exists())

    def test_malformed_retention_policy_is_rejected_before_any_output(self):
        for value in ['B' * 64, 'b' * 63, 'PRIVATE_POLICY_CANARY']:
            with self.assertRaisesRegex(ValueError, 'RETENTION_POLICY_INVALID'):
                self.prepare(retention_policy_sha256=value)
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
