"""Sealed synthetic inputs only; no retained config, Docker or email provider."""
import copy
from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import re
import tomllib
import unittest
from unittest.mock import patch

from scripts.self_hosted import retained_auth as a
from scripts.self_hosted import test_release_source_identity as source_fixture
from scripts.self_hosted.prepare import PROVIDER_SETTINGS, dotenv, seal_configuration

PASSWORD = 'synthetic-SMTP-private-token-do-not-print'
CAPTCHA_SECRET = 'synthetic-Turnstile-private-secret-do-not-print'
SITE_KEY = 'synthetic-Turnstile-public-site-key'
CONFIG = '''project_id = "local-app"
[api]
port = 55101
external_url = "http://127.0.0.1:55101"
[auth]
enabled = true
site_url = "http://127.0.0.1:3000"
additional_redirect_urls = ["http://127.0.0.1:3000/callback"]
signing_keys_path = "./private/signing_keys.json"
jwt_secret = 'env(DEV_JWT_SECRET)'
publishable_key = 'env(DEV_PUBLISHABLE_KEY)'
secret_key = 'env(DEV_SECRET_KEY)'
enable_signup = true
enable_anonymous_sign_ins = true
[auth.email]
enable_signup = true
enable_confirmations = true
[auth.email.template.magic_link]
content_path = "./templates/magic_link.html"
[auth.sms]
otp_expiry = 6000
[auth.external.google]
enabled = false
client_id = 'env(GOOGLE_CLIENT_ID)'
secret = 'env(GOOGLE_SECRET)'
skip_nonce_check = false
[auth.hook.send_sms]
enabled = true
uri = "http://127.0.0.1:55101/functions/v1/send-sms-hook"
secrets = 'env(AUTH_SEND_SMS_SECRET)'
[edge_runtime]
enabled = true
policy = "oneshot"
inspector_port = 55112
[edge_runtime.secrets]
UNCHANGED_SMS_PORT = 'env(AUTH_SEND_SMS_SECRET)'
[experimental]
stack = false
'''


class RetainedAuth(unittest.TestCase):
    def setUp(self):
        self.fixture = source_fixture.ReleaseSourceIdentity(methodName='runTest')
        self.fixture.setUp(); self.addCleanup(self.fixture.doCleanups)
        self.root, self.profile = self.fixture.root, self.fixture.profile
        self.profile['google_callback_origin'] = self.profile['admin_origin']
        self.fixture._refresh_manifest_and_receipt()
        self.settings = {**PROVIDER_SETTINGS, 'SMTP_HOST': 'smtp.mx.cloudflare.net', 'SMTP_PORT': '465',
                         'SMTP_USER': 'api_token', 'SMTP_PASS': PASSWORD,
                         'SMTP_ADMIN_EMAIL': 'selected-sender@example.test', 'SMTP_SENDER_NAME': 'Selected sender'}
        self.functions = {'UNRELATED_FUNCTION_SETTING': 'preserved-function-value'}
        self.seal()
        self.workspace = self.fixture.parent / 'local-app'
        self.config = self.workspace / 'supabase/config.toml'
        self.config.parent.mkdir(parents=True)
        self.config.write_text(CONFIG)
        self.private = self.config.parent / 'private/application.env'
        self.private.parent.mkdir()
        self.private.write_text('EXISTING_AUTH_SECRET=synthetic-existing-secret\n')
        self.private.chmod(0o600)
        self.before = self.private.read_bytes()
        self.output = self.fixture.parent / 'candidate'

    def seal(self):
        (self.root / 'private/provider-settings.json').write_text(json.dumps(self.settings))
        (self.root / 'private/functions.env').write_text(dotenv(self.functions))
        seal_configuration(self.root)

    def plan(self, **kwargs):
        return a.plan(self.root, self.config, **kwargs)

    def production(self):
        self.profile['environment'] = 'production'
        self.fixture._refresh_manifest_and_receipt()
        self.settings.update(TURNSTILE_SITE_KEY=SITE_KEY, TURNSTILE_SECRET_KEY=CAPTCHA_SECRET)
        self.config.write_text(CONFIG.replace('[auth.hook.send_sms]\nenabled = true',
                                             '[auth.hook.send_sms]\nenabled = false'))
        self.seal()

    def test_plan_has_no_side_effects_or_secret_output(self):
        before = self.config.read_bytes()
        with patch('subprocess.run') as run:
            selected = self.plan()
            run.assert_not_called()
        report = selected.describe()
        self.assertTrue(report['plan_only'])
        self.assertFalse(report['runtime_changed']); self.assertFalse(report['configuration_changed'])
        self.assertNotIn(PASSWORD, json.dumps(report)); self.assertNotIn(PASSWORD, repr(selected))
        self.assertFalse(self.output.exists()); self.assertEqual(self.config.read_bytes(), before)
        self.assertEqual(self.private.read_bytes(), self.before)

    def test_protected_updates_pin_auth_mount_and_preserve_identity_and_provider_policies(self):
        selected = self.plan(callbacks=(self.profile['admin_origin'] + '/recovery',))
        report = selected.export(self.output)
        updates = json.loads((self.output / 'config-updates.json').read_text())
        self.assertEqual(updates['api'], {'external_url': self.profile['supabase_origin']})
        for key in ('external_url', 'jwt_issuer'):
            self.assertEqual(updates['auth'][key], self.profile['supabase_origin'] + '/auth/v1')
        self.assertEqual(updates['auth']['site_url'], self.profile['public_origin'])
        self.assertEqual(updates['auth']['additional_redirect_urls'], sorted([
            self.profile['admin_origin'], self.profile['public_origin'], self.profile['admin_origin'] + '/recovery',
            self.profile['google_callback_origin'] + '/functions/v1/collect-api/v1/auth/google/callback']))
        self.assertEqual(updates['edge_runtime'], {'enabled': False})
        self.assertEqual(updates['auth.email.smtp']['pass'], a.SMTP_REFERENCE)
        self.assertEqual(updates['auth.email.smtp']['port'], 465)
        self.assertEqual(updates['auth.email'], {'otp_expiry': 1800})
        original = tomllib.loads(CONFIG)
        merged = copy.deepcopy(original)
        for section, fields in updates.items():
            target = merged
            for segment in section.split('.'):
                target = target.setdefault(segment, {})
            target.update(fields)
        self.assertEqual(merged['auth']['external'], original['auth']['external'])
        self.assertEqual(merged['auth']['hook'], original['auth']['hook'])
        self.assertEqual(merged['auth']['sms'], original['auth']['sms'])
        self.assertEqual(merged['auth']['email']['template'], original['auth']['email']['template'])
        for key in ('signing_keys_path', 'jwt_secret', 'publishable_key', 'secret_key', 'enable_signup'):
            self.assertEqual(merged['auth'][key], original['auth'][key])
        self.assertEqual(merged['edge_runtime']['secrets'], original['edge_runtime']['secrets'])
        self.assertEqual((self.output / 'application-env.append').read_text(), a.SMTP_VARIABLE + '=' + PASSWORD + '\n')
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        for name in report['candidate_files']:
            self.assertEqual((self.output / name).stat().st_mode & 0o777, 0o600)
        self.assertNotIn(PASSWORD, json.dumps(report)); self.assertNotIn(PASSWORD, json.dumps(updates))
        self.assertEqual(self.private.read_bytes(), self.before)
        self.assertEqual(self.config.read_text(), CONFIG)

    def test_production_projects_gotrue_captcha_and_disables_public_signup_without_changing_identity(self):
        self.production()
        self.functions['TURNSTILE_SITE_KEY'] = SITE_KEY
        self.seal()
        original = tomllib.loads(self.config.read_text())
        selected = self.plan(); report = selected.export(self.output)
        updates = json.loads((self.output / 'config-updates.json').read_text())
        self.assertEqual(updates['auth.captcha'], {
            'enabled': True, 'provider': 'turnstile', 'secret': 'env(COLLECT_AUTH_TURNSTILE_SECRET)'})
        self.assertIs(updates['auth']['enable_signup'], False)
        self.assertIs(updates['auth']['enable_anonymous_sign_ins'], False)
        self.assertEqual(updates['auth.email'], {'enable_signup': True, 'otp_expiry': 1800})
        merged = copy.deepcopy(original)
        for section, fields in updates.items():
            target = merged
            for segment in section.split('.'):
                target = target.setdefault(segment, {})
            target.update(fields)
        for key in ('signing_keys_path', 'jwt_secret', 'publishable_key', 'secret_key'):
            self.assertEqual(merged['auth'][key], original['auth'][key])
        for key in ('external', 'hook'):
            self.assertEqual(merged['auth'][key], original['auth'][key])
        self.assertEqual(merged['auth']['email']['template'], original['auth']['email']['template'])
        self.assertEqual(merged['auth']['sms'], original['auth']['sms'])
        self.assertIs(merged['auth']['email']['enable_confirmations'], True)
        self.assertEqual(merged['edge_runtime']['secrets'], original['edge_runtime']['secrets'])
        self.assertTrue(report['gotrue_turnstile_enabled'])
        self.assertTrue(report['production_public_signup_disabled'])
        self.assertEqual(report['turnstile_environment_fields'], [a.TURNSTILE_VARIABLE])
        self.assertIn('qualify_native_and_admin_captcha_flow_before_commissioning', report['requires_operator'])
        self.assertEqual(self.private.read_bytes(), self.before)
        for secret in (PASSWORD, CAPTCHA_SECRET):
            self.assertNotIn(secret, json.dumps(updates)); self.assertNotIn(secret, json.dumps(report))
            self.assertNotIn(secret, repr(selected))
        for name in report['candidate_files']:
            self.assertEqual((self.output / name).stat().st_mode & 0o777, 0o600)

    def test_disabled_email_provider_is_reenabled_without_opening_public_signup(self):
        self.production()
        text = self.config.read_text().replace('enable_signup = true', 'enable_signup = false', 1)
        text = text.replace('[auth.email]\nenable_signup = true', '[auth.email]\nenable_signup = false')
        self.config.write_text(text)
        original = tomllib.loads(text)
        selected = self.plan(); selected.export(self.output)
        updates = json.loads((self.output / 'config-updates.json').read_text())
        merged = copy.deepcopy(original)
        for section, fields in updates.items():
            target = merged
            for segment in section.split('.'):
                target = target.setdefault(segment, {})
            target.update(fields)
        # CLI 2.122.0 gotrue.service.ts: global signup is negated, while
        # email.enable_signup directly enables the WHOLE email provider.
        # GoTrue 2.197.0 MagicLink rejects existing-user OTP with422 when the
        # latter is false; global DisableSignup independently blocks new users.
        projected = {
            'GOTRUE_DISABLE_SIGNUP': str(not merged['auth']['enable_signup']).lower(),
            'GOTRUE_EXTERNAL_EMAIL_ENABLED': str(merged['auth']['email']['enable_signup']).lower(),
            'GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED': str(merged['auth']['enable_anonymous_sign_ins']).lower(),
        }
        self.assertEqual(projected, {'GOTRUE_DISABLE_SIGNUP': 'true',
                                     'GOTRUE_EXTERNAL_EMAIL_ENABLED': 'true',
                                     'GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED': 'false'})
        self.assertEqual(merged['auth']['email']['template'], original['auth']['email']['template'])
        self.assertEqual(merged['auth']['email']['enable_confirmations'], original['auth']['email']['enable_confirmations'])
        self.assertEqual(merged['auth']['captcha']['secret'], a.TURNSTILE_REFERENCE)
        self.assertEqual(merged['auth']['email']['smtp']['pass'], a.SMTP_REFERENCE)
        self.assertEqual(self.config.read_text(), text)
        self.assertEqual(self.private.read_bytes(), self.before)

    def test_exported_secret_references_resolve_with_pinned_cli_verbatim_env_capture(self):
        self.production(); self.plan().export(self.output)
        updates = json.loads((self.output / 'config-updates.json').read_text())
        values = dict(line.split('=', 1) for line in (self.output / 'application-env.append').read_text().splitlines())
        self.assertEqual(values, {a.SMTP_VARIABLE: PASSWORD, a.TURNSTILE_VARIABLE: CAPTCHA_SECRET})
        # CLI 2.122.0 lib/env.ts takes match[1] verbatim, without stripping quotes.
        for reference, expected in ((updates['auth.email.smtp']['pass'], PASSWORD),
                                    (updates['auth.captcha']['secret'], CAPTCHA_SECRET)):
            match = re.fullmatch(r'env\(([A-Z_][A-Z0-9_]*)\)', reference)
            self.assertIsNotNone(match); self.assertEqual(values[match[1]], expected)
        self.assertNotIn('"' + a.SMTP_VARIABLE + '"', values)

    def test_production_requires_real_turnstile_pair_and_rejects_public_test_credentials(self):
        self.production()
        for key, value, code in (
                ('TURNSTILE_SITE_KEY', '', 'turnstile_configuration_required'),
                ('TURNSTILE_SECRET_KEY', '', 'turnstile_configuration_required'),
                ('TURNSTILE_SITE_KEY', 'bad site key', 'turnstile_configuration_required'),
                ('TURNSTILE_SECRET_KEY', CAPTCHA_SECRET + '\nSECOND=entry', 'turnstile_configuration_required'),
                ('TURNSTILE_SITE_KEY', next(iter(a.TURNSTILE_TEST_SITE_KEYS)), 'production_turnstile_required'),
                ('TURNSTILE_SECRET_KEY', next(iter(a.TURNSTILE_TEST_SECRET_KEYS)), 'production_turnstile_required')):
            original = self.settings[key]
            with self.subTest(field=key, code=code):
                self.settings[key] = value; self.seal()
                with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_' + code + '$'):
                    self.plan()
                self.assertFalse(self.output.exists())
            self.settings[key] = original

    def test_turnstile_secret_cannot_enter_edge_or_function_environment_under_any_alias(self):
        self.production(); original = self.config.read_text()
        for entry in ('COLLECT_AUTH_TURNSTILE_SECRET = "alias"',
                      'TURNSTILE_SECRET_KEY = "alias"',
                      'ALIAS = "env(COLLECT_AUTH_TURNSTILE_SECRET)"',
                      'ALIAS = "Bearer ' + CAPTCHA_SECRET + '"'):
            with self.subTest(kind=entry.split('=')[0]):
                self.config.write_text(original.replace('[edge_runtime.secrets]', '[edge_runtime.secrets]\n' + entry))
                with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_turnstile_server_boundary_required$'):
                    self.plan()
        self.config.write_text(original)
        for name, value in (('TURNSTILE_SECRET_KEY', ''), (a.TURNSTILE_VARIABLE, 'alias'),
                            ('GOTRUE_SECURITY_CAPTCHA_SECRET', 'alias'),
                            ('ALIAS', CAPTCHA_SECRET), ('ALIAS', 'env(COLLECT_AUTH_TURNSTILE_SECRET)')):
            with self.subTest(field=name):
                self.functions[name] = value; self.seal()
                with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_turnstile_server_boundary_required$'):
                    self.plan()
                del self.functions[name]

    def test_production_rejects_conflicting_enabled_provider_policy_instead_of_silently_changing_it(self):
        self.production(); original = self.config.read_text()
        for name, value in (('AUTH_ANONYMOUS_ENABLED', 'true'), ('AUTH_SMS_ENABLED', 'true'),
                            ('AUTH_WHATSAPP_ENABLED', 'true'), ('GOOGLE_AUTH_ENABLED', 'true'),
                            ('GOOGLE_AUTH_ENABLED', 'unsupported')):
            previous = self.settings[name]
            with self.subTest(field=name):
                self.settings[name] = value; self.seal()
                with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_private_provider_policy_required$'):
                    self.plan()
            self.settings[name] = previous
        self.seal()
        for config in (original.replace('[auth.hook.send_sms]\nenabled = false', '[auth.hook.send_sms]\nenabled = true'),
                       original + '\n[auth.sms.twilio]\nenabled = true\n',
                       original + '\n[auth.external.apple]\nenabled = true\n'):
            self.config.write_text(config)
            with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_private_provider_policy_required$'):
                self.plan()

    def test_unapproved_query_wildcard_traversal_or_foreign_callback_refused(self):
        for value in ('https://outside.example/callback', self.profile['admin_origin'] + '/**',
                      self.profile['admin_origin'] + '/callback?state=untrusted',
                      self.profile['admin_origin'] + '/callback#fragment',
                      self.profile['admin_origin'] + '/a/../callback',
                      self.profile['admin_origin'] + '/%2fcallback', 'http://127.0.0.1/callback'):
            with self.subTest(value=value), self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_callback_invalid$'):
                self.plan(callbacks=(value,))

    def test_google_policy_is_preserved_and_state_bearing_redirect_remains_explicit_gate(self):
        self.config.write_text(CONFIG.replace('[auth.external.google]\nenabled = false', '[auth.external.google]\nenabled = true'))
        selected = self.plan(); selected.export(self.output)
        updates = json.loads((self.output / 'config-updates.json').read_text())
        self.assertEqual(updates['auth.external.google'], {
            'redirect_uri': self.profile['supabase_origin'] + '/auth/v1/callback'})
        self.assertTrue(selected.describe()['google_state_redirect_match_requires_qualification'])
        self.assertIn(self.profile['admin_origin'] + '/functions/v1/collect-api/v1/auth/google/callback',
                      updates['auth']['additional_redirect_urls'])

    def test_google_callback_on_other_application_origin_is_refused(self):
        self.profile['google_callback_origin'] = self.profile['member_api_origin']
        self.fixture._refresh_manifest_and_receipt(); self.seal()
        self.config.write_text(CONFIG.replace('[auth.external.google]\nenabled = false', '[auth.external.google]\nenabled = true'))
        with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_google_admin_origin_required$'):
            self.plan()

    def test_existing_send_email_hook_cannot_silently_shadow_smtp(self):
        self.config.write_text(CONFIG + '\n[auth.hook.send_email]\nenabled = true\nuri = "https://hook.example"\n')
        with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_send_email_hook_conflict$'):
            self.plan()

    def test_missing_password_incompatible_smtp_or_invalid_sender_is_refused(self):
        for key, value, error in (
            ('SMTP_PASS', '', 'protected_smtp_password_required'),
            ('SMTP_PASS', PASSWORD + '\nOTHER=oops', 'protected_smtp_password_required'),
            ('SMTP_HOST', 'smtp.other.example', 'cloudflare_implicit_tls_required'),
            ('SMTP_PORT', '587', 'cloudflare_implicit_tls_required'),
            ('SMTP_USER', 'other', 'cloudflare_implicit_tls_required'),
            ('SMTP_ADMIN_EMAIL', 'not-an-address', 'sender_required'),
            ('SMTP_SENDER_NAME', 'bad\r\nheader', 'sender_required')):
            original = self.settings[key]
            with self.subTest(key=key, value=value):
                self.settings[key] = value; self.seal()
                with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_' + error + '$'):
                    self.plan()
            self.settings[key] = original

    def test_smtp_secret_cannot_enter_edge_or_function_environment(self):
        for entry in ('COLLECT_AUTH_SMTP_PASS = "alias"', 'ALIAS = \'env("COLLECT_AUTH_SMTP_PASS")\''):
            self.config.write_text(CONFIG.replace('[edge_runtime.secrets]', '[edge_runtime.secrets]\n' + entry))
            with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_smtp_server_boundary_required$'):
                self.plan()
        self.config.write_text(CONFIG)
        for name, value in (('SMTP_PASS', 'alias'), ('COLLECT_AUTH_SMTP_PASS', PASSWORD), ('ALIAS', PASSWORD)):
            self.functions[name] = value; self.seal()
            with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_smtp_server_boundary_required$'):
                self.plan()
            del self.functions[name]

    def test_changed_original_config_or_provider_rejects_stale_plan(self):
        selected = self.plan()
        self.config.write_text(CONFIG + '\n# changed after review\n')
        with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_plan_changed$'):
            selected.export(self.output)
        self.assertFalse(self.output.exists())
        self.config.write_text(CONFIG); selected = self.plan()
        self.settings['SMTP_PASS'] += '-rotated'; self.seal()
        with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_plan_changed$'):
            selected.export(self.output)
        self.assertFalse(self.output.exists())

    def test_changed_sealed_source_fails_before_candidate_output(self):
        selected = self.plan()
        (self.root / 'source/supabase/functions/fixture.js').write_text('// changed')
        with self.assertRaisesRegex(ValueError, '^Source file changed$'):
            selected.export(self.output)
        self.assertFalse(self.output.exists())

    def test_no_overwrite_workspace_output_symlink_or_public_parent(self):
        selected = self.plan()
        selected.export(self.output)
        original = (self.output / 'application-env.append').read_bytes()
        for output in (self.output, self.workspace / 'candidate', self.root / 'private/candidate'):
            with self.subTest(output=output), self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_new_protected_output_required$'):
                selected.export(output)
        self.assertEqual((self.output / 'application-env.append').read_bytes(), original)
        public = self.fixture.parent / 'public'; public.mkdir(mode=0o755)
        with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_new_protected_output_required$'):
            selected.export(public / 'candidate')
        link = self.fixture.parent / 'link'; link.symlink_to(self.output, target_is_directory=True)
        with self.assertRaisesRegex(a.AuthPlanError, '^retained_auth_new_protected_output_required$'):
            selected.export(link / 'candidate')

    def test_cli_is_plan_only_and_failure_is_redacted(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch('subprocess.run') as run, redirect_stdout(stdout):
            code = a.main(['--release', str(self.root), '--cli-config', str(self.config)])
            run.assert_not_called()
        self.assertEqual(code, 0); self.assertNotIn(PASSWORD, stdout.getvalue())
        self.assertTrue(json.loads(stdout.getvalue())['plan_only'])
        stdout = io.StringIO()
        with patch.object(a, 'plan', side_effect=ValueError(PASSWORD)), redirect_stdout(stdout), redirect_stderr(stderr):
            code = a.main(['--release', str(self.root), '--cli-config', str(self.config)])
        self.assertEqual(code, 1); self.assertNotIn(PASSWORD, stderr.getvalue())
        self.assertEqual(stdout.getvalue(), ''); self.assertEqual(self.private.read_bytes(), self.before)


if __name__ == '__main__':
    unittest.main()
