"""Synthetic provider-settings parsing and refusal checks; no service is started."""
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts.self_hosted.assets import install, tree
from scripts.self_hosted.configure import (
    configure,
    parse_fcm_account_json,
    read_provider_settings,
    validated_settings,
)
from scripts.self_hosted.prepare import PROVIDER_SETTINGS
from scripts.self_hosted.release_operator import Operator


SECRET = 'synthetic-private-never-disclose'
PROFILE = {
    'format': 'collect.deployment.v1', 'id': 'synthetic-provider',
    'mode': 'self_hosted', 'environment': 'qualification',
    'supabase_origin': 'https://supabase.example',
    'member_api_origin': 'https://api.example',
    'admin_origin': 'https://admin.example', 'public_origin': 'https://public.example',
    'google_callback_origin': 'https://admin.example',
}


class ProviderJsonSafety(unittest.TestCase):
    def assert_redacted_exception(self, error):
        pending = [error]
        seen = set()
        while pending:
            current = pending.pop()
            if id(current) in seen:
                continue
            seen.add(id(current))
            for value in (str(current), repr(current), repr(current.args), repr(vars(current)),
                          repr(getattr(current, 'doc', None)), repr(getattr(current, 'object', None))):
                self.assertNotIn(SECRET, value)
            pending.extend(link for link in (current.__cause__, current.__context__) if link is not None)
        self.assertIsNone(error.__cause__)
        self.assertIsNone(error.__context__)

    def assert_rejected(self, call):
        with self.assertRaises(ValueError) as caught:
            call()
        self.assert_redacted_exception(caught.exception)

    def test_valid_unicode_service_account_remains_accepted(self):
        account = {
            'type': 'service_account', 'project_id': 'sample-prj1',
            'token_uri': 'https://oauth2.googleapis.com/token', 'private_key_id': 'synthetic-key',
            'client_email': 'sender@sample-prj1.iam.gserviceaccount.com',
            'private_key': '-----BEGIN PRIVATE KEY-----\nQUJD\n-----END PRIVATE KEY-----\n',
            'display_name': 'Café Kigali 🌍',
        }
        encoded = json.dumps(account, ensure_ascii=False)
        self.assertEqual(parse_fcm_account_json(encoded), account)
        settings = {**PROVIDER_SETTINGS, 'SMTP_PASS': '\b\t\n\f\r', 'FCM_PROJECT_ID': 'sample-prj1',
                    'FCM_SERVICE_ACCOUNT_JSON': encoded}
        self.assertTrue(validated_settings(settings, PROFILE, 'a' * 64)['configuration_only'])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'provider-settings.json'
            path.write_text(json.dumps(settings, ensure_ascii=False), encoding='utf8')
            self.assertEqual(read_provider_settings(path), settings)

    def test_nested_invalid_inputs_never_expose_decoder_attributes(self):
        cases = (
            '{"private_key":"' + SECRET + '"',
            '{"private_key":"' + SECRET + '\ud800"}',
            '{"private_key":"' + SECRET + '\\ud800"}',
            '["' + SECRET + '"]',
            '[' * 8000 + '"' + SECRET + '"' + ']' * 8000,
            'null',
            '{"private_key":"' + SECRET + '"' + ' ' * 16384 + '}',
        )
        for value in cases:
            with self.subTest(kind=repr(value[:30])):
                settings = {**PROVIDER_SETTINGS, 'FCM_SERVICE_ACCOUNT_JSON': value}
                self.assert_rejected(lambda: validated_settings(settings, PROFILE, 'a' * 64))

    def test_deep_json_failure_does_not_leave_an_exception_context(self):
        with patch('scripts.self_hosted.configure.json.loads', side_effect=RecursionError(SECRET)):
            self.assert_rejected(lambda: parse_fcm_account_json('{"private_key":"fixture"}'))

    def test_outer_provider_file_fails_closed_on_invalid_utf8_or_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'provider-settings.json'
            for data in (b'{"private":"' + SECRET.encode() + b'",',
                         b'{"private":"' + SECRET.encode() + b'\xff"}',
                         b'{"field":' + b'[' * 1200 + b'"' + SECRET.encode() + b'"' + b']' * 1200 + b'}',
                         ('["' + SECRET + '"]').encode()):
                with self.subTest(length=len(data)):
                    path.write_bytes(data)
                    self.assert_rejected(lambda: read_provider_settings(path))
            path.write_bytes(b'{"private":"' + SECRET.encode() + b'"}' + b' ' * 128)
            with patch('scripts.self_hosted.configure.MAX_PROVIDER_SETTINGS_BYTES', 64), \
                 patch('scripts.self_hosted.configure.json.loads') as decode:
                self.assert_rejected(lambda: read_provider_settings(path))
                decode.assert_not_called()

    def test_configure_refuses_outer_and_nested_errors_before_projection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            private = root / 'private'
            private.mkdir()
            (root / 'release.json').write_text(json.dumps({'profile': PROFILE, 'source_sha256': 'a' * 64}))
            provider = private / 'provider-settings.json'
            outputs = ('private/stack.env', 'private/functions.env', 'public.env',
                       'client.json', 'private/configuration.json')
            for name in outputs:
                (root / name).write_text('retained synthetic output')
            cases = (
                b'{"private":"' + SECRET.encode() + b'",',
                json.dumps({**PROVIDER_SETTINGS, 'FCM_SERVICE_ACCOUNT_JSON':
                            '{"private_key":"' + SECRET + '"'}).encode(),
                json.dumps({**PROVIDER_SETTINGS, 'FCM_SERVICE_ACCOUNT_JSON':
                            '{"private_key":"' + SECRET + '\ud800"}'}).encode(),
                json.dumps({**PROVIDER_SETTINGS, 'SMTP_PASS': SECRET + '\ud800'}).encode(),
            )
            for data in cases:
                with self.subTest(length=len(data)):
                    provider.write_bytes(data)
                    provider.chmod(0o600)
                    self.assert_rejected(lambda: configure(root))
                    for name in outputs:
                        self.assertEqual((root / name).read_text(), 'retained synthetic output')
                    self.assertEqual(list(root.rglob('*.next')), [])

    def test_publish_rejects_non_fcm_unprojectable_text_before_service_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            private = root / 'private'
            private.mkdir()
            op = Operator.__new__(Operator)
            op.root = root
            op.profile = PROFILE
            op.meta = {'source_sha256': 'a' * 64}
            for invalid in ('\ud800', '\x01'):
                with self.subTest(kind=repr(invalid)):
                    settings = {**PROVIDER_SETTINGS, 'SMTP_PASS': SECRET + invalid}
                    (private / 'provider-settings.json').write_text(json.dumps(settings))
                    with patch.object(op, 'docker_preflight') as docker, \
                         patch.object(op, 'validate_runtime_database') as database, \
                         patch.object(op, 'compose') as compose, \
                         patch('scripts.self_hosted.assets.verify_assets') as assets:
                        self.assert_rejected(op.publish)
                    docker.assert_not_called()
                    database.assert_not_called()
                    compose.assert_not_called()
                    assets.assert_not_called()

    def test_asset_install_refuses_bad_provider_values_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            root = base / 'release'
            private = root / 'private'
            private.mkdir(parents=True)
            for surface in ('admin', 'public'):
                (root / 'assets' / surface).mkdir(parents=True)
                (base / surface).mkdir()
                (base / surface / 'index.html').write_text('synthetic frontend')
            (root / 'client.json').write_text('{}')
            (private / 'keys.json').write_text(json.dumps({'JWT_KEYS': '[]'}))
            meta = {'profile_sha256': 'a' * 64, 'source_sha256': 'b' * 64,
                    'frontend_source_sha256': 'c' * 64, 'frontend_source_complete': True}
            receipt = {
                'format': 'collect.selfhost.frontend-build.v1',
                'profile_sha256': meta['profile_sha256'], 'source_sha256': meta['source_sha256'],
                'frontend_source_sha256': meta['frontend_source_sha256'],
                'client_config_sha256': hashlib.sha256((root / 'client.json').read_bytes()).hexdigest(),
                'toolchain': {'synthetic': 'offline'},
                'commands': {'admin': ['synthetic'], 'public': ['synthetic']},
                'surfaces': {surface: tree(base / surface) for surface in ('admin', 'public')},
            }
            evidence = base / 'build-evidence.json'
            evidence.write_text(json.dumps(receipt))
            provider = private / 'provider-settings.json'
            op = SimpleNamespace(root=root, meta=meta)
            cases = (
                b'{"private":"' + SECRET.encode() + b'",',
                json.dumps({**PROVIDER_SETTINGS, 'FCM_SERVICE_ACCOUNT_JSON':
                            '{"private_key":"' + SECRET + '"'}).encode(),
                json.dumps({**PROVIDER_SETTINGS, 'FCM_SERVICE_ACCOUNT_JSON':
                            '{"private_key":"' + SECRET + '\ud800"}'}).encode(),
                json.dumps({**PROVIDER_SETTINGS, 'FCM_SERVICE_ACCOUNT_JSON':
                            '{"private_key":"' + SECRET + '\\ud800"}'}).encode(),
                json.dumps({**PROVIDER_SETTINGS, 'FCM_SERVICE_ACCOUNT_JSON':
                            '["' + SECRET + '"]'}).encode(),
                json.dumps({**PROVIDER_SETTINGS, 'FCM_SERVICE_ACCOUNT_JSON':
                            '[' * 8000 + '"' + SECRET + '"' + ']' * 8000}).encode(),
                json.dumps({**PROVIDER_SETTINGS, 'SMTP_PASS': SECRET + '\ud800'}).encode(),
            )
            for data in cases:
                with self.subTest(length=len(data)):
                    provider.write_bytes(data)
                    provider.chmod(0o600)
                    self.assert_rejected(lambda: install(op, base / 'admin', base / 'public', evidence))
                    self.assertEqual(list((root / 'assets').rglob('*.html')), [])
                    self.assertFalse((root / 'assets-build-evidence.json').exists())
                    self.assertFalse((root / 'assets-manifest.json').exists())


if __name__ == '__main__':
    unittest.main()
