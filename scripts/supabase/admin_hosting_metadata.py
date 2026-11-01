"""Validate the public deployment identity retained in a built Admin artifact.

The digest proves consistency with the chosen profile, never deployment or
provider approval. Legacy artifacts keep their exact managed-project check.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys

try:
    from .deployment_profile import validate_profile, profile_sha256, resolve_profile
except ImportError:
    from deployment_profile import validate_profile, profile_sha256, resolve_profile


PROFILE_FIELDS = frozenset(("deployment_profile", "deployment_profile_sha256",
                            "supabase_hosting", "supabase_auth_issuer"))
PROJECT = "rrlduytparvsjfmegalh"


def validate_metadata(version: dict, env: dict[str, str] | None = None) -> None:
    if not isinstance(version, dict):
        raise ValueError("Admin metadata must be an object")
    explicit = bool(PROFILE_FIELDS.intersection(version))
    env = {} if env is None else env
    if not explicit:
        if (version.get("supabase_project_ref") != PROJECT or
                "COLLECT_DEPLOYMENT_PROFILE" in env or
                "COLLECT_DEPLOYMENT_PROFILE_SHA256" in env):
            raise ValueError("Legacy Admin metadata must retain its nominated managed project")
        return
    if not PROFILE_FIELDS.issubset(version):
        raise ValueError("Admin deployment identity is incomplete")
    profile = validate_profile(version["deployment_profile"])
    if (version["deployment_profile_sha256"] != profile_sha256(profile) or
            version["supabase_hosting"] != profile["mode"] or
            version["supabase_auth_issuer"] != profile["supabase_origin"] + "/auth/v1" or
            version.get("supabase_project_ref") != (PROJECT if profile["mode"] == "managed" else None)):
        raise ValueError("Admin deployment identity fields disagree")
    qualification = profile["environment"] == "qualification"
    if version.get("environment", profile["environment"]) != profile["environment"]:
        raise ValueError("Admin artifact environment disagrees with its profile")
    if qualification and not (
            version.get("purpose") == "qualification" and
            version.get("admin_origin") == profile["admin_origin"] and
            version.get("qualification_complete") is False and
            version.get("shipping_candidate") is False):
        raise ValueError("Qualification artifact cannot claim release acceptance")
    if "admin_origin" in version and version["admin_origin"] != profile["admin_origin"]:
        raise ValueError("Admin origin disagrees with its profile")
    if "COLLECT_DEPLOYMENT_PROFILE" in env or "COLLECT_DEPLOYMENT_PROFILE_SHA256" in env:
        if resolve_profile(env, qualification=qualification) != profile:
            raise ValueError("Built Admin identity differs from the selected profile")


def main() -> int:
    try:
        if len(sys.argv) != 2:
            raise ValueError("Expected the built public version metadata path")
        path = Path(sys.argv[1]).absolute()
        if path.is_symlink() or path.resolve() != path or not path.is_file() or path.stat().st_size > 1024 * 1024:
            raise ValueError("Expected bounded physical Admin metadata")
        validate_metadata(json.loads(path.read_text()), dict(os.environ))
        return 0
    except (OSError, ValueError, TypeError, KeyError):
        # Caller provides a stable redacted gate error; no environment is logged.
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
