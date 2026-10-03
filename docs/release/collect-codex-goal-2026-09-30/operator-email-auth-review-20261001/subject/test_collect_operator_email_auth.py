#!/usr/bin/env python3
"""Exercise actual narrow update orchestration using a controlled transport."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("email_setup", ROOT / "scripts/collect_operator_email_auth.py")
S = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(S)
CANARY = "smtp_secret_must_never_appear_123"
TEMPLATE = '<p>Code: {{ .Token }}</p>'


class Transport:
    def __init__(self):
        self.config = {"external_email_enabled": False, "external_phone_enabled": True,
                       "smtp_host": "smtp.example.test", "smtp_admin_email": "auth@example.test",
                       "smtp_user": "auth", "smtp_pass": CANARY, "smtp_port": 587,
                       "hook_send_sms_secrets": CANARY, "hook_send_sms_enabled": True,
                       "disable_signup": True, "uri_allow_list": "https://example.test"}
        self.calls = []
        self.status = 200
        self.fail_after_patch = False
        self.change_unrelated = False

    def __call__(self, method, token, payload=None):
        self.calls.append((method, copy.deepcopy(payload)))
        if self.status != 200:
            return self.status, json.dumps({"error": CANARY}).encode()
        if method == "PATCH":
            self.config.update(payload)
            if self.change_unrelated:
                self.config["external_phone_enabled"] = False
        elif len(self.calls) > 2 and self.fail_after_patch:
            raise S.AuthSetupError("TRANSPORT_OUTCOME_UNCONFIRMED")
        return 200, json.dumps(self.config).encode()


class NarrowEmailAuthTest(unittest.TestCase):
    def test_authorized_apply_preserves_unrelated_values_and_redacts_credentials(self):
        t = Transport()
        original = copy.deepcopy(t.config)
        e = S.execute("apply", "sbp_test", TEMPLATE, t)
        self.assertEqual(e["status"], "CONFIGURED_READBACK_VERIFIED")
        self.assertEqual([c[0] for c in t.calls], ["GET", "PATCH", "GET"])
        self.assertTrue(e["configuration_update_verified"])
        self.assertNotIn(CANARY, json.dumps(e))
        self.assertEqual(e["otp_requests"], 0)
        payload = t.calls[1][1]
        for key, value in original.items():
            if key not in payload:
                self.assertEqual(t.config[key], value)
        self.assertEqual(payload["mailer_templates_magic_link_content"], TEMPLATE)
        self.assertTrue(t.config["external_email_enabled"])
        self.assertFalse(t.config["mailer_autoconfirm"])

    def test_403_stops_before_configuration_or_user_mutation(self):
        t = Transport(); t.status = 403
        e = S.execute("apply", "sbp_test", TEMPLATE, t)
        self.assertEqual(e["status"], "MANAGEMENT_ACCESS_DENIED")
        self.assertEqual(len(t.calls), 1)
        self.assertFalse(e["configuration_update_attempted"])
        self.assertNotIn(CANARY, json.dumps(e))

    def test_check_is_read_only_even_with_ready_transport(self):
        t = Transport()
        e = S.execute("check", "sbp_test", TEMPLATE, t)
        self.assertEqual(e["status"], "READ_SUCCEEDED")
        self.assertEqual([c[0] for c in t.calls], ["GET"])
        self.assertFalse(e["configuration_update_attempted"])

    def test_missing_transport_or_phone_blocks_apply(self):
        for missing in ("smtp_pass", "external_phone_enabled"):
            with self.subTest(missing=missing):
                t = Transport(); t.config.pop(missing)
                e = S.execute("apply", "sbp_test", TEMPLATE, t)
                self.assertFalse(e["configuration_update_attempted"])
                self.assertEqual(len(t.calls), 1)

    def test_existing_https_email_hook_is_preserved(self):
        t = Transport(); t.config.pop("smtp_pass")
        t.config.update(hook_send_email_enabled=True,
                        hook_send_email_uri="https://example.test/send",
                        hook_send_email_secrets=CANARY)
        e = S.execute("apply", "sbp_test", TEMPLATE, t)
        self.assertTrue(e["configuration_update_verified"])
        self.assertNotIn("hook_send_email_uri", t.calls[1][1])

    def test_uncertain_readback_keeps_identity_and_never_retries_or_rolls_back(self):
        t = Transport(); t.fail_after_patch = True
        e = S.execute("apply", "sbp_test", TEMPLATE, t)
        self.assertTrue(e["configuration_outcome_uncertain"])
        self.assertFalse(e["configuration_update_verified"])
        self.assertEqual([c[0] for c in t.calls], ["GET", "PATCH", "GET"])

    def test_concurrent_unrelated_change_is_detected_without_blind_rollback(self):
        t = Transport(); t.change_unrelated = True
        e = S.execute("apply", "sbp_test", TEMPLATE, t)
        self.assertEqual(e["status"], "CONFIGURATION_READBACK_MISMATCH")
        self.assertEqual(e["unrelated_config_changed_keys"], ["external_phone_enabled"])
        self.assertEqual(len(t.calls), 3)

    def test_idempotent_config_read_does_not_repeat_patch(self):
        t = Transport(); t.config.update(S.desired_config(TEMPLATE))
        e = S.execute("apply", "sbp_test", TEMPLATE, t)
        self.assertEqual(e["status"], "ALREADY_CONFIGURED")
        self.assertEqual(len(t.calls), 1)

    def test_invalid_template_is_refused_before_request(self):
        t = Transport()
        with self.assertRaises(S.AuthSetupError):
            S.execute("apply", "sbp_test", "{{ .ConfirmationURL }}", t)
        self.assertFalse(t.calls)

    def test_malformed_success_response_is_not_configuration_acceptance(self):
        e = S.execute("apply", "sbp_test", TEMPLATE, lambda *a: (200, b'[]'))
        self.assertEqual(e["status"], "INVALID_CONFIG_RESPONSE")
        self.assertFalse(e["configuration_update_attempted"])

    def test_invalid_or_credential_embedded_email_hook_cannot_enable_auth(self):
        for uri in ("https://", "http://example.test/send", "https://private@example.test/send"):
            with self.subTest(uri=uri):
                t = Transport(); t.config.pop("smtp_pass")
                t.config.update(hook_send_email_enabled=True, hook_send_email_uri=uri,
                                hook_send_email_secrets=CANARY)
                e = S.execute("apply", "sbp_test", TEMPLATE, t)
                self.assertFalse(e["configuration_update_attempted"])

    def test_unsafe_token_file_and_symlink_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory); (home / ".supabase").mkdir()
            token = home / ".supabase/access-token"; token.write_text("sbp_synthetic")
            with patch.object(S.Path, "home", return_value=home), patch.dict(os.environ, {}, clear=True):
                token.chmod(0o644)
                with self.assertRaises(S.AuthSetupError): S.load_management_token()
                token.chmod(0o600)
                self.assertEqual(S.load_management_token(), "sbp_synthetic")
                target = home / "synthetic-secret"; token.rename(target); token.symlink_to(target)
                with self.assertRaises(S.AuthSetupError): S.load_management_token()

    def test_credential_header_injection_is_refused_before_network(self):
        with patch.dict(os.environ, {"SUPABASE_ACCESS_TOKEN": "sbp_test\r\nX-Canary: secret"}):
            with self.assertRaises(S.AuthSetupError): S.load_management_token()

    def test_redirect_policy_does_not_forward_management_credentials(self):
        redirect = S.NoRedirect()
        self.assertIsNone(redirect.redirect_request(None, None, 302, "", {}, "https://example.test"))


if __name__ == "__main__":
    unittest.main()
