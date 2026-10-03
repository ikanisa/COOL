#!/usr/bin/env python3
"""Offline reproduction against the exact retained pre-fix review subject.

Only synthetic in-memory transport is invoked. No credential loader, urllib
request, Auth endpoint, CLI, OTP, file credential or environment is accessed.
"""
import copy
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path

LEAF = Path(__file__).resolve().parent
SUBJECT = LEAF / "subject/collect_operator_email_auth.py"
EXPECTED = "645bd7f40400fe9dff8dbd78cd3aebebee60bba3b615a7e479a79d4263022e62"
CANARY = "SYNTHETIC_REDACTION_REVIEW_CANARY"
TEMPLATE = "<p>Code: {{ .Token }}</p>"


class SyntheticTransport:
    def __init__(self, config):
        self.config = copy.deepcopy(config)
        self.calls = []

    def __call__(self, method, token, payload=None):
        self.calls.append(method)
        if payload is not None:
            self.config.update(payload)
        return 200, json.dumps(self.config).encode()


def main():
    digest = hashlib.sha256(SUBJECT.read_bytes()).hexdigest()
    if digest != EXPECTED:
        raise RuntimeError("Retained original subject hash does not match")
    spec = importlib.util.spec_from_file_location("review_subject", SUBJECT)
    subject = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(subject)
    base = {
        "external_email_enabled": False, "external_phone_enabled": True,
        "smtp_host": "smtp.example.test", "smtp_admin_email": "auth@example.test",
        "smtp_user": "auth", "smtp_pass": "synthetic", "smtp_port": 587,
        "hook_send_email_enabled": True, "hook_send_email_uri": "https://",
        "hook_send_email_secrets": None,
    }
    hook = SyntheticTransport(base)
    hook_result = subject.execute("apply", "synthetic", TEMPLATE, hook)
    reflected = SyntheticTransport({**base, "external_email_enabled": CANARY})
    reflected_result = subject.execute("check", "synthetic", TEMPLATE, reflected)
    untyped = {**base, "hook_send_email_enabled": False,
               **subject.desired_config(TEMPLATE)}
    for key in ("external_email_enabled", "mailer_autoconfirm",
                "mailer_allow_unverified_email_sign_ins"):
        untyped[key] = int(untyped[key])
    equality = SyntheticTransport(untyped)
    equality_result = subject.execute("apply", "synthetic", TEMPLATE, equality)
    findings = {
        "enabled_invalid_hook_uses_smtp_fallback": {
            "status": hook_result["status"], "calls": hook.calls,
            "unexpected_acceptance": hook_result["configuration_update_verified"],
        },
        "selected_field_reflects_untyped_content": {
            "status": reflected_result["status"], "calls": reflected.calls,
            "canary_reflected": CANARY in json.dumps(reflected_result),
        },
        "boolean_integer_equality_accepts_wrong_types": {
            "status": equality_result["status"], "calls": equality.calls,
            "unexpected_acceptance": equality_result["configuration_update_verified"],
        },
    }
    receipt = {
        "kind": "independent_auth_source_review_synthetic_reproduction",
        "observed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "subject_sha256": digest, "findings": findings,
        "hosted_calls": 0, "credential_accesses": 0, "otp_requests": 0,
        "source_edits": 0, "production_acceptance": False,
    }
    print(json.dumps(receipt, indent=2))
    return 0 if (findings["enabled_invalid_hook_uses_smtp_fallback"]["unexpected_acceptance"]
                 and findings["selected_field_reflects_untyped_content"]["canary_reflected"]
                 and findings["boolean_integer_equality_accepts_wrong_types"]["unexpected_acceptance"]) else 2


if __name__ == "__main__":
    raise SystemExit(main())
