#!/usr/bin/env python3
"""Read or narrowly configure hosted operator email Auth without exposing secrets.

This does not provision users, verify an email, request an OTP, establish an
operator session, cut over approvals, or enable receipt sends. No automatic
retry or rollback is performed after a possibly applied configuration update.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import stat
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
PROJECT = "lhbowpbcpwoiparwnwgt"
AUTH_CONFIG_URL = f"https://api.supabase.com/v1/projects/{PROJECT}/config/auth"
TEMPLATE = ROOT / "supabase/templates/collect_email_sign_in.html"
SELECTED_KEYS = (
    "external_email_enabled", "external_phone_enabled", "mailer_autoconfirm",
    "mailer_allow_unverified_email_sign_ins", "mailer_otp_length",
    "mailer_otp_exp", "smtp_max_frequency", "hook_send_email_enabled",
    "disable_signup",
)


class AuthSetupError(Exception):
    """Only constant, non-sensitive diagnostic codes may cross the boundary."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def load_management_token():
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
    if not token:
        path = Path.home() / ".supabase/access-token"
        try:
            metadata = path.lstat()
            if (not stat.S_ISREG(metadata.st_mode) or
                    metadata.st_uid != os.getuid() or metadata.st_mode & 0o077):
                raise AuthSetupError("CLI_TOKEN_FILE_UNSAFE")
            token = path.read_text().strip()
        except AuthSetupError:
            raise
        except Exception:
            raise AuthSetupError("MANAGEMENT_CREDENTIAL_UNAVAILABLE") from None
    if not token.startswith("sbp_") or any(c in token for c in "\r\n\x00"):
        raise AuthSetupError("MANAGEMENT_CREDENTIAL_INVALID")
    return token


def request_config(method, token, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(
        AUTH_CONFIG_URL, data=data, method=method,
        headers={"Authorization": "Bearer " + token,
                 "Accept": "application/json", "Content-Type": "application/json"},
    )
    try:
        response = urllib.request.build_opener(NoRedirect()).open(request, timeout=20)
    except urllib.error.HTTPError as response:
        with response:
            raw = response.read(2_000_001)
            return response.code, raw
    except Exception:
        raise AuthSetupError("TRANSPORT_OUTCOME_UNCONFIRMED") from None
    with response:
        raw = response.read(2_000_001)
        if len(raw) > 2_000_000:
            raise AuthSetupError("RESPONSE_LIMIT_EXCEEDED")
        return response.status, raw


def desired_config(template):
    if "{{ .Token }}" not in template or "ConfirmationURL" in template:
        raise AuthSetupError("EMAIL_CODE_TEMPLATE_INVALID")
    return {
        "external_email_enabled": True,
        "mailer_autoconfirm": False,
        "mailer_allow_unverified_email_sign_ins": False,
        "mailer_otp_length": 6,
        "mailer_otp_exp": 600,
        "smtp_max_frequency": 60,
        "mailer_subjects_magic_link": "Collect sign-in code",
        "mailer_templates_magic_link_content": template,
    }


def delivery_metadata(config):
    custom_smtp = all(bool(config.get(k)) for k in
                      ("smtp_host", "smtp_admin_email", "smtp_user", "smtp_pass"))
    smtp_port = str(config.get("smtp_port", ""))
    custom_smtp = custom_smtp and smtp_port.isdigit() and 1 <= int(smtp_port) <= 65535
    hook_uri = config.get("hook_send_email_uri", "")
    try:
        parsed = urllib.parse.urlsplit(hook_uri if isinstance(hook_uri, str) else "")
        secure_hook = (parsed.scheme == "https" and bool(parsed.hostname) and
                       parsed.username is None and parsed.password is None)
    except ValueError:
        secure_hook = False
    hook = (config.get("hook_send_email_enabled") is True and secure_hook and
            bool(config.get("hook_send_email_secrets")))
    return {"custom_smtp_configured": bool(custom_smtp),
            "email_hook_configured": bool(hook),
            "delivery_transport_metadata_ready": bool(custom_smtp or hook),
            "actual_email_delivery_verified": False}


def decode_config(raw):
    try:
        config = json.loads(raw)
        if not isinstance(config, dict):
            raise ValueError()
        return config
    except Exception:
        raise AuthSetupError("INVALID_CONFIG_RESPONSE") from None


def execute(mode, token, template, transport=request_config):
    desired = desired_config(template)
    evidence = {
        "kind": "narrow_hosted_operator_email_auth",
        "captured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "project_ref": PROJECT, "mode": mode, "selected_operator_email": "info@ikanisa.com",
        "configuration_update_attempted": False, "configuration_update_verified": False,
        "configuration_outcome_uncertain": False, "account_provisioned": False,
        "otp_requests": 0, "operator_session_established": False,
        "credentials_printed": False, "raw_config_saved": False,
        "live_sms_enabled": False,
        "template_sha256": hashlib.sha256(template.encode()).hexdigest(),
        "patch_fields": sorted(desired), "requests": [],
    }

    def call(method, payload=None):
        status, raw = transport(method, token, payload)
        evidence["requests"].append({"method": method, "http_status": status,
                                    "response_sha256": hashlib.sha256(raw).hexdigest()})
        if status not in (200, 201):
            raise AuthSetupError("MANAGEMENT_ACCESS_DENIED" if status in (401, 403)
                                 else "MANAGEMENT_HTTP_FAILURE")
        return decode_config(raw)

    try:
        before = call("GET")
        evidence["selected_config_before"] = {k: before.get(k) for k in SELECTED_KEYS}
        evidence["delivery"] = delivery_metadata(before)
        if mode == "check":
            evidence["status"] = "READ_SUCCEEDED"
            return evidence
        if before.get("external_phone_enabled") is not True:
            raise AuthSetupError("MEMBER_PHONE_AUTH_NOT_ESTABLISHED")
        if not evidence["delivery"]["delivery_transport_metadata_ready"]:
            raise AuthSetupError("PRODUCTION_EMAIL_TRANSPORT_REQUIRED")
        # Keep all SMTP, SMS/phone, signup, redirect, MFA and hook values out of
        # the PATCH. Compare them in memory after the update, never in logs.
        if all(before.get(k) == v for k, v in desired.items()):
            evidence["status"] = "ALREADY_CONFIGURED"
            evidence["configuration_update_verified"] = True
            evidence["unrelated_config_unchanged"] = True
            return evidence
        evidence["configuration_update_attempted"] = True
        call("PATCH", desired)
        after = call("GET")
        evidence["selected_config_after"] = {k: after.get(k) for k in SELECTED_KEYS}
        changed = sorted(k for k in set(before) | set(after)
                         if k not in desired and before.get(k) != after.get(k))
        evidence["unrelated_config_changed_keys"] = changed
        evidence["unrelated_config_unchanged"] = not changed
        if changed or any(after.get(k) != v for k, v in desired.items()):
            raise AuthSetupError("CONFIGURATION_READBACK_MISMATCH")
        evidence["configuration_update_verified"] = True
        evidence["status"] = "CONFIGURED_READBACK_VERIFIED"
    except AuthSetupError as error:
        evidence["status"] = str(error)
        evidence["configuration_outcome_uncertain"] = evidence["configuration_update_attempted"]
    except Exception:
        evidence["status"] = "SETUP_INCOMPLETE"
        evidence["configuration_outcome_uncertain"] = evidence["configuration_update_attempted"]
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("check", "apply"))
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    if args.evidence.exists() or args.evidence.is_symlink():
        parser.error("Evidence output already exists; use a fresh filename")
    try:
        result = execute(args.mode, load_management_token(), TEMPLATE.read_text())
    except AuthSetupError as error:
        result = {"status": str(error), "configuration_update_attempted": False,
                  "credentials_printed": False, "otp_requests": 0}
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    with args.evidence.open("x") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")
    print(json.dumps({k: result.get(k) for k in
                      ("status", "configuration_update_attempted", "configuration_update_verified",
                       "configuration_outcome_uncertain", "otp_requests")}))
    return 0 if result.get("status") in ("READ_SUCCEEDED", "ALREADY_CONFIGURED",
                                        "CONFIGURED_READBACK_VERIFIED") else 2


if __name__ == "__main__":
    raise SystemExit(main())
