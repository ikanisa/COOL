#!/usr/bin/env python3
"""Public release configuration only. Never accepts database/provider secrets."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
from urllib.parse import urlsplit

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
    backend = env.get("COLLECT_BACKEND", "supabase")
    if backend not in ("cloudflare", "supabase"):
        raise ValueError("Unsupported Collect backend")
    if qualification and backend != "supabase":
        raise ValueError("Admin qualification requires the Supabase backend")
    public = origin(env.get("APP_PUBLIC_URL", "https://collect.ikanisa.com"))
    admin = origin(env.get("ADMIN_APP_URL", "https://platform-admin.collect.ikanisa.com"))
    if not qualification and admin == QUALIFICATION_ORIGIN:
        raise ValueError("The Admin qualification origin requires explicit qualification mode")
    defines = {"APP_PUBLIC_URL": public, "ADMIN_APP_URL": admin,
               "COLLECT_BACKEND": backend, "APP_ENVIRONMENT": f"{backend}-platform",
               "COLLECT_BACKEND_REVISION": f"{backend}-platform-20261020" if backend == "supabase" else "cloudflare-platform-20261014",
               "ENABLE_ADMIN_PANEL": "true", "COLLECT_PUBLIC_LANDING_HOME": "false"}
    captcha = env.get("AUTH_CAPTCHA_ENABLED", "false")
    if captcha not in ("true", "false"):
        raise ValueError("AUTH_CAPTCHA_ENABLED must be true or false")
    provider = env.get("AUTH_CAPTCHA_PROVIDER", "turnstile" if captcha == "true" else "")
    site_key = env.get("AUTH_CAPTCHA_SITE_KEY", "")
    if captcha == "true" and (provider != "turnstile" or not re.fullmatch(r"[A-Za-z0-9_-]{10,200}", site_key)):
        raise ValueError("Enabled CAPTCHA requires Turnstile and its public site key")
    if qualification and captcha != "true":
        raise ValueError("Admin qualification requires enabled Turnstile CAPTCHA")
    defines.update({"AUTH_CAPTCHA_ENABLED": captcha, "AUTH_CAPTCHA_PROVIDER": provider,
                    "AUTH_CAPTCHA_SITE_KEY": site_key})
    google = env.get("GOOGLE_AUTH_ENABLED", "false")
    if google not in ("true", "false"):
        raise ValueError("GOOGLE_AUTH_ENABLED must be true or false")
    defines["GOOGLE_AUTH_ENABLED"] = google
    metadata = {"backend": backend, "authentication": "email_otp_cookie_with_totp",
                "notifications": "provider_configuration_required", "data_strategy": "fresh_cloudflare",
                "legacy_data_import_required": False, "minimum_core_schema_migration": "0017_admin_email_otp.sql",
                "operating_actions_available": False, "operational_migration_complete": False,
                "financial_model": "canonical_evidence_ledger", "financial_contract_version": 2,
                "provider_settlement_available": False}
    if backend == "supabase":
        allowed_admin_origins = {QUALIFICATION_ORIGIN} if qualification else ADMIN_ORIGINS
        if public != "https://collect.ikanisa.com" or admin not in allowed_admin_origins:
            raise ValueError("Supabase release must use approved Collect frontend origins")
        project = origin(env.get("SUPABASE_URL", ""))
        api = origin(env.get("SUPABASE_API_URL", admin))
        admin_api = origin(env.get("SUPABASE_ADMIN_API_URL", admin))
        key = env.get("SUPABASE_PUBLISHABLE_KEY", "")
        if project != PROJECT_ORIGIN or api != admin or admin_api != admin:
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
                         "supabase_project_ref": PROJECT,
                         "supabase_schema_sha256": hashlib.sha256(data).hexdigest(),
                         "admin_transport": "same_origin_static_proxy",
                         "supabase_qualification_complete": False})
        chain = migration_chain(root)
        metadata.update({'supabase_migrations': chain,
                         'supabase_migration_chain_sha256': hashlib.sha256(json.dumps(chain, sort_keys=True, separators=(',', ':')).encode()).hexdigest()})
    if qualification:
        defines["APP_ENVIRONMENT"] = "qualification"
        metadata.update({"purpose": "qualification", "environment": "qualification",
                         "admin_origin": admin, "qualification_complete": False,
                         "shipping_candidate": False})
    return defines, metadata

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qualification", action="store_true",
                        help="Build only for the approved isolated Admin qualification origin")
    parser.add_argument("--defines-output", type=Path, required=True)
    parser.add_argument("--metadata-output", type=Path, required=True)
    args = parser.parse_args()
    try:
        defines, metadata = configuration(dict(os.environ), Path(__file__).resolve().parents[2],
                                          qualification=args.qualification)
    except (OSError, ValueError) as error:
        raise SystemExit(f"Invalid Admin public build configuration: {error}") from None
    for output, value in ((args.defines_output, defines), (args.metadata_output, metadata)):
        output.write_text(json.dumps(value, indent=2) + "\n")

if __name__ == "__main__":
    main()
