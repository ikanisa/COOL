#!/usr/bin/env python3
"""Synthetic source/command failure checks; never executes Flutter or hosted I/O."""
import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

PATH = Path(__file__).with_name('run_admin_checkpoint.py')
SPEC = importlib.util.spec_from_file_location('admin_checkpoint', PATH)
checkpoint = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checkpoint)


class CheckpointSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name).resolve()
        self.work = self.directory / 'work'
        self.candidate = self.directory / 'candidate'
        self.packet = self.directory / 'packet'
        for path in (self.work, self.candidate, self.packet):
            path.mkdir()
        self.patchers = [patch.object(checkpoint, key, value) for key, value in
                        [('WORK', self.work), ('CANDIDATE', self.candidate), ('PACKET', self.packet), ('LABEL', 'synthetic-check'), ('PUBLIC_CONFIG', None), ('PUBLIC_KEY_BYTES', None)]]
        for item in self.patchers:
            item.start()

    def tearDown(self):
        for item in reversed(self.patchers):
            item.stop()
        self.temporary.cleanup()

    def manifest(self):
        source = self.work / 'lib/main_admin.dart'
        source.parent.mkdir()
        source.write_text('synthetic local source only\n')
        return {'source_files': {'lib/main_admin.dart': {
            'sha256': checkpoint.module.sha(source.read_bytes()), 'bytes': source.stat().st_size,
            'mode': stat.S_IMODE(source.stat().st_mode)}}}

    def arguments(self, work=None, candidate=None):
        return ['run_admin_checkpoint.py', 'plain', '--workspace', str(work or self.work),
                '--candidate', str(candidate or self.candidate), '--manifest-sha256', 'a' * 64,
                '--packet', str(self.packet), '--label', 'synthetic-check']

    def test_per_file_bytes_and_modes_detect_tamper(self):
        manifest = self.manifest()
        self.assertEqual(checkpoint.selected_changes(manifest), [])
        source = self.work / 'lib/main_admin.dart'
        source.chmod(source.stat().st_mode ^ stat.S_IXUSR)
        self.assertEqual(checkpoint.selected_changes(manifest), ['lib/main_admin.dart'])
        source.write_text('different source\n')
        self.assertEqual(checkpoint.selected_changes(manifest), ['lib/main_admin.dart'])

    def test_missing_and_symlinked_selected_source_fail_closed(self):
        manifest = self.manifest()
        source = self.work / 'lib/main_admin.dart'
        source.unlink()
        self.assertEqual(checkpoint.selected_changes(manifest), ['lib/main_admin.dart'])
        source.symlink_to(self.directory / 'missing')
        self.assertEqual(checkpoint.selected_changes(manifest), ['lib/main_admin.dart'])

    def test_in_checkout_workspace_rejected_before_any_command(self):
        with patch('sys.argv', self.arguments(work=checkpoint.ROOT)), patch.object(checkpoint, 'run_command') as run:
            with self.assertRaises(checkpoint.module.ReleaseError) as error:
                checkpoint.main()
            self.assertEqual(error.exception.code, 'CANDIDATE_DESTINATION_NOT_ISOLATED')
            run.assert_not_called()

    def test_candidate_workspace_overlap_rejected_before_commands(self):
        with patch('sys.argv', self.arguments(work=self.candidate)), patch.object(checkpoint, 'run_command') as run:
            with self.assertRaises(checkpoint.module.ReleaseError) as error:
                checkpoint.main()
            self.assertEqual(error.exception.code, 'CANDIDATE_DESTINATION_NOT_ISOLATED')
            run.assert_not_called()

    def test_symlink_workspace_rejected_before_commands(self):
        link = self.directory / 'link'
        link.symlink_to(self.work, target_is_directory=True)
        with patch('sys.argv', self.arguments(work=link)), patch.object(checkpoint, 'run_command') as run:
            with self.assertRaises(checkpoint.module.ReleaseError) as error:
                checkpoint.main()
            self.assertEqual(error.exception.code, 'CANDIDATE_SYMLINK_REFUSED')
            run.assert_not_called()

    def test_timeout_retains_actual_partial_log_and_failure_receipt(self):
        timeout = subprocess.TimeoutExpired(['synthetic-flutter'], 1, output=b'actual synthetic partial output\n')
        with patch.object(checkpoint.subprocess, 'run', side_effect=timeout) as run, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(checkpoint.module.ReleaseError):
                checkpoint.run_command(['synthetic-flutter'], 'synthetic-timeout', {'CI': 'true'}, 1)
            self.assertEqual(run.call_count, 1)
        receipt = json.loads((self.packet / 'synthetic-timeout.result.json').read_text())
        self.assertEqual(receipt['exit_code'], 124)
        self.assertFalse(receipt['backend_configuration_supplied'])
        self.assertEqual(receipt['hosted_mutations'], 0)
        self.assertIn(b'actual synthetic partial output', (self.packet / 'synthetic-timeout.log').read_bytes())

    def test_private_pattern_in_command_output_is_never_written_or_printed(self):
        pattern = ('ghp_' + 'z' * 42).encode()
        result = subprocess.CompletedProcess(['synthetic-flutter'], 0, pattern)
        captured = io.StringIO()
        with patch.object(checkpoint.subprocess, 'run', return_value=result), contextlib.redirect_stdout(captured):
            with self.assertRaises(checkpoint.module.ReleaseError) as error:
                checkpoint.run_command(['synthetic-flutter'], 'synthetic-redaction', {}, 1)
        self.assertEqual(error.exception.code, 'CANDIDATE_CREDENTIAL_PATTERN')
        self.assertFalse((self.packet / 'synthetic-redaction.log').exists())
        self.assertNotIn(pattern.decode(), captured.getvalue())


    def public_config(self, key=None):
        if key is None:
            encode = lambda value: base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip('=')
            key = '.'.join([encode({'alg': 'HS256', 'typ': 'JWT'}), encode({'iss': 'supabase', 'ref': checkpoint.PROJECT_REF, 'role': 'anon', 'iat': int(time.time()) - 60, 'exp': int(time.time()) + 3600}), 'synthetic_signature_' + 'a' * 30])
        return {'SUPABASE_URL': 'https://' + checkpoint.PROJECT_REF + '.supabase.co', 'SUPABASE_ANON_KEY': key,
                'ENABLE_ADMIN_PANEL': True, 'APP_ENVIRONMENT': 'production'}

    def public_file(self, config=None):
        folder = self.directory / 'private-config'
        folder.mkdir(mode=0o700)
        path = folder / 'defines.json'
        path.write_text(json.dumps(config or self.public_config()))
        path.chmod(0o600)
        return path, checkpoint.module.sha(path.read_bytes())

    def test_current_public_anon_claims_and_publishable_form_are_allowed(self):
        config, metadata = checkpoint.validate_public_defines(json.dumps(self.public_config()).encode())
        self.assertEqual(metadata['key_form'], 'public_anon_jwt')
        self.assertFalse(metadata['remote_authentication_attested'])
        config, metadata = checkpoint.validate_public_defines(json.dumps(self.public_config('sb_publishable_' + 'x' * 32)).encode())
        self.assertEqual(metadata['key_form'], 'public_publishable_key')

    def test_privileged_user_secret_and_unknown_keys_are_rejected(self):
        for key in ('sb_secret_' + 'x' * 32, 'Bearer synthetic_user_token', 'synthetic_invalid'):
            with self.subTest(key=key[:8]), self.assertRaises(checkpoint.module.ReleaseError):
                checkpoint.validate_public_defines(json.dumps(self.public_config(key)).encode())
        for field in ('ADMIN_PWA_EVIDENCE_MODE', 'AUTH_CAPTCHA_SITE_KEY', 'ENABLE_ADMIN_DEV_TOOLS', 'ACCESS_TOKEN'):
            config = self.public_config();config[field] = 'synthetic_unrequested'
            with self.subTest(field=field), self.assertRaises(checkpoint.module.ReleaseError):
                checkpoint.validate_public_defines(json.dumps(config).encode())

    def test_wrong_project_environment_or_non_true_flag_is_rejected(self):
        for field, value in [('SUPABASE_URL', 'https://example.supabase.co'), ('SUPABASE_URL', 'http://' + checkpoint.PROJECT_REF + '.supabase.co'), ('APP_ENVIRONMENT', 'local'), ('ENABLE_ADMIN_PANEL', 1), ('ENABLE_ADMIN_PANEL', 'false')]:
            config = self.public_config();config[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(checkpoint.module.ReleaseError):
                checkpoint.validate_public_defines(json.dumps(config).encode())

    def test_authenticated_service_roles_and_mismatching_refs_are_rejected(self):
        config = self.public_config();parts = config['SUPABASE_ANON_KEY'].split('.')
        claims = json.loads(base64.urlsafe_b64decode(parts[1] + '=' * (-len(parts[1]) % 4)))
        for field, value in [('role', 'authenticated'), ('role', 'service_role'), ('ref', 'other_project'), ('exp', int(time.time()) - 10), ('iat', True)]:
            changed = {**claims, field: value}
            encoded = base64.urlsafe_b64encode(json.dumps(changed).encode()).decode().rstrip('=')
            config['SUPABASE_ANON_KEY'] = '.'.join([parts[0], encoded, parts[2]])
            with self.subTest(field=field, value=value), self.assertRaises(checkpoint.module.ReleaseError):
                checkpoint.validate_public_defines(json.dumps(config).encode())

    def test_duplicate_keys_and_malformed_json_are_rejected(self):
        for data in (b'{"SUPABASE_URL":"a","SUPABASE_URL":"b"}', b'{broken', b'[]', b'null'):
            with self.subTest(data=data), self.assertRaises(checkpoint.module.ReleaseError):
                checkpoint.validate_public_defines(data)

    def test_public_file_hash_modes_and_no_symlink_are_required(self):
        path, digest = self.public_file()
        raw, config, metadata = checkpoint.read_public_defines(path, digest)
        self.assertEqual(metadata['sha256'], digest)
        with self.assertRaises(checkpoint.module.ReleaseError):
            checkpoint.read_public_defines(path, 'a' * 64)
        path.chmod(0o644)
        with self.assertRaises(checkpoint.module.ReleaseError):
            checkpoint.read_public_defines(path, digest)
        path.chmod(0o600);link = path.parent / 'link.json';link.symlink_to(path)
        with self.assertRaises(checkpoint.module.ReleaseError):
            checkpoint.read_public_defines(link, digest)
        path.parent.chmod(0o755)
        with self.assertRaises(checkpoint.module.ReleaseError):
            checkpoint.read_public_defines(path, digest)

    def test_staged_public_bytes_are_pinned_and_tampering_rejected(self):
        raw = json.dumps(self.public_config()).encode()
        staged = checkpoint.stage_public_defines(raw)
        self.assertEqual(staged.read_bytes(), raw)
        self.assertEqual(stat.S_IMODE(staged.stat().st_mode), 0o600)
        self.assertEqual(checkpoint.stage_public_defines(raw), staged)
        staged.write_bytes(b'changed')
        with self.assertRaises(checkpoint.module.ReleaseError):
            checkpoint.stage_public_defines(raw)

    def test_public_key_redacted_from_actual_command_log_and_console(self):
        key = ('sb_publishable_' + 'x' * 32).encode()
        output = b'compiler synthetic output ' + key + b'\n'
        with patch.object(checkpoint, 'PUBLIC_KEY_BYTES', key), patch.object(checkpoint, 'PUBLIC_CONFIG', {'sha256': 'a' * 64}), patch.object(checkpoint.subprocess, 'run', return_value=subprocess.CompletedProcess(['synthetic-flutter'], 0, output)), contextlib.redirect_stdout(io.StringIO()) as console:
            checkpoint.run_command(['synthetic-flutter'], 'synthetic-public-redaction', {}, 1)
        self.assertNotIn(key, (self.packet / 'synthetic-public-redaction.log').read_bytes())
        self.assertNotIn(key.decode(), console.getvalue())
        receipt = json.loads((self.packet / 'synthetic-public-redaction.result.json').read_text())
        self.assertEqual(receipt['public_key_occurrences_redacted'], 1)
        self.assertTrue(receipt['backend_configuration_supplied'])
        self.assertNotIn(key.decode(), json.dumps(receipt))

    def test_configured_mode_requires_file_and_plain_refuses_file_before_commands(self):
        for arguments in ([*self.arguments()[:1], 'configured', *self.arguments()[2:]], self.arguments() + ['--defines-file', '/synthetic/ignored.json', '--defines-sha256', 'a' * 64]):
            with self.subTest(mode=arguments[1]), patch('sys.argv', arguments), patch.object(checkpoint, 'run_command') as run:
                with self.assertRaises(checkpoint.module.ReleaseError):
                    checkpoint.main()
                run.assert_not_called()


if __name__ == '__main__':
    unittest.main(verbosity=2)
