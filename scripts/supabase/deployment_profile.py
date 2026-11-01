"""One public deployment identity shared by Collect releases and self-host services.

This contains no credentials. A SHA256 binds the canonical public configuration;
it is an integrity identifier, not an approval or an authentication credential.
"""
from __future__ import annotations

import hashlib
import ipaddress
import json
import re
from urllib.parse import urlsplit

FORMAT = "collect.deployment.v1"
FIELDS = frozenset(("format", "id", "mode", "environment", "supabase_origin",
                    "member_api_origin", "admin_origin", "public_origin",
                    "google_callback_origin"))
MANAGED_ORIGIN = "https://rrlduytparvsjfmegalh.supabase.co"


def normalize_https_origin(value: str) -> str:
    if not isinstance(value, str) or not value or len(value) > 2048 or re.search(r"[\s\\\x00-\x1f]", value):
        raise ValueError("Deployment origins must be canonical HTTPS origins")
    try:
        parsed = urlsplit(value)
        if (parsed.scheme != "https" or not parsed.hostname or parsed.username is not None
                or parsed.password is not None or parsed.port not in (None, 443)
                or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
            raise ValueError
        host = parsed.hostname.lower()
        # IP literals are deliberately excluded from release identities. A real
        # hostname binds TLS, cookies and OAuth consistently on physical devices.
        try:
            ipaddress.ip_address(host)
        except ValueError:
            pass
        else:
            raise ValueError
        if (len(host) > 253 or "." not in host or host.endswith(".") or re.fullmatch(r"[\d.]+", host)
                or any(not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
                       for label in host.split("."))):
            raise ValueError
        return "https://" + host
    except (ValueError, TypeError) as error:
        raise ValueError("Deployment origins must be canonical HTTPS origins") from error


def canonical_profile(profile: dict[str, str]) -> str:
    return json.dumps(profile, ensure_ascii=True, sort_keys=True, separators=(",", ":"))


def profile_sha256(profile: dict[str, str]) -> str:
    return hashlib.sha256(canonical_profile(profile).encode("utf-8")).hexdigest()


def validate_profile(profile: object) -> dict[str, str]:
    if (not isinstance(profile, dict) or set(profile) != FIELDS
            or any(not isinstance(value, str) for value in profile.values())
            or profile["format"] != FORMAT
            or not re.fullmatch(r"[a-z][a-z0-9-]{0,62}", profile["id"])
            or profile["mode"] not in ("managed", "self_hosted")
            or profile["environment"] not in ("production", "qualification")):
        raise ValueError("Invalid public deployment profile")
    for key in FIELDS:
        if key.endswith("_origin") and normalize_https_origin(profile[key]) != profile[key]:
            raise ValueError("Deployment profile origins must be canonical")
    if profile["google_callback_origin"] not in (profile["member_api_origin"], profile["admin_origin"]):
        raise ValueError("Google callback must use an approved application origin")
    if profile["mode"] == "managed" and profile["supabase_origin"] != MANAGED_ORIGIN:
        raise ValueError("Managed deployment must preserve its nominated project")
    return dict(profile)


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate deployment profile field")
        result[key] = value
    return result


def legacy_profile(*, qualification: bool = False) -> dict[str, str]:
    admin = ("https://admin-supabase-qa.collect.ikanisa.com" if qualification
             else "https://platform-admin.collect.ikanisa.com")
    return {"format": FORMAT, "id": "collect-managed-qualification" if qualification else "collect-managed-production",
            "mode": "managed", "environment": "qualification" if qualification else "production",
            "supabase_origin": MANAGED_ORIGIN, "member_api_origin": admin,
            "admin_origin": admin, "public_origin": "https://collect.ikanisa.com",
            "google_callback_origin": admin}


def resolve_profile(env: dict[str, str], *, qualification: bool = False) -> dict[str, str]:
    raw = env.get("COLLECT_DEPLOYMENT_PROFILE")
    digest = env.get("COLLECT_DEPLOYMENT_PROFILE_SHA256")
    if raw is None and digest is None:
        return legacy_profile(qualification=qualification)
    if (not isinstance(raw, str) or not raw or len(raw.encode("utf-8")) > 8192
            or not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest)):
        raise ValueError("Deployment profile and SHA256 must be configured together")
    try:
        profile = validate_profile(json.loads(raw, object_pairs_hook=_unique_object))
    except (ValueError, TypeError, UnicodeError) as error:
        raise ValueError("Invalid public deployment profile") from error
    if raw != canonical_profile(profile):
        raise ValueError("Deployment profile must be canonical JSON")
    if profile_sha256(profile) != digest:
        raise ValueError("Deployment profile SHA256 mismatch")
    expected = "qualification" if qualification else "production"
    if profile["environment"] != expected:
        raise ValueError("Deployment profile environment does not match release purpose")
    return profile


def public_profile_defines(env: dict[str, str], *, qualification: bool = False) -> dict[str, str]:
    """Only explicit profiles are serialized to new clients; legacy stays exact."""
    if "COLLECT_DEPLOYMENT_PROFILE" not in env and "COLLECT_DEPLOYMENT_PROFILE_SHA256" not in env:
        return {}
    profile = resolve_profile(env, qualification=qualification)
    return {"COLLECT_DEPLOYMENT_PROFILE": canonical_profile(profile),
            "COLLECT_DEPLOYMENT_PROFILE_SHA256": profile_sha256(profile),
            "SUPABASE_AUTH_ISSUER": profile["supabase_origin"] + "/auth/v1"}
