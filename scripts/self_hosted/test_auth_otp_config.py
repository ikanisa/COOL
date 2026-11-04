"""Focused source-only checks for the generated self-hosted SMS policy."""
import json
from pathlib import Path
import tempfile
import unittest

from scripts.self_hosted.prepare import PROVIDER_SETTINGS, build_compose, verify_vendor
from scripts.self_hosted.configure import configure, validated_settings


PROFILE = {
    'format': 'collect.deployment.v1',
    'id': 'synthetic-sms',
    'mode': 'self_hosted',
    'environment': 'qualification',
    'supabase_origin': 'https://supabase.collect.example',
    'member_api_origin': 'https://api.collect.example',
    'admin_origin': 'https://admin.collect.example',
    'public_origin': 'https://collect.example',
    'google_callback_origin': 'https://admin.collect.example',
}


class AuthOtpConfiguration(unittest.TestCase):
    def test_generated_auth_pins_sms_timing_without_enabling_admission(self):
        images = verify_vendor()
        expected = {
            'GOTRUE_SMS_OTP_LENGTH': '6',
            'GOTRUE_SMS_OTP_EXP': '300',
            'GOTRUE_DISABLE_SIGNUP': '${DISABLE_SIGNUP}',
            'GOTRUE_EXTERNAL_PHONE_ENABLED': '${ENABLE_PHONE_SIGNUP}',
            'GOTRUE_SMS_AUTOCONFIRM': 'false',
            'GOTRUE_SMS_PROVIDER': '${GOTRUE_SMS_PROVIDER}',
            'GOTRUE_HOOK_SEND_SMS_ENABLED': '${GOTRUE_HOOK_SEND_SMS_ENABLED}',
            'GOTRUE_HOOK_SEND_SMS_URI': 'http://functions:9000/send-sms-hook',
            'GOTRUE_HOOK_SEND_SMS_SECRETS': 'v1,whsec_${COLLECT_SMS_HOOK_SECRET}',
            'GOTRUE_SECURITY_CAPTCHA_ENABLED': '${GOTRUE_SECURITY_CAPTCHA_ENABLED}',
        }
        for environment in ('qualification', 'production'):
            with self.subTest(environment=environment):
                profile = {**PROFILE, 'environment': environment}
                auth = build_compose(profile, images)['services']['auth']['environment']
                self.assertEqual({key: auth[key] for key in expected}, expected)

        self.assertEqual(
            {key: PROVIDER_SETTINGS[key] for key in (
                'AUTH_MEMBER_REGISTRATION_ENABLED', 'AUTH_SMS_ENABLED',
                'AUTH_WHATSAPP_ENABLED', 'AUTH_PHONE_DELIVERY_MODE',
                'COLLECT_SMS_ENABLED', 'DISPATCH_PAUSED',
            )},
            {
                'AUTH_MEMBER_REGISTRATION_ENABLED': 'false',
                'AUTH_SMS_ENABLED': 'false',
                'AUTH_WHATSAPP_ENABLED': 'false',
                'AUTH_PHONE_DELIVERY_MODE': 'opensms_hook',
                'COLLECT_SMS_ENABLED': 'false',
                'DISPATCH_PAUSED': 'true',
            },
        )

    def test_enabled_sms_hook_refuses_the_receipt_application_even_when_disabled(self):
        settings = {
            **PROVIDER_SETTINGS,
            'AUTH_SMS_ENABLED': 'true',
            'COLLECT_SMS_ENABLED': 'true',
            'COLLECT_SMS_APPROVAL_SHA256': 'a' * 64,
            'OPENSMS_BASE_URL': PROFILE['supabase_origin'] + '/functions/v1/collect-sms',
            'OPENSMS_APPLICATION_ID': 'otp-app',
            'OPENSMS_APPLICATION_TOKEN': 'app_' + 'a' * 32,
            'OPENSMS_RECEIPT_APPLICATION_ID': 'otp-app',
            'OPENSMS_RECEIPT_APPLICATION_TOKEN': 'app_' + 'b' * 32,
            'COLLECT_RECEIPT_SMS_ENABLED': 'false',
        }
        with self.assertRaisesRegex(ValueError, 'distinct'):
            validated_settings(settings, PROFILE, 'b' * 64)
        for receipt_id in ('', 'receipt-app'):
            with self.subTest(receipt_id=receipt_id):
                validated_settings({**settings, 'OPENSMS_RECEIPT_APPLICATION_ID': receipt_id}, PROFILE, 'b' * 64)
        # Incomplete credentials may still be staged while the OTP hook is disabled.
        validated_settings({**settings, 'AUTH_SMS_ENABLED': 'false'}, PROFILE, 'b' * 64)

    def test_configured_turnstile_site_key_matches_mobile_and_admin_key_shape(self):
        settings = {**PROVIDER_SETTINGS, 'TURNSTILE_SECRET_KEY': 'synthetic-private'}
        for site_key in ('a' * 10, 'a' * 200, '1x00000000000000000000AA', 'synthetic_site-key'):
            with self.subTest(valid_length=len(site_key)):
                validated_settings({**settings, 'TURNSTILE_SITE_KEY': site_key}, PROFILE, 'b' * 64)
        for site_key in ('a' * 9, 'a' * 201, 'synthetic key', 'synthetic.key', 'x' * 10 + '\n'):
            with self.subTest(invalid_length=len(site_key)), self.assertRaisesRegex(ValueError, 'site key'):
                validated_settings({**settings, 'TURNSTILE_SITE_KEY': site_key}, PROFILE, 'b' * 64)
        validated_settings(dict(PROVIDER_SETTINGS), PROFILE, 'b' * 64)

    def test_invalid_settings_do_not_replace_existing_configuration(self):
        sms = {
            **PROVIDER_SETTINGS,
            'AUTH_SMS_ENABLED': 'true',
            'COLLECT_SMS_ENABLED': 'true',
            'COLLECT_SMS_APPROVAL_SHA256': 'a' * 64,
            'OPENSMS_BASE_URL': PROFILE['supabase_origin'] + '/functions/v1/collect-sms',
            'OPENSMS_APPLICATION_ID': 'otp-app',
            'OPENSMS_APPLICATION_TOKEN': 'app_' + 'a' * 32,
            'OPENSMS_RECEIPT_APPLICATION_ID': 'otp-app',
        }
        captcha = {**PROVIDER_SETTINGS, 'TURNSTILE_SITE_KEY': '!', 'TURNSTILE_SECRET_KEY': 'synthetic-private'}
        for case, settings, error in (('sms', sms, 'distinct'), ('captcha', captcha, 'site key')):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                release = Path(directory)
                private = release / 'private'
                private.mkdir()
                (release / 'release.json').write_text(json.dumps({'profile': PROFILE, 'source_sha256': 'b' * 64}))
                source = private / 'provider-settings.json'
                source.write_text(json.dumps(settings))
                source.chmod(0o600)
                outputs = ('private/stack.env', 'private/functions.env', 'public.env', 'client.json', 'private/configuration.json')
                for name in outputs:
                    (release / name).write_text('retained synthetic output')
                with self.assertRaisesRegex(ValueError, error):
                    configure(release)
                for name in outputs:
                    self.assertEqual((release / name).read_text(), 'retained synthetic output')
                self.assertEqual(list(release.rglob('*.next')), [])


if __name__ == '__main__':
    unittest.main()
