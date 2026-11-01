#!/usr/bin/env python3
"""Public release configuration only. Never accepts database/provider secrets."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import tempfile
from urllib.parse import urlsplit

try:
    from .deployment_profile import resolve_profile, public_profile_defines
except ImportError:
    from deployment_profile import resolve_profile, public_profile_defines

PROJECT = "rrlduytparvsjfmegalh"
PROJECT_ORIGIN = f"https://{PROJECT}.supabase.co"
ADMIN_ORIGINS = {"https://admin.collect.ikanisa.com", "https://platform-admin.collect.ikanisa.com"}
QUALIFICATION_ORIGIN = "https://admin-supabase-qa.collect.ikanisa.com"
BASELINE = "20261020134444_collect_curated_platform_baseline.sql"

def migration_chain(root: Path) -> list[dict[str, str]]:
    folder = root / 'supabase/migrations'
    files = sorted(path for path in folder.iterdir()
                   if re.fullmatch(r'\d{14}_[a-z0-9_]+\.sql', path.name))
    if not files or files[0].name != BASELINE or any(path.is_symlink() or not path.is_file() or not path.read_bytes().strip() for path in files):
        raise ValueError('Expected the complete curated Supabase migration chain')
    return [{'name': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()} for path in files]

def origin(value: str) -> str:
    parsed = urlsplit(value)
    if (value != value.strip() or parsed.scheme != "https" or not parsed.hostname
            or parsed.username or parsed.password or parsed.port not in (None, 443)
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise ValueError("Public release URLs must be HTTPS origins")
    return f"https://{parsed.hostname}"

def configuration(env: dict[str, str], root: Path, *, qualification: bool = False) -> tuple[dict, dict]:
    profile = resolve_profile(env, qualification=qualification)
    explicit_profile = "COLLECT_DEPLOYMENT_PROFILE" in env or "COLLECT_DEPLOYMENT_PROFILE_SHA256" in env
    backend = env.get("COLLECT_BACKEND", "supabase")
    if backend not in ("cloudflare", "supabase"):
        raise ValueError("Unsupported Collect backend")
    if qualification and backend != "supabase":
        raise ValueError("Admin qualification requires the Supabase backend")
    if explicit_profile and backend != "supabase":
        raise ValueError("A deployment profile requires the Supabase backend")
    public = origin(env.get("APP_PUBLIC_URL", profile["public_origin"] if explicit_profile else "https://collect.ikanisa.com"))
    admin = origin(env.get("ADMIN_APP_URL", profile["admin_origin"] if explicit_profile else "https://platform-admin.collect.ikanisa.com"))
    if not qualification and admin == QUALIFICATION_ORIGIN:
        raise ValueError("The Admin qualification origin requires explicit qualification mode")
    defines = {"APP_PUBLIC_URL": public, "ADMIN_APP_URL": admin,
               "COLLECT_BACKEND": backend, "APP_ENVIRONMENT": f"{backend}-platform",
               "COLLECT_BACKEND_REVISION": f"{backend}-platform-20261020" if backend == "supabase" else "cloudflare-platform-20261014",
               "ENABLE_ADMIN_PANEL": "true", "COLLECT_PUBLIC_LANDING_HOME": "false"}
    if explicit_profile:
        if env.get("APP_ENVIRONMENT", profile["environment"]) != profile["environment"]:
            raise ValueError("Admin environment must match its deployment profile")
        if env.get("SUPABASE_AUTH_ISSUER", profile["supabase_origin"] + "/auth/v1") != profile["supabase_origin"] + "/auth/v1":
            raise ValueError("Admin Auth issuer must use its public Supabase origin")
        defines.update(public_profile_defines(env, qualification=qualification))
        defines["APP_ENVIRONMENT"] = profile["environment"]
    captcha = env.get("AUTH_CAPTCHA_ENABLED", "false")
    if captcha not in ("true", "false"):
        raise ValueError("AUTH_CAPTCHA_ENABLED must be true or false")
    provider = env.get("AUTH_CAPTCHA_PROVIDER", "turnstile" if captcha == "true" else "")
    site_key = env.get("AUTH_CAPTCHA_SITE_KEY", "")
    # Disabled CAPTCHA has no active provider or site key. Do not serialize
    # stale configuration values into the public compiler input.
    if captcha == "false":
        provider, site_key = "", ""
    if captcha == "true" and (provider != "turnstile" or not re.fullmatch(r"[A-Za-z0-9_-]{10,200}", site_key)):
        raise ValueError("Enabled CAPTCHA requires Turnstile and its public site key")
    # These documented public dummy keys do not qualify production protection.
    if not qualification and site_key in {
            "1x00000000000000000000AA", "2x00000000000000000000AB",
            "1x00000000000000000000BB", "2x00000000000000000000BB",
            "3x00000000000000000000FF"}:
        raise ValueError("Production Admin builds cannot use a public CAPTCHA test key")
    if qualification and captcha != "true":
        raise ValueError("Admin qualification requires enabled Turnstile CAPTCHA")
    defines.update({"AUTH_CAPTCHA_ENABLED": captcha, "AUTH_CAPTCHA_PROVIDER": provider,
                    "AUTH_CAPTCHA_SITE_KEY": site_key})
    google = env.get("GOOGLE_AUTH_ENABLED", "false")
    if google not in ("true", "false"):
        raise ValueError("GOOGLE_AUTH_ENABLED must be true or false")
    defines["GOOGLE_AUTH_ENABLED"] = google
    assisted_sms = env.get("COLLECT_ASSISTED_SMS_ENABLED", "false")
    if assisted_sms not in ("true", "false") or assisted_sms == "true" and backend != "supabase":
        raise ValueError("Assisted SMS requires an explicit Supabase public enable flag")
    defines["COLLECT_ASSISTED_SMS_ENABLED"] = assisted_sms
    metadata = {"backend": backend, "authentication": "email_otp_cookie_with_totp",
                "notifications": "provider_configuration_required", "data_strategy": "fresh_cloudflare",
                "legacy_data_import_required": False, "minimum_core_schema_migration": "0017_admin_email_otp.sql",
                "operating_actions_available": False, "operational_migration_complete": False,
                "financial_model": "canonical_evidence_ledger", "financial_contract_version": 2,
                "provider_settlement_available": False}
    if backend == "supabase":
        allowed_admin_origins = {profile["admin_origin"]} if explicit_profile else ({QUALIFICATION_ORIGIN} if qualification else ADMIN_ORIGINS)
        if public != profile["public_origin"] or admin not in allowed_admin_origins:
            raise ValueError("Supabase release must use approved Collect frontend origins")
        project = origin(env.get("SUPABASE_URL", profile["supabase_origin"] if explicit_profile else ""))
        api = origin(env.get("SUPABASE_API_URL", profile["member_api_origin"] if explicit_profile else admin))
        admin_api = origin(env.get("SUPABASE_ADMIN_API_URL", admin))
        key = env.get("SUPABASE_PUBLISHABLE_KEY", "")
        if project != profile["supabase_origin"] or api != (profile["member_api_origin"] if explicit_profile else admin) or admin_api != admin:
            raise ValueError("Admin release requires the nominated project and same-origin transport")
        if not re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{10,300}", key):
            raise ValueError("Admin release requires a public Supabase publishable key")
        migration = root / "supabase/migrations" / BASELINE
        data = migration.read_bytes()
        if not data.strip():
            raise ValueError("Curated Supabase migration is empty")
        defines.update({"SUPABASE_URL": project, "SUPABASE_API_URL": api,
                        "SUPABASE_ADMIN_API_URL": admin_api, "SUPABASE_PUBLISHABLE_KEY": key})
        metadata.update({"authentication": "supabase_auth_cookie_with_email_verification",
                         "data_strategy": "preserve_existing_source", "legacy_data_import_required": True,
                         "minimum_core_schema_migration": BASELINE,
                         "supabase_project_ref": PROJECT if profile["mode"] == "managed" else None,
                         "supabase_schema_sha256": hashlib.sha256(data).hexdigest(),
                         "admin_transport": "same_origin_static_proxy",
                         "admin_origin": admin, "api_origin": api, "admin_api_origin": admin_api,
                         "supabase_qualification_complete": False})
        if explicit_profile:
            metadata.update({"deployment_profile": profile,
                             "deployment_profile_sha256": defines["COLLECT_DEPLOYMENT_PROFILE_SHA256"],
                             "supabase_hosting": profile["mode"],
                             "supabase_auth_issuer": defines["SUPABASE_AUTH_ISSUER"]})
        chain = migration_chain(root)
        metadata.update({'supabase_migrations': chain,
                         'supabase_migration_chain_sha256': hashlib.sha256(json.dumps(chain, sort_keys=True, separators=(',', ':')).encode()).hexdigest()})
    if qualification:
        defines["APP_ENVIRONMENT"] = "qualification"
        metadata.update({"purpose": "qualification", "environment": "qualification",
                         "admin_origin": admin, "qualification_complete": False,
                         "shipping_candidate": False})
    return defines, metadata


def read_public_file(path: Path) -> bytes:
    """Read a bounded physical public input, rejecting links and replacement races."""
    path = path.absolute()
    if path.resolve() != path:
        raise ValueError("Public build input must use a physical path")
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        named = os.lstat(path)
        stamp = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
        if (not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or
                not 0 < before.st_size <= 65536 or stamp(before) != stamp(named)):
            raise ValueError("Invalid public build input")
        data = b""
        while len(data) < before.st_size:
            chunk = os.read(fd, before.st_size - len(data))
            if not chunk:
                raise ValueError("Incomplete public build input")
            data += chunk
        if stamp(before) != stamp(os.fstat(fd)) or stamp(before) != stamp(os.lstat(path)):
            raise ValueError("Public build input changed during inspection")
        return data
    finally:
        os.close(fd)


def verify_public_inputs(defines_bytes: bytes, metadata_bytes: bytes, env: dict[str, str],
                         root: Path, *, qualification: bool = False, binding: bool = False) -> dict:
    """Check the exact post-diagnostic compiler input; not an immutable lease."""
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate public build input field")
            result[key] = value
        return result
    try:
        defines = json.loads(defines_bytes, object_pairs_hook=unique,
                             parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Invalid number")))
        metadata = json.loads(metadata_bytes, object_pairs_hook=unique,
                              parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Invalid number")))
    except (ValueError, UnicodeError, TypeError) as error:
        raise ValueError("Invalid public build input") from error
    expected_defines, expected_metadata = configuration(env, root, qualification=qualification)
    if not isinstance(defines, dict) or not isinstance(metadata, dict):
        raise ValueError("Invalid public build input")
    source = defines.get("COLLECT_BUILD_SOURCE_ID")
    version = defines.get("COLLECT_BUILD_VERSION")
    if (not isinstance(source, str) or not re.fullmatch(r"[a-f0-9]{64}", source) or
            not isinstance(version, str) or not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\+[1-9][0-9]*", version) or
            defines != {**expected_defines, "COLLECT_BUILD_VERSION": version, "COLLECT_BUILD_SOURCE_ID": source} or
            (json.dumps(defines, indent=2) + "\n").encode() != defines_bytes):
        raise ValueError("Public compiler inputs differ from the selected configuration")
    expected_metadata.update({"diagnostics_source_revision": source, "diagnostics_build_version": version})
    hashed = hashlib.sha256(defines_bytes).hexdigest()
    if not binding:
        expected_metadata["public_build_defines_sha256"] = hashed
    if metadata != expected_metadata:
        raise ValueError("Public build metadata does not match compiler inputs")
    return {**expected_metadata, "public_build_defines_sha256": hashed}

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qualification", action="store_true",
                        help="Build only for the approved isolated Admin qualification origin")
    parser.add_argument("--defines-output", type=Path, required=True)
    parser.add_argument("--metadata-output", type=Path, required=True)
    parser.add_argument("--bind-public-input", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--retain-defines", type=Path)
    args = parser.parse_args()
    try:
        if args.bind_public_input or args.verify_only:
            if args.bind_public_input and (args.verify_only or args.retain_defines):
                raise ValueError("Choose one public input operation")
            data = read_public_file(args.defines_output)
            metadata = verify_public_inputs(data, read_public_file(args.metadata_output), dict(os.environ),
                                            Path(__file__).resolve().parents[2], qualification=args.qualification,
                                            binding=args.bind_public_input)
            if args.bind_public_input:
                target = args.metadata_output.absolute()
                fd, temporary = tempfile.mkstemp(prefix='.admin-config-', dir=target.parent)
                try:
                    with os.fdopen(fd, "w") as output:
                        json.dump(metadata, output, indent=2)
                        output.write("\n")
                        output.flush()
                        os.fsync(output.fileno())
                    os.replace(temporary, target)
                finally:
                    if os.path.exists(temporary):
                        os.unlink(temporary)
            if args.retain_defines:
                target = args.retain_defines.absolute()
                if target.parent.resolve() != target.parent:
                    raise ValueError("Retained compiler input must use a physical directory")
                fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
                with os.fdopen(fd, "wb") as output:
                    output.write(data)
            return
        if args.retain_defines:
            raise ValueError("Retaining compiler inputs requires verification")
        defines, metadata = configuration(dict(os.environ), Path(__file__).resolve().parents[2],
                                          qualification=args.qualification)
    except (OSError, ValueError) as error:
        raise SystemExit(f"Invalid Admin public build configuration: {error}") from None
    for output, value in ((args.defines_output, defines), (args.metadata_output, metadata)):
        output.write_text(json.dumps(value, indent=2) + "\n")

if __name__ == "__main__":
    main()
