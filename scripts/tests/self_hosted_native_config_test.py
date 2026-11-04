"""Public profile parity only; no compiler, signing key, or deployment access."""
import hashlib
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

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

    def test_candidate_requires_explicit_self_hosted_profile_and_enabled_sms(self):
        for platform in ('android', 'ios'):
            values = native.store_candidate_configuration(self.configured(), platform, self.pubspec)
            self.assertEqual(values, native.configuration(self.configured(), platform, self.pubspec))
            self.assertEqual(values['COLLECT_SMS_AUTH_ENABLED'], 'true')
            self.assertEqual(values['COLLECT_DEPLOYMENT_PROFILE_SHA256'], self.configured()['COLLECT_DEPLOYMENT_PROFILE_SHA256'])

    def test_candidate_rejects_absent_malformed_mismatched_or_disabled_inputs(self):
        valid = self.configured()
        missing_profile = dict(valid); del missing_profile['COLLECT_DEPLOYMENT_PROFILE']
        missing_digest = dict(valid); del missing_digest['COLLECT_DEPLOYMENT_PROFILE_SHA256']
        missing_sms = dict(valid); del missing_sms['COLLECT_SMS_AUTH_ENABLED']
        no_profile = dict(missing_profile); del no_profile['COLLECT_DEPLOYMENT_PROFILE_SHA256']
        malformed = {**valid, 'COLLECT_DEPLOYMENT_PROFILE': '{'}
        duplicate = {**valid, 'COLLECT_DEPLOYMENT_PROFILE': valid['COLLECT_DEPLOYMENT_PROFILE'].replace(
            '"mode":"self_hosted"', '"mode":"self_hosted","mode":"self_hosted"')}
        cases = [missing_profile, missing_digest, no_profile, missing_sms, malformed, duplicate,
                 {**valid, 'COLLECT_DEPLOYMENT_PROFILE': valid['COLLECT_DEPLOYMENT_PROFILE'] + ' '},
                 {**valid, 'COLLECT_DEPLOYMENT_PROFILE_SHA256': '0' * 64},
                 {**valid, 'COLLECT_SMS_AUTH_ENABLED': 'false'},
                 {**valid, 'COLLECT_SMS_AUTH_ENABLED': '1'},
                 {**valid, 'SUPABASE_URL': 'https://wrong.collect.example'},
                 {**valid, 'SUPABASE_API_URL': 'https://wrong.collect.example'},
                 {**valid, 'SUPABASE_AUTH_ISSUER': 'https://wrong.collect.example/auth/v1'}]
        for platform in ('android', 'ios'):
            for case in cases:
                with self.subTest(platform=platform, case=cases.index(case)), self.assertRaises(ValueError):
                    native.store_candidate_configuration(case, platform, self.pubspec)

    def test_candidate_rejects_managed_qualification_and_disguised_managed_origin(self):
        original = dict(self.profile)
        variants = [dict(mode='managed', supabase_origin=native.PROJECT),
                    dict(environment='qualification'), dict(supabase_origin=native.PROJECT)]
        for variant in variants:
            self.profile = {**original, **variant}
            env = self.configured(SUPABASE_URL=self.profile['supabase_origin'])
            for platform in ('android', 'ios'):
                with self.subTest(variant=variant, platform=platform), self.assertRaises(ValueError):
                    native.store_candidate_configuration(env, platform, self.pubspec)

    def test_generic_managed_configuration_remains_available(self):
        legacy = {'SUPABASE_URL': native.PROJECT, 'SUPABASE_API_URL': native.ADMIN,
                  'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_synthetic_test_key',
                  'AUTH_CAPTCHA_SITE_KEY': 'synthetic_public_captcha'}
        for platform in ('android', 'ios'):
            self.assertEqual(native.configuration(legacy, platform, self.pubspec)['SUPABASE_URL'], native.PROJECT)
            with self.assertRaises(ValueError):
                native.store_candidate_configuration(legacy, platform, self.pubspec)

    def cli(self, env, *args):
        with patch.dict(os.environ, env, clear=True), patch.object(sys, 'argv', ['native_build_config.py', *args]):
            native.main()

    def test_candidate_cli_generates_and_validates_each_platform(self):
        path = Path(self.temp.name) / 'candidate.json'
        for platform in ('android', 'ios'):
            self.cli(self.configured(), platform, '--store-candidate', '--defines-output', str(path))
            values = json.loads(path.read_text())
            self.assertEqual(values['COLLECT_SMS_AUTH_ENABLED'], 'true')
            self.assertEqual(values['COLLECT_DEPLOYMENT_PROFILE_SHA256'], self.configured()['COLLECT_DEPLOYMENT_PROFILE_SHA256'])
            self.cli({}, platform, '--store-candidate', '--validate-defines', str(path))

    def test_candidate_cli_refuses_invalid_input_and_invalid_saved_defines(self):
        path = Path(self.temp.name) / 'candidate.json'
        valid = self.configured()
        cases = [{key: value for key, value in valid.items() if key != field}
                 for field in ('COLLECT_DEPLOYMENT_PROFILE', 'COLLECT_DEPLOYMENT_PROFILE_SHA256', 'COLLECT_SMS_AUTH_ENABLED')]
        cases += [{**valid, 'COLLECT_DEPLOYMENT_PROFILE_SHA256': '0' * 64},
                  {**valid, 'COLLECT_SMS_AUTH_ENABLED': 'false'},
                  {'SUPABASE_URL': native.PROJECT, 'SUPABASE_API_URL': native.ADMIN,
                   'SUPABASE_PUBLISHABLE_KEY': self.env['SUPABASE_PUBLISHABLE_KEY'],
                   'AUTH_CAPTCHA_SITE_KEY': self.env['AUTH_CAPTCHA_SITE_KEY']}]
        for platform in ('android', 'ios'):
            for case in cases:
                with self.subTest(platform=platform, keys=sorted(case)), contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as caught:
                        self.cli(case, platform, '--store-candidate', '--defines-output', str(path))
                    self.assertEqual(caught.exception.code, 2)
            self.cli(valid, platform, '--store-candidate', '--defines-output', str(path))
            saved = json.loads(path.read_text())
            invalid = [{key: value for key, value in saved.items() if key != field}
                       for field in ('COLLECT_DEPLOYMENT_PROFILE', 'COLLECT_DEPLOYMENT_PROFILE_SHA256', 'COLLECT_SMS_AUTH_ENABLED')]
            invalid += [{**saved, 'COLLECT_SMS_AUTH_ENABLED': 'false'},
                        {**saved, 'COLLECT_DEPLOYMENT_PROFILE_SHA256': '0' * 64}]
            for values in invalid:
                path.write_text(json.dumps(values))
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as caught:
                    self.cli({}, platform, '--store-candidate', '--validate-defines', str(path))
                self.assertEqual(caught.exception.code, 2)

            legacy = {'SUPABASE_URL': native.PROJECT, 'SUPABASE_API_URL': native.ADMIN,
                      'SUPABASE_PUBLISHABLE_KEY': self.env['SUPABASE_PUBLISHABLE_KEY'],
                      'AUTH_CAPTCHA_SITE_KEY': self.env['AUTH_CAPTCHA_SITE_KEY']}
            self.cli(legacy, platform, '--defines-output', str(path))
            self.cli({}, platform, '--validate-defines', str(path))
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as caught:
                self.cli({}, platform, '--store-candidate', '--validate-defines', str(path))
            self.assertEqual(caught.exception.code, 2)


if __name__ == '__main__': unittest.main()
