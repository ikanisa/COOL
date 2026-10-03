#!/usr/bin/env python3
"""Exercise actual narrow update orchestration using a controlled transport."""
import copy
import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import subprocess
import sys
import time
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
                       "smtp_user": "auth", "smtp_pass": CANARY, "smtp_port": "587",
                       "hook_send_email_enabled": False, "hook_send_email_uri": None,
                       "hook_send_email_secrets": None, "mailer_autoconfirm": False,
                       "mailer_allow_unverified_email_sign_ins": False,
                       "mailer_otp_length": 6, "mailer_otp_exp": 3600, "smtp_max_frequency": 60,
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

    def test_enabled_invalid_hook_blocks_even_when_unused_smtp_is_configured(self):
        for uri, secret in (("https://", CANARY), ("https://example.test/send", None),
                            ("https://example.test:bad/send", CANARY),
                            ("https://example.test:65536/send", CANARY),
                            ("https://exa mple.test/send", CANARY)):
            with self.subTest(uri=uri):
                t = Transport()
                t.config.update(hook_send_email_enabled=True, hook_send_email_uri=uri,
                                hook_send_email_secrets=secret)
                e = S.execute("apply", "sbp_test", TEMPLATE, t)
                self.assertEqual(e["status"], "PRODUCTION_EMAIL_TRANSPORT_REQUIRED")
                self.assertTrue(e["delivery"]["custom_smtp_configured"])
                self.assertFalse(e["configuration_update_attempted"])
                self.assertEqual([c[0] for c in t.calls], ["GET"])

    def test_selected_boolean_canaries_never_enter_read_or_apply_evidence(self):
        for key in S.BOOLEAN_KEYS:
            for mode in ("check", "apply"):
                with self.subTest(key=key, mode=mode):
                    t = Transport(); t.config[key] = CANARY
                    e = S.execute(mode, "sbp_test", TEMPLATE, t)
                    self.assertEqual(e["status"], "INVALID_CONFIG_RESPONSE")
                    self.assertNotIn(CANARY, json.dumps(e))
                    self.assertFalse(e["configuration_update_attempted"])
                    self.assertEqual(len(t.calls), 1)

    def test_integer_projection_rejects_coercion_and_unbounded_values(self):
        for key in S.INTEGER_KEYS:
            for value in (True, 1.5, CANARY, {"secret": CANARY}, 9_007_199_254_740_992):
                with self.subTest(key=key, value=type(value).__name__):
                    t = Transport(); t.config[key] = value
                    e = S.execute("apply", "sbp_test", TEMPLATE, t)
                    self.assertEqual(e["status"], "INVALID_CONFIG_RESPONSE")
                    self.assertNotIn(CANARY, json.dumps(e))
                    self.assertFalse(e["configuration_update_attempted"])

    def test_numeric_boolean_cannot_appear_already_configured(self):
        t = Transport(); t.config.update(S.desired_config(TEMPLATE))
        t.config["external_email_enabled"] = 1
        t.config["mailer_autoconfirm"] = 0
        e = S.execute("apply", "sbp_test", TEMPLATE, t)
        self.assertEqual(e["status"], "INVALID_CONFIG_RESPONSE")
        self.assertFalse(e["configuration_update_verified"])
        self.assertEqual(len(t.calls), 1)

    def test_transport_metadata_rejects_objects_controls_and_invalid_port(self):
        for key in S.TRANSPORT_STRING_KEYS:
            for value in (True, {"secret": CANARY}, [CANARY], CANARY + "\n", "x" * 16_385):
                with self.subTest(key=key, type=type(value).__name__):
                    t = Transport(); t.config[key] = value
                    e = S.execute("check", "sbp_test", TEMPLATE, t)
                    self.assertEqual(e["status"], "INVALID_CONFIG_RESPONSE")
                    self.assertNotIn(CANARY, json.dumps(e))
        for port in (True, 587, 587.0, "5\n87", 0, 65536, {"secret": CANARY}):
            t = Transport(); t.config["smtp_port"] = port
            self.assertEqual(S.execute("apply", "sbp_test", TEMPLATE, t)["status"],
                             "INVALID_CONFIG_RESPONSE")
        t = Transport(); t.config["smtp_port"] = "587"
        self.assertTrue(S.execute("apply", "sbp_test", TEMPLATE, t)["configuration_update_verified"])
        for port in (None, "", "0587", "0", "65536", "not-a-port"):
            t = Transport(); t.config["smtp_port"] = port
            self.assertEqual(S.execute("apply", "sbp_test", TEMPLATE, t)["status"],
                             "PRODUCTION_EMAIL_TRANSPORT_REQUIRED")

    def test_nullable_hook_selection_is_unknown_and_cannot_fall_back_to_smtp(self):
        t = Transport(); t.config["hook_send_email_enabled"] = None
        e = S.execute("apply", "sbp_test", TEMPLATE, t)
        self.assertEqual(e["status"], "PRODUCTION_EMAIL_TRANSPORT_REQUIRED")
        self.assertIsNone(e["selected_config_before"]["hook_send_email_enabled"])
        self.assertFalse(e["configuration_update_attempted"])

    def test_duplicate_and_nonfinite_json_is_refused(self):
        for raw in (b'{"external_email_enabled":false,"external_email_enabled":true}',
                    b'{"smtp_port":NaN}'):
            e = S.execute("check", "sbp_test", TEMPLATE, lambda *a: (200, raw))
            self.assertEqual(e["status"], "INVALID_CONFIG_RESPONSE")

    def test_unknown_changed_field_names_and_presence_are_not_saved(self):
        for remove in (False, True):
            t = Transport(); t.config[CANARY] = None
            def transport(method, token, payload=None):
                if method == "PATCH":
                    if remove: t.config.pop(CANARY)
                    else: t.config[CANARY] = "changed"
                return t(method, token, payload)
            e = S.execute("apply", "sbp_test", TEMPLATE, transport)
            self.assertEqual(e["status"], "CONFIGURATION_READBACK_MISMATCH")
            self.assertEqual(e["unrelated_config_changed_keys"], [])
            self.assertEqual(e["unrelated_config_changed_count"], 1)
            self.assertNotIn(CANARY, json.dumps(e))

    def test_patch_whole_request_deadline_terminates_child_without_retry(self):
        original_run = subprocess.run
        calls = []
        def controlled_run(command, **kwargs):
            self.assertNotIn("sbp_test", json.dumps(command))
            self.assertNotIn("env", kwargs)
            envelope = json.loads(kwargs["input"])
            calls.append(envelope["method"])
            if envelope["method"] == "GET":
                body = base64.b64encode(json.dumps(Transport().config).encode()).decode()
                return subprocess.CompletedProcess(command, 0,
                    json.dumps({"status": 200, "body": body}).encode(), b"")
            return original_run([sys.executable, "-c", "import time; time.sleep(5)"], **kwargs)
        started = time.monotonic()
        with patch.object(S, "REQUEST_TIMEOUT_SECONDS", 0.1), \
                patch.object(S.subprocess, "run", controlled_run):
            e = S.execute("apply", "sbp_test", TEMPLATE, S.request_config)
        self.assertLess(time.monotonic() - started, 2)
        self.assertEqual(calls, ["GET", "PATCH"])
        self.assertEqual(e["status"], "TRANSPORT_OUTCOME_UNCONFIRMED")
        self.assertTrue(e["configuration_outcome_uncertain"])
        self.assertFalse(e["configuration_update_verified"])
        self.assertNotIn(CANARY, json.dumps(e))

    def test_private_worker_cannot_load_tokens_or_patch_outside_fixed_configuration(self):
        expected = S.desired_config(S.TEMPLATE.read_text())
        for payload in ({**expected, "external_phone_enabled": False},
                        {**expected, "external_email_enabled": 1}):
            data = json.dumps({"method": "PATCH", "token": "sbp_test", "payload": payload}).encode()
            stdin = type("PrivateInput", (), {"buffer": io.BytesIO(data)})()
            stdout = io.StringIO()
            with patch.object(S.sys, "stdin", stdin), patch.object(S.sys, "stdout", stdout), \
                    patch.object(S, "_request_config_http") as network, \
                    patch.object(S, "load_management_token") as credentials:
                S.private_request_worker()
            network.assert_not_called(); credentials.assert_not_called()
            self.assertEqual(json.loads(stdout.getvalue()), {"error": "TRANSPORT_OUTCOME_UNCONFIRMED"})

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
