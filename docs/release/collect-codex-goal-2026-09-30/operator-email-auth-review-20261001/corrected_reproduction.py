#!/usr/bin/env python3
"""Check corrected review guards using only synthetic in-memory responses."""
import copy
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path

LEAF = Path(__file__).resolve().parent
SUBJECT = LEAF / "corrected-subject/collect_operator_email_auth.py"
EXPECTED = "a6edff976eee3f65ce9cbccdbe84dfc2f2c1e99f78d26b09f2f69a676dc0df05"
CANARY = "SYNTHETIC_REDACTION_REVIEW_CANARY"
TEMPLATE = "<p>Code: {{ .Token }}</p>"


class SyntheticTransport:
    def __init__(self, config, change=None):
        self.config = copy.deepcopy(config)
        self.change = change
        self.calls = []

    def __call__(self, method, token, payload=None):
        self.calls.append(method)
        if payload is not None:
            self.config.update(payload)
            if self.change is not None:
                self.change(self.config)
        return 200, json.dumps(self.config).encode()


def main():
    digest = hashlib.sha256(SUBJECT.read_bytes()).hexdigest()
    if digest != EXPECTED:
        raise RuntimeError("Corrected subject hash does not match reviewed bytes")
    spec = importlib.util.spec_from_file_location("corrected_subject", SUBJECT)
    subject = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(subject)
    base = {
        "external_email_enabled": False, "external_phone_enabled": True,
        "mailer_otp_exp": 600, "hook_send_email_enabled": False,
        "smtp_host": "smtp.example.test", "smtp_admin_email": "auth@example.test",
        "smtp_user": "auth", "smtp_pass": "synthetic", "smtp_port": "587",
    }
    hook = SyntheticTransport({**base, "hook_send_email_enabled": True,
                               "hook_send_email_uri": "https://",
                               "hook_send_email_secrets": None})
    hook_result = subject.execute("apply", "synthetic", TEMPLATE, hook)
    reflected = SyntheticTransport({**base, "external_email_enabled": CANARY})
    reflected_result = subject.execute("check", "synthetic", TEMPLATE, reflected)
    equality = SyntheticTransport({**base, **subject.desired_config(TEMPLATE),
                                   "external_email_enabled": 1,
                                   "mailer_autoconfirm": 0})
    equality_result = subject.execute("apply", "synthetic", TEMPLATE, equality)
    changed = SyntheticTransport({**base, "external_anonymous_users_enabled": False},
                                 lambda config: config.update(external_anonymous_users_enabled=0))
    changed_result = subject.execute("apply", "synthetic", TEMPLATE, changed)
    unknown = SyntheticTransport({**base, "hook_send_email_enabled": None})
    unknown_result = subject.execute("apply", "synthetic", TEMPLATE, unknown)
    guards = {
        "invalid_active_hook_blocks_patch":
            hook_result["status"] == "PRODUCTION_EMAIL_TRANSPORT_REQUIRED" and hook.calls == ["GET"],
        "untyped_selected_canary_refused_without_reflection":
            reflected_result["status"] == "INVALID_CONFIG_RESPONSE" and CANARY not in json.dumps(reflected_result),
        "numeric_booleans_cannot_be_accepted":
            equality_result["status"] == "INVALID_CONFIG_RESPONSE" and not equality_result["configuration_update_verified"],
        "unrelated_type_change_is_uncertain_and_never_retried":
            changed_result["status"] == "CONFIGURATION_READBACK_MISMATCH"
            and changed_result["configuration_outcome_uncertain"]
            and not changed_result["configuration_update_verified"]
            and changed.calls == ["GET", "PATCH", "GET"],
        "nullable_active_transport_remains_unknown":
            unknown_result["status"] == "PRODUCTION_EMAIL_TRANSPORT_REQUIRED" and unknown.calls == ["GET"],
    }
    print(json.dumps({
        "kind": "independent_corrected_auth_guard_review",
        "observed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "subject_sha256": digest, "guards": guards, "all_guards_pass": all(guards.values()),
        "scope": "Five injected guard checks; not the owner31-test suite or hosted acceptance",
        "hosted_calls": 0, "credential_accesses": 0, "otp_requests": 0,
        "source_edits": 0, "production_acceptance": False,
    }, indent=2))
    return 0 if all(guards.values()) else 2


if __name__ == "__main__":
    raise SystemExit(main())
