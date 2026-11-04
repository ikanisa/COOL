"""Focused source-only checks for the generated self-hosted SMS policy."""
import unittest

from scripts.self_hosted.prepare import PROVIDER_SETTINGS, build_compose, verify_vendor


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


if __name__ == '__main__':
    unittest.main()
