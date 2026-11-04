"""Synthetic self-hosted environment encoding checks; no service is started."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from scripts.self_hosted.configure import configure, read_env
from scripts.self_hosted.prepare import PROVIDER_SETTINGS, dotenv, prepare


PROFILE = {
    'format': 'collect.deployment.v1', 'id': 'synthetic-env',
    'mode': 'self_hosted', 'environment': 'qualification',
    'supabase_origin': 'https://supabase.example',
    'member_api_origin': 'https://api.example',
    'admin_origin': 'https://admin.example', 'public_origin': 'https://public.example',
    'google_callback_origin': 'https://admin.example',
}


class EnvironmentProjection(unittest.TestCase):
    def test_unicode_and_compose_escapes_roundtrip(self):
        values = {
            'UNICODE': 'Café · Kigali 🌍',
            'LINE_SEPARATORS': 'a\u0085b\u2028c\u2029d',
            'SPECIAL': '$name ${other} $$ `text` \\ "quoted"',
            'CONTROLS': '\b\t\n\f\r',
            'EMPTY': '',
        }
        encoded = dotenv(values)
        self.assertIn('Café · Kigali 🌍', encoded)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'variables.env'
            path.write_text(encoded, encoding='utf8')
            self.assertEqual(read_env(path), values)

    def test_legacy_ascii_json_escaped_files_remain_readable(self):
        original = {'LABEL': 'Café', 'SECRET': '$literal $$'}
        legacy = ''.join(
            key + '=' + json.dumps(value.replace('$', '$$')) + '\n'
            for key, value in sorted(original.items())
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'legacy.env'
            path.write_text(legacy, encoding='utf8')
            self.assertEqual(read_env(path), original)

    def test_unrepresentable_controls_and_surrogates_are_rejected(self):
        for value in ('invalid\x01value', 'invalid\x0bvalue', 'invalid\x1bvalue', '\ud800'):
            with self.subTest(value=repr(value)), self.assertRaisesRegex(ValueError, 'environment'):
                dotenv({'VALUE': value})

    def test_invalid_provider_value_does_not_replace_or_stage_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            private = root / 'private'
            private.mkdir()
            (root / 'release.json').write_text(json.dumps({'profile': PROFILE, 'source_sha256': 'a' * 64}))
            provider = private / 'provider-settings.json'
            provider.write_text(json.dumps({**PROVIDER_SETTINGS, 'SMTP_SENDER_NAME': 'invalid\x01value'}))
            provider.chmod(0o600)
            initial = {
                'private/stack.env': dotenv({'PRESERVED': 'stack'}),
                'private/functions.env': dotenv({'PRESERVED': 'functions'}),
                'public.env': dotenv({'PRESERVED': 'public'}),
                'client.json': 'retained synthetic client',
                'private/configuration.json': 'retained synthetic receipt',
            }
            for name, data in initial.items():
                (root / name).write_text(data, encoding='utf8')
            with self.assertRaisesRegex(ValueError, 'environment'):
                configure(root)
            for name, data in initial.items():
                self.assertEqual((root / name).read_text(encoding='utf8'), data)
            self.assertEqual(list(root.rglob('*.next')), [])

    def test_unrepresentable_release_path_is_refused_before_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            profile = root / 'profile.json'
            profile.write_text(json.dumps(PROFILE))
            output = root / 'release\x01invalid'
            with patch('scripts.self_hosted.prepare._capture_inputs') as capture, \
                 patch('scripts.self_hosted.prepare.subprocess.run') as command:
                with self.assertRaisesRegex(ValueError, 'environment'):
                    prepare(profile, output, tls_mode='internal')
            self.assertFalse(output.exists())
            capture.assert_not_called()
            command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
