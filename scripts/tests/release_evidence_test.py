#!/usr/bin/env python3
"""Release record binding fixtures; no hosted execution or release approval."""
import importlib.util
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('release_evidence', Path(__file__).resolve().parents[1] / 'qa/release_evidence.py')
evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evidence)

class LegacyAcceptanceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.record = self.root / 'acceptance.json'
        self.proof = self.root / 'reviewed-proof.txt'
        self.proof.write_text('synthetic reviewed record; no live proof')
        self.sources = {'deploy/platform-api/src/index.js': 'a' * 64}
        self.patcher = patch.object(evidence, 'source_manifest', return_value=self.sources)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        self.value = {'backend': 'cloudflare', 'status': 'pass',
            'expires_at': (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(),
            'source_manifest_sha256': evidence.manifest_sha(self.sources),
            'checks': {name: {'status': 'pass', 'evidence': {'path': self.proof.name,
                       'sha256': evidence.sha(self.proof)}} for name in evidence.REQUIRED_HOSTED_CHECKS}}

    def result(self):
        self.record.write_text(json.dumps(self.value))
        return evidence.hosted_acceptance(self.root, self.record)

    def test_missing_record_blocks(self):
        self.assertEqual(evidence.hosted_acceptance(self.root, self.record)['decision'], 'NO-GO')

    def test_local_pass_cannot_replace_hosted_checks(self):
        self.value['checks'] = {'platform_tests': {'status': 'pass'}}
        self.assertEqual(set(self.result()['blocker_keys']), set(evidence.REQUIRED_HOSTED_CHECKS))

    def test_legacy_hashed_reviewed_record_is_structurally_accepted(self):
        self.assertEqual(self.result()['status'], 'pass')

    def test_source_drift_and_expiry_block(self):
        self.value['source_manifest_sha256'] = 'b' * 64
        self.value['expires_at'] = (datetime.now(timezone.utc) - timedelta(seconds=1)).isoformat()
        self.assertIn('hosted_acceptance_source_changed', self.result()['blocker_keys'])
        self.assertIn('hosted_acceptance_expired', self.result()['blocker_keys'])

    def test_changed_or_missing_reviewed_evidence_blocks(self):
        self.proof.write_text('changed bytes')
        self.assertEqual(set(self.result()['blocker_keys']), set(evidence.REQUIRED_HOSTED_CHECKS))
        self.proof.unlink()
        self.assertEqual(self.result()['decision'], 'NO-GO')

    def test_fixture_and_invalid_json_block(self):
        self.value['fixture'] = True
        self.assertIn('hosted_acceptance_not_passed', self.result()['blocker_keys'])
        self.record.write_text('{')
        self.assertIn('hosted_acceptance_missing_or_invalid', evidence.hosted_acceptance(self.root, self.record)['blocker_keys'])

class CurrentReleaseTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.sources = {'supabase/functions/fixture.ts': 'a' * 64, 'tools/fixture.mjs': 'b' * 64}

    def summary(self, backend='supabase'):
        commands = {}
        for name, _ in evidence.REQUIRED_COMMANDS:
            log = self.root / (name + '.txt')
            log.write_text('synthetic local pass; not hosted evidence')
            commands[name] = {'file': log.name, 'sha256': evidence.sha(log), 'status': 'pass', 'exit_code': 0}
        value = {'backend': backend, 'status': 'pass', 'fixture': False,
                 'source_sha256': self.sources, 'commands': commands, 'release_status': {'decision': 'GO'}}
        (self.root / 'summary.json').write_text(json.dumps(value))
        return value

    def checked_index(self):
        with patch.object(evidence, 'source_manifest', return_value=self.sources):
            return evidence.index(self.root)

    def test_source_identity_includes_current_backend_and_consumer_roots_and_drift(self):
        names = ['supabase/functions/fixture.ts', 'supabase/migrations/20261021000001_fixture.sql',
                 'tools/operator/fixture.mjs', 'tools/operator/node_modules/ignored.js', 'unrelated.txt']
        for name in names:
            path = self.root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('fixture')
        with patch.object(evidence.subprocess, 'check_output', return_value=('\0'.join(names) + '\0').encode()):
            before = evidence.source_manifest(self.root)
            self.assertEqual(set(before), set(names[:3]))
            (self.root / names[0]).write_text('changed backend')
            self.assertNotEqual(before, evidence.source_manifest(self.root))
            (self.root / names[2]).write_text('changed consumer')
            self.assertNotEqual(before[names[2]], evidence.source_manifest(self.root)[names[2]])

    def test_new_current_roots_exclude_private_config_and_generated_outputs(self):
        private = ['supabase/.temp/cli-latest', 'supabase/.temp/linked-project.json',
                   'supabase/.env', 'tools/operator/.env.production',
                   'tools/operator/credentials.json', 'supabase/service-account.json',
                   'supabase/key.properties', 'tools/local.properties',
                   'tools/google-services.json', 'tools/GoogleService-Info.plist',
                   'tools/GoogleService-Info-production.plist', 'tools/Generated.xcconfig',
                   'tools/MapsKeys.xcconfig', 'tools/flutter_export_environment.sh',
                   'tools/.flutter-plugins-dependencies', 'tools/upload.keystore',
                   'tools/key.pem', 'tools/client.p12', 'tools/device.mobileprovision']
        generated = ['supabase/functions/node_modules/x.js', 'tools/coverage/index.html',
                     'supabase/functions/.cache/result.json', 'tools/output/result.json',
                     'tools/failures/result.json', 'tools/build_stale_20261021/a.js',
                     'tools/DerivedData/output', 'tools/App.dSYM/Contents/Info.plist',
                     'tools/.pub-cache/cache', 'tools/.kotlin/cache', 'tools/.swiftpm/cache',
                     'tools/.build/cache', 'tools/.git/config', 'tools/result.log',
                     'supabase/schema.dump', 'tools/archive.zip', 'tools/result.sql.gz',
                     'tools/app.apk', 'tools/compiled.pyc']
        keep = ['supabase/config.toml', 'supabase/functions/auth/index.ts',
                'supabase/functions/_shared/runtime.js', 'supabase/functions/deno.json',
                'supabase/functions/deno.lock', 'supabase/migrations/20261021000001_auth.sql',
                'supabase/functions/test/secret-token.test.ts', 'tools/auth/token.mjs',
                'tools/operator/test/credentials.test.mjs', 'tools/operator/package.json',
                'tools/operator/package-lock.json', 'tools/operator/.env.example',
                'tools/operator/source-map.json']
        names = private + generated + keep
        for name in names:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('inert fixture source; no credentials')
        with patch.object(evidence.subprocess, 'check_output', return_value=('\0'.join(names) + '\0').encode()):
            original = evidence.source_manifest(self.root)
            self.assertEqual(set(original), set(keep))
            for name in private + generated:
                (self.root / name).write_text('changed excluded fixture')
            self.assertEqual(original, evidence.source_manifest(self.root))
            for name in keep:
                with self.subTest(name=name):
                    saved = (self.root / name).read_text()
                    (self.root / name).write_text('changed legitimate source')
                    self.assertNotEqual(original[name], evidence.source_manifest(self.root)[name])
                    (self.root / name).write_text(saved)

    def test_new_root_exclusions_do_not_change_existing_root_identity(self):
        names = ['deploy/fixture/.temp/current.json', 'test/fixture/credentials.json']
        for name in names:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('inert existing-root fixture')
        with patch.object(evidence.subprocess, 'check_output', return_value=('\0'.join(names) + '\0').encode()):
            self.assertEqual(set(evidence.source_manifest(self.root)), set(names))

    def test_current_source_symlinks_and_external_ancestors_still_refused(self):
        workspace = self.root / 'workspace'
        (workspace / 'supabase/functions').mkdir(parents=True)
        source = workspace / 'supabase/functions/actual.ts'
        source.write_text('inert legitimate source')
        direct = workspace / 'supabase/functions/link.ts'
        direct.symlink_to(source)
        outside = self.root / 'external'
        outside.mkdir()
        (outside / 'runtime.mjs').write_text('inert external source')
        (workspace / 'tools').symlink_to(outside, target_is_directory=True)
        for name in ['supabase/functions/link.ts', 'tools/runtime.mjs']:
            with self.subTest(name=name), \
                    patch.object(evidence.subprocess, 'check_output', return_value=(name + '\0').encode()):
                with self.assertRaisesRegex(ValueError, 'non-regular or external path'):
                    evidence.source_manifest(workspace)

    def test_current_command_list_never_executes_legacy_inventory_or_backend(self):
        commands = dict(evidence.REQUIRED_COMMANDS)
        self.assertNotIn('platform_inventory', commands)
        self.assertNotIn('platform_tests', commands)
        self.assertEqual(commands['supabase_tests'], ['make', 'supabase-test'])
        self.assertEqual(commands['hosted_acceptance'],
                         ['python3', 'scripts/qa/release_evidence.py', 'current-platform', '--json'])
        self.assertNotIn('cloudflare-platform-test', str(commands))
        self.assertNotIn('deploy/platform-api', str(commands))
        self.assertNotIn('supabase-inventory', str(commands))

    def test_current_hosted_contract_is_pending_even_if_all_local_logs_claim_success(self):
        self.summary()
        result = self.checked_index()
        self.assertEqual(result['backend'], 'supabase')
        self.assertEqual(result['decision'], 'NO-GO')
        self.assertEqual(result['blocker_keys'], ['current_supabase_hosted_acceptance_pending'])
        self.assertEqual(set(evidence.current_hosted_acceptance()['required_checks']), set(evidence.REQUIRED_HOSTED_CHECKS))

    def test_cloudflare_bundle_or_relabelled_record_cannot_approve_current_release(self):
        self.summary('cloudflare')
        self.assertIn('current_backend_not_supabase', self.checked_index()['blocker_keys'])
        self.summary('supabase')
        self.assertIn('current_supabase_hosted_acceptance_pending', self.checked_index()['blocker_keys'])
        with patch.object(evidence, 'read_json', side_effect=AssertionError('No contract may be read as approved')):
            self.assertEqual(evidence.current_hosted_acceptance()['decision'], 'NO-GO')

    def test_current_index_still_rejects_source_fixture_log_and_command_drift(self):
        for mutation, expected in [('source', 'source_changed_or_fixture'), ('fixture', 'source_changed_or_fixture'),
                                   ('log', 'supabase_tests_evidence_missing_or_changed'), ('command', 'supabase_tests')]:
            value = self.summary()
            if mutation == 'source': value['source_sha256'] = {}
            elif mutation == 'fixture': value['fixture'] = True
            elif mutation == 'log': (self.root / value['commands']['supabase_tests']['file']).write_text('changed')
            else: value['commands']['supabase_tests']['status'] = 'fail'
            (self.root / 'summary.json').write_text(json.dumps(value))
            self.assertIn(expected, self.checked_index()['blocker_keys'])

    def test_current_run_collects_only_declared_current_commands_with_no_real_execution(self):
        from types import SimpleNamespace
        output = self.root / 'new-bundle'
        calls = []
        def fake_run(command, **kwargs):
            calls.append(command)
            if kwargs.get('capture_output'):
                return SimpleNamespace(returncode=0, stdout='{"decision":"GO"}')
            kwargs['stdout'].write(b'synthetic command result')
            return SimpleNamespace(returncode=0)
        with patch.object(evidence, 'source_manifest', return_value=self.sources), \
                patch.object(evidence.subprocess, 'run', side_effect=fake_run):
            result = evidence.run(output)
        self.assertEqual(calls[:-1], [command for _, command in evidence.REQUIRED_COMMANDS])
        self.assertEqual(result['decision'], 'NO-GO')
        summary = json.loads((output / 'summary.json').read_text())
        self.assertEqual(summary['backend'], 'supabase')
        self.assertEqual(summary['decision'], 'NO-GO')
        self.assertIn('current_supabase_hosted_acceptance_pending', summary['blocker_keys'])
        self.assertNotIn('cloudflare-platform-test', str(calls))

    def test_legacy_reader_is_explicitly_historical_and_cannot_set_current_approval(self):
        with patch.object(evidence, 'read_json', side_effect=ValueError):
            result = evidence.hosted_acceptance(self.root)
        self.assertEqual(result['scope_classification'], 'historical_cloudflare_only')
        self.assertIs(result['current_supabase_release_accepted'], False)


if __name__ == '__main__':
    unittest.main()
