#!/usr/bin/env python3
"""Public native store configuration. No provider, database or signing inputs."""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
from urllib.parse import urlsplit

PROJECT = "https://rrlduytparvsjfmegalh.supabase.co"
PUBLIC = "https://collect.ikanisa.com"
ADMIN = "https://platform-admin.collect.ikanisa.com"
# Public dummy site keys documented by Cloudflare. They are useful only for an
# explicitly isolated qualification artifact, never a native store build.
TURNSTILE_TEST_SITE_KEYS = frozenset((
    "1x00000000000000000000AA", "2x00000000000000000000AB",
    "1x00000000000000000000BB", "2x00000000000000000000BB",
    "3x00000000000000000000FF",
))


def deployment_configuration(env):
    # Keep legacy artifacts reproducible. An explicit deployment can only use
    # the shared checked-in validator, never a path supplied by an environment.
    if "COLLECT_DEPLOYMENT_PROFILE" not in env and "COLLECT_DEPLOYMENT_PROFILE_SHA256" not in env:
        return {"supabase_origin": PROJECT, "member_api_origin": ADMIN,
                "admin_origin": ADMIN, "public_origin": PUBLIC}, {}
    path = Path(__file__).resolve().parents[1] / "supabase/deployment_profile.py"
    try:
        if not path.is_file() or path.is_symlink():
            raise ValueError
        spec = importlib.util.spec_from_file_location("collect_native_deployment_profile", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        profile = module.resolve_profile(env)
        return profile, module.public_profile_defines(env)
    except (OSError, ValueError, TypeError, AttributeError) as error:
        raise ValueError("Native release requires a valid reviewed deployment profile") from error


def origin(value):
    parsed = urlsplit(value)
    if (not value or re.search(r"\s", value) or parsed.scheme != "https"
            or not parsed.hostname or parsed.username or parsed.password
            or parsed.port not in (None, 443) or parsed.path not in ("", "/")
            or parsed.query or parsed.fragment):
        raise ValueError("Native release URLs must be HTTPS origins")
    return "https://" + parsed.hostname.lower()


def build_version(env, platform, pubspec=None):
    # Match the numeric, <=32-character public diagnostic boundary. Production
    # artifact identity and its diagnostic label must come from the same source.
    path = Path(pubspec) if pubspec is not None else Path(__file__).resolve().parents[2] / "pubspec.yaml"
    try:
        if not path.is_file() or path.is_symlink() or path.stat().st_size > 1024**2:
            raise ValueError
        declarations = [line for line in path.read_text(encoding="utf-8").splitlines()
                        if line.startswith("version:")]
    except (OSError, UnicodeError, ValueError) as error:
        raise ValueError("Native release requires a readable source pubspec version") from error
    match = re.fullmatch(
        r"version:[ \t]*((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))\+([1-9][0-9]*)[ \t]*",
        declarations[0] if len(declarations) == 1 else "")
    if match is None or len(match[1] + "+" + match[2]) > 32 or int(match[2]) > 0x7fffffff:
        raise ValueError("Native release requires one numeric source version and positive build number")
    version = match[1] + "+" + match[2]
    expected = {"COLLECT_BUILD_VERSION": version,
                "COLLECT_" + platform.upper() + "_BUILD_NAME": match[1],
                "COLLECT_" + platform.upper() + "_BUILD_NUMBER": match[2]}
    if any(name in env and env[name] != value for name, value in expected.items()):
        # Never echo a caller value into diagnostics or command errors.
        raise ValueError("Native release build overrides must match the source pubspec version")
    return version


def configuration(env, platform, pubspec=None):
    if platform not in ("android", "ios"):
        raise ValueError("Expected android or ios")
    if env.get("COLLECT_BACKEND", "supabase") != "supabase":
        raise ValueError("Native store builds require the Supabase backend")
    profile, profile_defines = deployment_configuration(env)
    project = origin(env.get("SUPABASE_URL", ""))
    if project != profile["supabase_origin"]:
        raise ValueError("Native store builds require the nominated Supabase project")
    key = env.get("SUPABASE_PUBLISHABLE_KEY", "")
    if not re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{10,300}", key):
        raise ValueError("Native release requires a public Supabase publishable key")
    captcha = env.get("AUTH_CAPTCHA_ENABLED", "true")
    google = env.get("COLLECT_GOOGLE_AUTH_ENABLED", env.get("GOOGLE_AUTH_ENABLED", "false"))
    if ("COLLECT_GOOGLE_AUTH_ENABLED" in env and "GOOGLE_AUTH_ENABLED" in env
            and env["COLLECT_GOOGLE_AUTH_ENABLED"] != env["GOOGLE_AUTH_ENABLED"]):
        raise ValueError("Native and shared Google authentication flags must match")
    feature_flags = {}
    for name in ("COLLECT_SMS_AUTH_ENABLED", "COLLECT_WHATSAPP_AUTH_ENABLED", "COLLECT_ANONYMOUS_AUTH_ENABLED"):
        if name in env:
            if env[name] not in ("true", "false"):
                raise ValueError("Native authentication availability flags must be true or false")
            feature_flags[name] = env[name]
    if captcha != "true" or google not in ("true", "false"):
        raise ValueError("Store builds require CAPTCHA enabled and a true or false Google authentication flag")
    provider = env.get("AUTH_CAPTCHA_PROVIDER", "turnstile")
    site_key = env.get("AUTH_CAPTCHA_SITE_KEY", "")
    if provider != "turnstile" or not re.fullmatch(r"[A-Za-z0-9_-]{10,200}", site_key):
        raise ValueError("Enabled CAPTCHA requires Turnstile and its public site key")
    if site_key in TURNSTILE_TEST_SITE_KEYS:
        raise ValueError("Native store builds cannot use a public CAPTCHA test key")
    api = origin(env.get("SUPABASE_API_URL", ""))
    if api != profile["member_api_origin"]:
        raise ValueError("Native release API must use the reviewed Supabase production target")
    # Reject stale legacy input rather than silently letting it nominate another
    # native endpoint. The compatibility alias carries the same reviewed API.
    if env.get("COLLECT_API_URL", api) != api:
        raise ValueError("COLLECT_API_URL must match the Supabase API origin when provided")
    public, admin = profile["public_origin"], profile["admin_origin"]
    if env.get("APP_PUBLIC_URL", public) != public or env.get("ADMIN_APP_URL", admin) != admin:
        raise ValueError("Public and Admin URLs must match the reviewed HTTPS production targets")
    if env.get("SUPABASE_ADMIN_API_URL", admin) != admin:
        raise ValueError("Supabase Admin API must match the reviewed deployment profile")
    if env.get("SUPABASE_AUTH_ISSUER", project + "/auth/v1") != project + "/auth/v1":
        raise ValueError("Native Auth issuer must match the public Supabase origin")
    version = build_version(env, platform, pubspec)
    values = {"COLLECT_BUILD_VERSION": version, "COLLECT_BACKEND": "supabase", "SUPABASE_URL": project,
              "SUPABASE_API_URL": api, "SUPABASE_ADMIN_API_URL": admin,
              "SUPABASE_PUBLISHABLE_KEY": key, "COLLECT_API_URL": api,
              "APP_PUBLIC_URL": public, "ADMIN_APP_URL": admin,
              "APP_ENVIRONMENT": "production", "ENABLE_ADMIN_PANEL": "false",
              "COLLECT_MOBILE_EVIDENCE_MODE": "false",
              "AUTH_CAPTCHA_ENABLED": captcha, "AUTH_CAPTCHA_PROVIDER": provider,
              "AUTH_CAPTCHA_SITE_KEY": site_key, "GOOGLE_AUTH_ENABLED": google,
              "COLLECT_GOOGLE_AUTH_ENABLED": google,
              "ENABLE_SMS_READER": "true" if platform == "android" else "false",
              "ENABLE_ANDROID_SMS_ACCESS": "true" if platform == "android" else "false"}
    values.update(profile_defines)
    values.update(feature_flags)
    if platform == "ios":
        values["APNS_ENVIRONMENT"] = "production"
    if "COLLECT_BUILD_SOURCE_ID" in env:
        source = env["COLLECT_BUILD_SOURCE_ID"]
        if not isinstance(source, str) or not re.fullmatch(r"[a-f0-9]{64}", source):
            raise ValueError("Diagnostic source identity must be the exact client source fingerprint")
        values["COLLECT_BUILD_SOURCE_ID"] = source
    return values


def store_candidate_configuration(env, platform, pubspec=None):
    """Require the self-hosted SMS-enabled target for new store candidates.

    Generic native configuration remains available to its existing callers;
    candidate admission must never fall back to the legacy managed profile.
    """
    profile, profile_defines = deployment_configuration(env)
    if (not profile_defines or profile.get("mode") != "self_hosted"
            or profile.get("supabase_origin") == PROJECT):
        raise ValueError("Store candidate requires an explicit self-hosted production profile")
    if env.get("COLLECT_SMS_AUTH_ENABLED") != "true":
        raise ValueError("Store candidate requires SMS authentication enabled")
    return configuration(env, platform, pubspec)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("android", "ios"))
    outputs = parser.add_mutually_exclusive_group(required=True)
    outputs.add_argument("--defines-output", type=Path)
    outputs.add_argument("--validate-defines", type=Path)
    args = parser.parse_args()
    try:
        if args.validate_defines:
            values = json.loads(args.validate_defines.read_text())
            if not isinstance(values, dict) or values != configuration(values, args.platform):
                raise ValueError("Public profile differs from the validated native configuration")
        else:
            values = configuration(dict(os.environ), args.platform)
    except (ValueError, TypeError, OSError) as error:
        parser.error(str(error))
    if args.defines_output:
        args.defines_output.write_text(json.dumps(values, indent=2) + "\n")


if __name__ == "__main__":
    main()
