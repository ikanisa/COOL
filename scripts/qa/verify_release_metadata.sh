#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
METADATA_PATH="${1:-$ROOT_DIR/deeplinks/release_metadata.json}"

python3 - "$METADATA_PATH" <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print(f"Release metadata file not found: {path}", file=sys.stderr)
    sys.exit(1)

data = json.loads(path.read_text(encoding="utf-8"))
android = data.get("android") or {}
ios = data.get("ios") or {}
errors = []

android_package = str(android.get("packageName") or "").strip()
android_upload_fingerprints = [
    str(value).strip()
    for value in android.get("uploadSha256CertFingerprints") or []
    if str(value).strip()
]
android_play_fingerprint = str(
    android.get("playAppSigningSha256CertFingerprint") or ""
).strip()
expected_android_play_fingerprint = os.getenv(
    "COOL_ANDROID_PLAY_APP_SIGNING_SHA256_CERT_FINGERPRINT", ""
).strip()

if not android_package:
    errors.append("Android packageName is missing from deeplinks/release_metadata.json")
if not android_upload_fingerprints:
    errors.append(
        "Android uploadSha256CertFingerprints must contain at least one fingerprint"
    )
if not android_play_fingerprint:
    errors.append(
        "Android playAppSigningSha256CertFingerprint is missing from deeplinks/release_metadata.json"
    )
elif expected_android_play_fingerprint and (
    android_play_fingerprint != expected_android_play_fingerprint
):
    errors.append(
        "Android Play signing fingerprint in deeplinks/release_metadata.json "
        "does not match COOL_ANDROID_PLAY_APP_SIGNING_SHA256_CERT_FINGERPRINT"
    )

ios_release_enabled = os.getenv("COOL_IOS_RELEASE_ENABLED", "0").strip() == "1"
ios_metadata_required = os.getenv("COOL_REQUIRE_IOS_RELEASE_METADATA", "0").strip() == "1"
require_ios_metadata = ios_release_enabled or ios_metadata_required

ios_bundle_id = str(ios.get("bundleId") or "").strip()
ios_team_id = str(ios.get("teamId") or "").strip()
ios_app_store_id = str(ios.get("appStoreId") or "").strip()
expected_ios_team_id = os.getenv("COOL_IOS_TEAM_ID", "").strip()
expected_ios_app_store_id = os.getenv("COOL_IOS_APP_STORE_ID", "").strip()

if not ios_bundle_id:
    errors.append("iOS bundleId is missing from deeplinks/release_metadata.json")

if require_ios_metadata:
    if not ios_team_id:
        errors.append(
            "iOS release metadata is required, but deeplinks/release_metadata.json "
            "has an empty ios.teamId"
        )
    if not ios_app_store_id:
        errors.append(
            "iOS release metadata is required, but deeplinks/release_metadata.json "
            "has an empty ios.appStoreId"
        )
    if expected_ios_team_id and ios_team_id != expected_ios_team_id:
        errors.append(
            "iOS teamId in deeplinks/release_metadata.json does not match COOL_IOS_TEAM_ID"
        )
    if expected_ios_app_store_id and ios_app_store_id != expected_ios_app_store_id:
        errors.append(
            "iOS appStoreId in deeplinks/release_metadata.json does not match COOL_IOS_APP_STORE_ID"
        )

if errors:
    print("Release metadata verification failed:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)

print("==> release metadata verified")
print(f"    android package: {android_package}")
print(f"    android upload fingerprints: {len(android_upload_fingerprints)}")
print(f"    android play signing fingerprint: {android_play_fingerprint}")
if require_ios_metadata:
    print(f"    ios bundle: {ios_bundle_id}")
    print(f"    ios teamId: {ios_team_id}")
    print(f"    ios appStoreId: {ios_app_store_id}")
else:
    print(
        "    ios release metadata: explicitly de-scoped "
        "(set COOL_IOS_RELEASE_ENABLED=1 or COOL_REQUIRE_IOS_RELEASE_METADATA=1 to require it)"
    )
PY
