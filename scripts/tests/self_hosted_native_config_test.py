"""Public profile parity only; no compiler, signing key, or deployment access."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('native_config', ROOT / 'scripts/qa/native_build_config.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class SelfHostedNativeProfileTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.pubspec = Path(self.temp.name) / 'pubspec.yaml'
        self.pubspec.write_text('name: collect\nversion: 1.2.3+17\n')
        self.profile = dict(format='collect.deployment.v1', id='collect-selfhost', mode='self_hosted',
            environment='production', supabase_origin='https://supabase.collect.example',
            member_api_origin='https://api.collect.example', admin_origin='https://admin.collect.example',
            public_origin='https://collect.example', google_callback_origin='https://admin.collect.example')
        self.env = dict(SUPABASE_URL=self.profile['supabase_origin'], SUPABASE_API_URL=self.profile['member_api_origin'],
            SUPABASE_PUBLISHABLE_KEY='sb_publishable_synthetic_test_key', AUTH_CAPTCHA_SITE_KEY='synthetic_public_captcha',
            COLLECT_SMS_AUTH_ENABLED='true', COLLECT_WHATSAPP_AUTH_ENABLED='false', COLLECT_ANONYMOUS_AUTH_ENABLED='true')

    def configured(self, **extra):
        raw = json.dumps(self.profile, sort_keys=True, separators=(',', ':'))
        return {**self.env, 'COLLECT_DEPLOYMENT_PROFILE': raw,
            'COLLECT_DEPLOYMENT_PROFILE_SHA256': hashlib.sha256(raw.encode()).hexdigest(), **extra}

    def test_public_config_roundtrip_and_exact_origins(self):
        values = native.configuration(self.configured(), 'android', self.pubspec)
        self.assertEqual(values['SUPABASE_AUTH_ISSUER'], self.profile['supabase_origin'] + '/auth/v1')
        self.assertEqual(values['SUPABASE_ADMIN_API_URL'], self.profile['admin_origin'])
        self.assertEqual(values['COLLECT_SMS_AUTH_ENABLED'], 'true')
        self.assertEqual(values['COLLECT_WHATSAPP_AUTH_ENABLED'], 'false')
        self.assertEqual(values, native.configuration(values, 'android', self.pubspec))

    def test_mismatched_config_is_rejected_without_echoing_values(self):
        for extra in [dict(COLLECT_DEPLOYMENT_PROFILE_SHA256='0'*64), dict(SUPABASE_AUTH_ISSUER='http://api-gw:8000/auth/v1'),
                      dict(SUPABASE_API_URL='https://private.invalid'), dict(COLLECT_SMS_AUTH_ENABLED='1'),
                      dict(SUPABASE_PUBLISHABLE_KEY='sb_secret_synthetic_private')]:
            with self.subTest(extra=list(extra)):
                with self.assertRaises(ValueError) as caught:
                    native.configuration(self.configured(**extra), 'android', self.pubspec)
                self.assertNotIn('synthetic_private', str(caught.exception))
                self.assertNotIn('api-gw', str(caught.exception))

    def test_release_refuses_qualification_noncanonical_and_numeric_origins(self):
        self.profile['environment'] = 'qualification'
        with self.assertRaises(ValueError): native.configuration(self.configured(), 'android', self.pubspec)
        self.profile['environment'] = 'production'
        env = self.configured(); env['COLLECT_DEPLOYMENT_PROFILE'] += ' '
        with self.assertRaises(ValueError): native.configuration(env, 'android', self.pubspec)
        for origin in ['https://127.1', 'http://api-gw:8000', 'https://localhost', 'https://api.collect.example/path']:
            self.profile['google_callback_origin'] = origin
            with self.assertRaises(ValueError): native.configuration(self.configured(), 'android', self.pubspec)

    def test_store_build_refuses_every_documented_public_turnstile_test_key(self):
        for key in native.TURNSTILE_TEST_SITE_KEYS:
            for platform in ('android', 'ios'):
                with self.subTest(key=key, platform=platform), self.assertRaisesRegex(ValueError, 'test key'):
                    native.configuration(self.configured(AUTH_CAPTCHA_SITE_KEY=key), platform, self.pubspec)


if __name__ == '__main__': unittest.main()
