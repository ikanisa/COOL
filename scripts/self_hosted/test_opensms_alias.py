"""Synthetic checks for the generated OpenSMS device-route candidate.

These exercise the emitted method/URI patterns, not a running Caddy server.
The pinned Caddy, Envoy and Edge route still require separate qualification.
"""
import re
import unittest
from urllib.parse import unquote

from scripts.self_hosted.prepare import CONFIGURATION_FILES, caddyfile


PROFILE = {
    'format': 'collect.deployment.v1',
    'id': 'synthetic',
    'mode': 'self_hosted',
    'environment': 'qualification',
    'supabase_origin': 'https://supabase.collect.example',
    'member_api_origin': 'https://api.collect.example',
    'admin_origin': 'https://admin.collect.example',
    'public_origin': 'https://collect.example',
    'google_callback_origin': 'https://admin.collect.example',
}

# Frozen output of the prior release generator for these synthetic origins.
_LEGACY_OUTPUT = '''{
 admin off
__EMAIL__}
admin.collect.example {
__TLS__ request_body {
  max_size 16MB
 }
 header Strict-Transport-Security "max-age=31536000"
 reverse_proxy web:8080
}

api.collect.example {
__TLS__ request_body {
  max_size 16MB
 }
 header Strict-Transport-Security "max-age=31536000"
 reverse_proxy web:8080
}

collect.example {
__TLS__ request_body {
  max_size 16MB
 }
 header Strict-Transport-Security "max-age=31536000"
 reverse_proxy web:8080
}

supabase.collect.example {
__TLS__ request_body {
  max_size 16MB
 }
 header Strict-Transport-Security "max-age=31536000"
 @auth path /auth/v1/*
 handle @auth {
  request_body {
   max_size 16KB
  }
  reverse_proxy web:8080
 }
 @api path /rest/v1/* /storage/v1/* /realtime/v1/* /functions/v1/* /graphql/v1
 handle @api {
  reverse_proxy api-gw:8000
 }
 handle {
  respond 404
 }
}
'''


class OpenSmsAliasConfiguration(unittest.TestCase):
    def setUp(self):
        self.generated = caddyfile(PROFILE, 'internal', None, _qualify_device_alias=True)
        line = next(line for line in self.generated.splitlines() if line.startswith(' @device `'))
        # Characterize the exact patterns generated for Caddy; Python regexp is
        # only a source-level check, not proof of CEL or upstream behavior.
        self.rules = re.findall(
            r"method\('(GET|POST)'\) && \{http\.request\.orig_uri\}\.matches\('([^']+)'\)",
            line,
        )
        self.assertEqual([method for method, _ in self.rules], ['POST', 'GET', 'GET'])

    def admitted(self, method, target):
        return any(verb == method and re.fullmatch(pattern, target) is not None
                   for verb, pattern in self.rules)

    def test_default_release_generation_matches_prior_bytes(self):
        variants = (
            (PROFILE, 'internal', None, '', ' tls internal\n'),
            ({**PROFILE, 'environment': 'production'}, 'acme', 'ops@example.com',
             ' email ops@example.com\n', ''),
        )
        for profile, tls, email, expected_email, expected_tls in variants:
            with self.subTest(tls=tls):
                expected = _LEGACY_OUTPUT.replace('__EMAIL__', expected_email).replace('__TLS__', expected_tls)
                self.assertEqual(caddyfile(profile, tls, email), expected)
                self.assertEqual(caddyfile(profile, tls, email, _qualify_device_alias=False), expected)
                self.assertNotIn('@device', expected)

    def test_only_the_supabase_site_contains_the_ordered_device_adapter(self):
        text = self.generated
        self.assertEqual(text.count(' @device `'), 1)
        self.assertEqual(text.count(' @v1_invalid `'), 1)
        api = text.index('\nsupabase.collect.example {\n') + 1
        for host in ('admin.collect.example', 'api.collect.example', 'collect.example'):
            start = text.index('\n' + host + ' {\n') + 1
            end = text.index('\n}\n', start)
            block = text[start:end]
            self.assertIn('reverse_proxy web:8080', block)
            self.assertNotIn('@device', block)
        section = text[api:]
        self.assertLess(section.index('handle @device'), section.index('handle @v1_invalid'))
        self.assertLess(section.index('handle @v1_invalid'), section.index('handle @auth'))
        self.assertLess(section.index('handle @auth'), section.index('handle @api'))
        self.assertIn('route {\n', section)
        self.assertIn('uri path_regexp ^ /functions/v1/collect-sms\n', section)
        self.assertIn('reverse_proxy api-gw:8000\n', section)
        self.assertNotIn('header_up Authorization', section)
        self.assertNotIn('uri query', section)
        self.assertIn('@auth path /auth/v1/*', section)
        self.assertIn('max_size 16KB', section)
        self.assertIn('@api path /rest/v1/* /storage/v1/* /realtime/v1/* /functions/v1/* /graphql/v1', section)
        self.assertIn('Caddyfile', CONFIGURATION_FILES)

    def test_five_device_operations_and_encoded_collect_ids_are_admitted(self):
        routes = [
            ('POST', '/v1/device/registration'),
            ('GET', '/v1/device/jobs?limit=10&cursor=a%2Fb&cursor=two'),
            ('POST', '/v1/device/acceptances'),
            ('POST', '/v1/device/events'),
            ('GET', '/v1/device/messages/app%3Asbauth%3A' + 'a' * 64 + '/permit?parts_total=1'),
            ('GET', '/v1/device/messages/%61pp%3asbauth%3a' + 'a' * 64 + '/permit?parts_total=2'),
            ('GET', '/v1/device/messages/app%3Acollect-receipt%3A001-002/permit'),
            ('GET', '/v1/device/messages/' + 'a' * 200 + '/permit'),
        ]
        for method, target in routes:
            with self.subTest(method=method, target=target):
                self.assertTrue(self.admitted(method, target))

    def test_unsupported_methods_routes_and_ambiguous_ids_are_rejected(self):
        routes = [
            ('GET', '/v1/device/registration'),
            ('POST', '/v1/device/jobs'),
            ('GET', '/v1/device/events'),
            ('GET', '/v1/device/acceptances'),
            ('POST', '/v1/device/messages/a/permit'),
            ('HEAD', '/v1/device/jobs'),
            ('OPTIONS', '/v1/device/registration'),
            ('POST', '/v1/device/inbound'),
            ('GET', '/v1/device/recipient-policy'),
            ('POST', '/v1/momo/gateway/ingest'),
            ('GET', '/v1/device/jobs/extra'),
            ('GET', '/v1/device//jobs'),
            ('GET', '/v1/device/../device/jobs'),
            ('GET', '/v1/device/%2e%2e/functions/v1/collect-api'),
            ('GET', '/V1/device/jobs'),
            ('GET', '/v%31/device/jobs'),
            ('GET', '/v1/device/messages//permit'),
            ('GET', '/v1/device/messages/a%2Fb/permit'),
            ('GET', '/v1/device/messages/a%5Cb/permit'),
            ('GET', '/v1/device/messages/a%252Fb/permit'),
            ('GET', '/v1/device/messages/a%2/permit'),
            ('GET', '/v1/device/messages/a%20b/permit'),
            ('GET', '/v1/device/messages/' + 'a' * 201 + '/permit'),
        ]
        for method, target in routes:
            with self.subTest(method=method, target=target):
                self.assertFalse(self.admitted(method, target))

    def test_decoded_v1_aliases_are_caught_before_existing_api_fallback(self):
        line = next(line for line in self.generated.splitlines() if line.startswith(' @v1_invalid `'))
        match = re.fullmatch(r" @v1_invalid `\{http\.request\.uri\.path\}\.matches\('([^']+)'\)`", line)
        self.assertIsNotNone(match)
        pattern = match.group(1)
        for target in (
            '/v1/device/inbound',
            '/v1/device/../../functions/v1/collect-api/v1/momo/gateway/ingest',
            '/v%31/device/%2e%2e/functions/v1/collect-api',
            '/v1%2Fdevice/jobs',
            '//v1/device/jobs',
            '/V1/device/jobs',
        ):
            with self.subTest(target=target):
                self.assertIsNotNone(re.search(pattern, unquote(target.partition('?')[0])))

    def test_production_tls_and_existing_canonical_routes_remain_configured(self):
        production = caddyfile({**PROFILE, 'environment': 'production'}, 'acme', 'ops@example.com',
                               _qualify_device_alias=True)
        self.assertIn(' email ops@example.com\n', production)
        self.assertNotIn(' tls internal\n', production)
        self.assertEqual(production.count(' @device `'), 1)
        self.assertIn('@auth path /auth/v1/*', production)
        self.assertIn('@api path /rest/v1/* /storage/v1/* /realtime/v1/* /functions/v1/* /graphql/v1', production)
        self.assertIn('handle {\n   respond 404\n  }', production)


if __name__ == '__main__':
    unittest.main()
