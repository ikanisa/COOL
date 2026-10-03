#!/usr/bin/env python3
"""Read or narrowly configure hosted operator email Auth without exposing secrets.

This does not provision users, verify an email, request an OTP, establish an
operator session, cut over approvals, or enable receipt sends. No automatic
retry or rollback is performed after a possibly applied configuration update.
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
PROJECT = "lhbowpbcpwoiparwnwgt"
AUTH_CONFIG_URL = f"https://api.supabase.com/v1/projects/{PROJECT}/config/auth"
REQUEST_TIMEOUT_SECONDS = 20
MAX_RESPONSE_BYTES = 2_000_000
PRIVATE_REQUEST_ENV = {"PATH": os.defpath, "PYTHONUTF8": "1"}
TEMPLATE = ROOT / "supabase/templates/collect_email_sign_in.html"
SELECTED_KEYS = (
    "external_email_enabled", "external_phone_enabled", "mailer_autoconfirm",
    "mailer_allow_unverified_email_sign_ins", "mailer_otp_length",
    "mailer_otp_exp", "smtp_max_frequency", "hook_send_email_enabled",
    "disable_signup",
)
BOOLEAN_KEYS = frozenset(SELECTED_KEYS) - {
    "mailer_otp_length", "mailer_otp_exp", "smtp_max_frequency",
}
INTEGER_KEYS = frozenset(SELECTED_KEYS) - BOOLEAN_KEYS
TRANSPORT_STRING_KEYS = (
    "smtp_host", "smtp_admin_email", "smtp_user", "smtp_pass",
    "hook_send_email_uri", "hook_send_email_secrets",
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


def _request_config_http(method, token, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(
        AUTH_CONFIG_URL, data=data, method=method,
        headers={"Authorization": "Bearer " + token,
                 "Accept": "application/json", "Content-Type": "application/json"},
    )
    try:
        response = urllib.request.build_opener(NoRedirect()).open(
            request, timeout=REQUEST_TIMEOUT_SECONDS)
    except urllib.error.HTTPError as response:
        with response:
            raw = response.read(MAX_RESPONSE_BYTES + 1)
            if len(raw) > MAX_RESPONSE_BYTES:
                raise AuthSetupError("RESPONSE_LIMIT_EXCEEDED")
            return response.code, raw
    except Exception:
        raise AuthSetupError("TRANSPORT_OUTCOME_UNCONFIRMED") from None
    with response:
        raw = response.read(MAX_RESPONSE_BYTES + 1)
        if len(raw) > MAX_RESPONSE_BYTES:
            raise AuthSetupError("RESPONSE_LIMIT_EXCEEDED")
        return response.status, raw


def request_config(method, token, payload=None):
    # A socket timeout does not bound DNS or a trickling body. One child per
    # exchange gives the entire request a deadline and is killed on timeout.
    # Credentials, payload and raw configuration travel through private pipes;
    # they are never command arguments, environment additions or saved files.
    envelope = json.dumps({"method": method, "token": token, "payload": payload})
    try:
        child = subprocess.run(
            [sys.executable, str(Path(__file__).resolve()), "--private-auth-config-request"],
            input=envelope.encode(), capture_output=True, timeout=REQUEST_TIMEOUT_SECONDS,
            check=False, env=PRIVATE_REQUEST_ENV,
        )
        reply = json.loads(child.stdout)
        if child.returncode != 0 or not isinstance(reply, dict):
            raise ValueError()
        if "error" in reply:
            if reply["error"] == "RESPONSE_LIMIT_EXCEEDED":
                raise AuthSetupError("RESPONSE_LIMIT_EXCEEDED")
            raise ValueError()
        if type(reply.get("status")) is not int or not isinstance(reply.get("body"), str):
            raise ValueError()
        raw = base64.b64decode(reply["body"], validate=True)
        if len(raw) > MAX_RESPONSE_BYTES:
            raise AuthSetupError("RESPONSE_LIMIT_EXCEEDED")
        return reply["status"], raw
    except AuthSetupError:
        raise
    except Exception:
        raise AuthSetupError("TRANSPORT_OUTCOME_UNCONFIRMED") from None


def private_request_worker():
    """Private pipe protocol; cannot load credentials or perform other changes."""
    try:
        raw = sys.stdin.buffer.read(MAX_RESPONSE_BYTES + 1)
        if len(raw) > MAX_RESPONSE_BYTES:
            raise ValueError()
        envelope = json.loads(raw)
        method, token, payload = envelope["method"], envelope["token"], envelope["payload"]
        if (method not in ("GET", "PATCH") or not isinstance(token, str) or
                not token.startswith("sbp_") or any(c in token for c in "\r\n\x00")):
            raise ValueError()
        if method == "GET" and payload is not None:
            raise ValueError()
        if method == "PATCH":
            expected = desired_config(TEMPLATE.read_text())
            if (not isinstance(payload, dict) or set(payload) != set(expected) or
                    any(type(payload[k]) is not type(value) or payload[k] != value
                        for k, value in expected.items())):
                raise ValueError()
        status, body = _request_config_http(method, token, payload)
        reply = {"status": status, "body": base64.b64encode(body).decode("ascii")}
    except AuthSetupError as error:
        reply = {"error": str(error)}
    except Exception:
        reply = {"error": "TRANSPORT_OUTCOME_UNCONFIRMED"}
    sys.stdout.write(json.dumps(reply))
    return 0


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
    custom_smtp = all(isinstance(config.get(k), str) and bool(config[k].strip()) for k in
                      ("smtp_host", "smtp_admin_email", "smtp_user", "smtp_pass"))
    smtp_port = config.get("smtp_port")
    port_ready = (isinstance(smtp_port, str) and smtp_port.isascii() and
                  smtp_port.isdigit() and len(smtp_port) <= 5 and
                  str(int(smtp_port)) == smtp_port and 1 <= int(smtp_port) <= 65535)
    custom_smtp = custom_smtp and port_ready
    hook_uri = config.get("hook_send_email_uri", "")
    try:
        parsed = urllib.parse.urlsplit(hook_uri if isinstance(hook_uri, str) else "")
        secure_hook = (parsed.scheme == "https" and bool(parsed.hostname) and
                       parsed.username is None and parsed.password is None and
                       not any(c.isspace() for c in hook_uri) and
                       (parsed.port is None or 1 <= parsed.port <= 65535))
    except ValueError:
        secure_hook = False
    hook_enabled = config.get("hook_send_email_enabled") is True
    hook = (hook_enabled and secure_hook and
            isinstance(config.get("hook_send_email_secrets"), str) and
            bool(config["hook_send_email_secrets"].strip()))
    # An enabled Send Email Hook replaces SMTP. An invalid enabled hook must
    # never be accepted merely because unused SMTP metadata is present.
    ready = (hook if hook_enabled else custom_smtp
             if config.get("hook_send_email_enabled") is False else False)
    return {"custom_smtp_configured": bool(custom_smtp),
            "email_hook_configured": bool(hook),
            "delivery_transport_metadata_ready": bool(ready),
            "actual_email_delivery_verified": False}


def decode_config(raw):
    def unique_object(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError()
            value[key] = item
        return value

    def invalid_constant(_):
        raise ValueError()

    try:
        config = json.loads(raw, object_pairs_hook=unique_object,
                            parse_constant=invalid_constant)
        if not isinstance(config, dict):
            raise ValueError()
        # Validate before projecting anything into retained evidence. Missing
        # or null optional values remain unknown rather than becoming strings.
        for key in BOOLEAN_KEYS:
            if config.get(key) is not None and type(config[key]) is not bool:
                raise ValueError()
        for key in INTEGER_KEYS:
            value = config.get(key)
            if value is not None and (type(value) is not int or
                                      not -9_007_199_254_740_991 <= value <= 9_007_199_254_740_991):
                raise ValueError()
        if type(config.get("mailer_otp_exp")) is not int:
            raise ValueError()
        for key in TRANSPORT_STRING_KEYS:
            value = config.get(key)
            if value is not None and (not isinstance(value, str) or
                                      len(value) > 16_384 or
                                      any(c in value for c in "\r\n\x00")):
                raise ValueError()
        port = config.get("smtp_port")
        if port is not None and (not isinstance(port, str) or len(port) > 16_384 or
                                 any(c in port for c in "\r\n\x00")):
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
        changed = {k for k in set(before) | set(after) if k not in desired and
                   (k not in before or k not in after or before[k] != after[k])}
        # Compare every unrelated field, but retain only fixed known key names.
        # A malformed server field name must not become a saved secret value.
        evidence["unrelated_config_changed_keys"] = sorted(changed & set(SELECTED_KEYS))
        evidence["unrelated_config_changed_count"] = len(changed)
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
    raise SystemExit(private_request_worker() if
                     sys.argv[1:] == ["--private-auth-config-request"] else main())
