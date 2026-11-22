#!/usr/bin/env python3
"""Export and verify unapproved Collect source.

Only export writes source copies. No command commits, deploys, signs in, requests
an OTP, or attests that a candidate is reviewed/frozen.
"""
from __future__ import annotations

import argparse
import base64
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import selectors
import shutil
import stat
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ".collect-release-candidate.json"
SCHEMA_VERSION = 3
V1_ROOTS = (
    ".github", "admin-web", "lib", "assets", "licenses", "android", "ios", "web", "content",
    "third_party", "deploy", "tools", "scripts", "test",
    "integration_test", "test_driver", "tool", "contracts", "fastlane", "supabase",
)
V1_ROOT_FILES = {
    "AGENTS.md", "README.md", "Makefile", "pubspec.yaml", "pubspec.lock",
    "analysis_options.yaml", ".metadata", ".fvmrc", ".gitignore",
    ".gitleaks.toml", ".env.example", "Gemfile", "Gemfile.lock",
}
NATIVE_ROOTS = ("native/burimunsi", "upstream/collect", "integration/collect-posting",
                "integration/burimunsi/gateway-classification", "integration/burimunsi/provisioning",
                "integration/burimunsi/scope-setup", "tests")
NATIVE_CONTRACT_FIXTURES = {
    "docs/implementation/burimunsi-android/prototype-reference/" + name
    for name in ("index.html", "screen-map.json", "ui-contract.json", "provenance.json")
}
PUBLIC_COPY_READER = "scripts/qa/public_content_contract.rb"
RWANDA_SCOPE_READER = "scripts/tests/rwanda_release_scope_test.py"
PUBLIC_COPY_CONTRACT = "docs/release/public-website-current-content-contract.json"
PRODUCT_DOCUMENT = "docs/PRODUCT.md"
HISTORICAL_COPY_REVIEW = "docs/release/public-content-provenance/historical-comparison.json"
PUBLIC_COPY_HASH_FIELDS = {
    "docs/release/public-website-content-baseline.json": "historical_baseline_sha256",
    HISTORICAL_COPY_REVIEW: "historical_comparison_sha256",
    "docs/release/public-content-provenance/historical-visible-text.json": "historical_visible_text_sha256",
}
RWANDA_RECORDS = {"docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json", "docs/release/RELEASE_BLOCKERS.md"}
PUBLIC_CHECK_DOCUMENTS = {PUBLIC_COPY_CONTRACT, PRODUCT_DOCUMENT, *PUBLIC_COPY_HASH_FIELDS, *RWANDA_RECORDS}
COMPARISON_PATH = re.compile(r"docs/release/public-content-provenance/(?:[a-z0-9]+-)*comparison(?:-[0-9]{8})?\.json")
BROWSER_MEDIA_INDEX = "web/public/app-screens/capture-provenance.json"
BROWSER_MEDIA_PACKET_PREFIX = "content/public-website/app-media/"
BROWSER_MEDIA_PROOF = re.compile(
    rf"(?:docs/implementation/|{re.escape(BROWSER_MEDIA_PACKET_PREFIX)})"
    r"[a-z0-9-]+/(?:capture-report|visual-review)\.json"
)
BROWSER_MEDIA_POLICY = "exact browser screenshot capture report and visual review in " + BROWSER_MEDIA_INDEX
SOURCE_ROOTS = V1_ROOTS + NATIVE_ROOTS
# A filesystem walk must reach separately admitted roots and individual files
# without admitting their siblings, particularly historical documents.
SOURCE_PARENT_DIRECTORIES = {
    str(parent)
    for name in (*NATIVE_ROOTS, *NATIVE_CONTRACT_FIXTURES, *PUBLIC_CHECK_DOCUMENTS)
    for parent in PurePosixPath(name).parents
    if parent != PurePosixPath(".")
}
ROOT_FILES = V1_ROOT_FILES | {".dvmrc", ".supabase-cli-version"}
PRIVATE_NAMES = {
    "key.properties", "local.properties", "google-services.json", "GoogleService-Info.plist",
    "Generated.xcconfig", "MapsKeys.xcconfig", "flutter_export_environment.sh",
    ".flutter-plugins-dependencies", "credentials.json", "service-account.json",
}
BLOCKED_PARTS = {
    "node_modules", "Pods", ".symlinks", ".gradle", ".kotlin", ".dart_tool",
    ".pub-cache", ".pub", ".swiftpm", ".build", ".git", ".cache", ".wrangler",
    "build", "dist", ".vite", "test-results", "coverage", "output", "failures", "__pycache__", "DerivedData", ".temp",
}
BLOCKED_SUFFIXES = {
    ".jks", ".keystore", ".p12", ".pfx", ".p8", ".pem", ".key", ".mobileprovision",
    ".apk", ".aab", ".ipa", ".dSYM", ".class", ".pyc", ".log", ".dump", ".sql.gz",
    ".csv", ".tsv", ".xlsx", ".xls", ".pdf", ".zip", ".tar", ".gz", ".bak", ".old",
}
V1_LOCKS = (
    "pubspec.lock", "Gemfile.lock", "android/app/gradle.lockfile", "ios/Podfile.lock",
    "deploy/platform-api/package-lock.json", "admin-web/package-lock.json",
)
LOCKS = V1_LOCKS + ("deploy/platform-admin/package-lock.json", "scripts/supabase/package-lock.json",
                     "supabase/functions/deno.lock")
V1_REQUIRED = frozenset(V1_LOCKS) | {
    ".fvmrc", "pubspec.yaml", "lib/main.dart", "admin-web/src/main.tsx",
    "admin-web/scripts/build-admin.mjs",
    "deploy/platform-api/src/index.js", "deploy/platform-api/wrangler.jsonc",
    "android/app/build.gradle.kts", "android/gradle/wrapper/gradle-wrapper.properties",
    "android/gradle/wrapper/gradle-wrapper.jar", "ios/Podfile",
    "ios/Runner.xcodeproj/project.pbxproj",
    "supabase/config.toml", "supabase/functions/deno.json", "supabase/functions/deno.lock",
    "supabase/functions/collect-api/index.ts", "supabase/functions/_shared/serve.js",
    "supabase/functions/_shared/postgres.js", "supabase/functions/_shared/domain/index.js",
    "supabase/functions/_shared/domain/operations.js", "supabase/functions/_shared/domain/notifications.js",
    "supabase/migrations/20261020134444_collect_curated_platform_baseline.sql",
}
TOOLCHAIN_INPUTS = {
    ".fvmrc", ".dvmrc", ".supabase-cli-version", "pubspec.yaml", "android/app/build.gradle.kts",
    "android/gradle/wrapper/gradle-wrapper.properties", ".github/workflows/ci.yml", ".github/workflows/supabase.yml",
    ".github/workflows/burimunsi-native.yml", "native/burimunsi/build.gradle.kts",
    "native/burimunsi/app/build.gradle.kts", "native/burimunsi/core/build.gradle.kts",
    "native/burimunsi/settings.gradle.kts", "native/burimunsi/gradle/wrapper/gradle-wrapper.properties",
    "native/burimunsi/scripts/bootstrap_gradle.py", "native/burimunsi/scripts/setup_native_toolchain.py",
}
RECEIVER_MANIFEST = "native/burimunsi/integration/receiver-sources.json"
REQUIRED = V1_REQUIRED | frozenset(LOCKS) | TOOLCHAIN_INPUTS | NATIVE_CONTRACT_FIXTURES | {
    "supabase/functions/_shared/edge-http-handler.js",
    "supabase/functions/_shared/edge-http-transport.js",
    "supabase/functions/_shared/edge-jobs-handler.js",
    "supabase/functions/_shared/edge-job-cycle.js",
    "supabase/functions/_shared/edge-runtime.js",
    "supabase/functions/_shared/email-adapter.js",
    "supabase/functions/_shared/momo-model.js",
    "supabase/functions/_shared/storage/application-pool.js",
    "supabase/functions/_shared/storage/bucket.js",
    "supabase/functions/collect-sms/index.ts",
    "supabase/functions/collect-jobs/index.ts",
    "supabase/functions/admin-api/index.ts",
    "deploy/collect-sms/src/edge.ts",
    "deploy/collect-sms/src/fence.ts",
    "deploy/collect-sms/src/gateway-connection.ts",
    "deploy/collect-sms/src/gateway-runtime.ts",
    "supabase/functions/_shared/postgres-connections.js",
    "supabase/functions/_shared/postgres-transactions.js",
    "supabase/functions/_shared/postgres-compatibility-sql.js",
    RECEIVER_MANIFEST, "native/burimunsi/gradlew", "native/burimunsi/scripts/prepare_receiver.py",
    "native/burimunsi/scripts/native_pipeline.py", "native/burimunsi/app/src/main/AndroidManifest.xml",
    "native/burimunsi/app/src/staff/AndroidManifest.xml", "native/burimunsi/app/src/internal_receiver/AndroidManifest.xml",
    "native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/BuriApplication.kt",
    "integration/collect-posting/payments.js", "tests/uiux_contract_test.py",
}
PUBLIC_CONFIG_PREREQUISITES = (
    "android/app/google-services.json", "ios/Runner/GoogleService-Info.plist",
)
MAXIMUM_SOURCE_FILE = 128 * 1024 * 1024
NO_APPROVAL = {
    "trusted_source_verified": False, "reviewed": False, "frozen": False,
    "owner_approved": False, "signed": False, "production_release_accepted": False,
}


class ReleaseError(ValueError):
    def __init__(self, code: str, paths: list[str] | None = None):
        super().__init__(code)
        self.code, self.paths = code, paths or []


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def safe_relative(name: str) -> str:
    path = PurePosixPath(name)
    if not name or path.is_absolute() or ".." in path.parts or "\\" in name or "\0" in name:
        raise ReleaseError("CANDIDATE_PATH_INVALID")
    if any(ord(char) < 32 for char in name):
        raise ReleaseError("CANDIDATE_PATH_INVALID")
    return str(path)


def public_check_document(name: str) -> bool:
    return (name in PUBLIC_CHECK_DOCUMENTS or COMPARISON_PATH.fullmatch(name) is not None
            or BROWSER_MEDIA_PROOF.fullmatch(name) is not None)


def exclusion(name: str, *, historical_roots=None, public_inputs=None) -> str | None:
    path = PurePosixPath(name)
    if path.name in PRIVATE_NAMES or (path.name.startswith(".env") and path.name != ".env.example"):
        return "private_configuration"
    if any(part in BLOCKED_PARTS or part.startswith("build_stale_") for part in path.parts):
        return "cache_or_build_output"
    if len(path.parts) >= 3 and path.parts[0] == "third_party" and path.parts[2] == "test":
        return "upstream_qa_fixture_source"
    if path.suffix.lower() in BLOCKED_SUFFIXES or path.name.startswith("GoogleService-Info-") or any(part.endswith(".dSYM") for part in path.parts):
        return "private_artifact_or_payload_format"
    if historical_roots is not None:
        return None if path.parts[0] in historical_roots or name in V1_ROOT_FILES else "outside_declared_source_scope"
    if path.suffix.lower() == ".backup":
        return "private_artifact_or_payload_format"
    # When the browser index selects a canonical media packet, admit only its
    # two hash-bound proof files from the media evidence directory.
    if (name.startswith(BROWSER_MEDIA_PACKET_PREFIX) and public_inputs is not None
            and any(source.startswith(BROWSER_MEDIA_PACKET_PREFIX) for source in public_inputs)):
        return None if name in public_inputs else "outside_declared_source_scope"
    if path.parts[0] in V1_ROOTS or name in V1_ROOT_FILES:
        return None
    # A workdir walk can observe an unexpected comparison file. Capturing a
    # source snapshot admits only the exact path and digest in its copy contract.
    if (public_check_document(name) if public_inputs is None else name in public_inputs):
        return None
    if name in ROOT_FILES or name in NATIVE_CONTRACT_FIXTURES or any(name == root or name.startswith(root + "/") for root in NATIVE_ROOTS):
        return None
    return "outside_declared_source_scope"


def policy() -> dict:
    return {"git_selection": "tracked plus nonignored untracked; missing indexed files recorded as absent",
            "source_roots": list(SOURCE_ROOTS), "top_level_source_files": sorted(ROOT_FILES),
            "excluded_path_components": sorted(BLOCKED_PARTS), "excluded_names": sorted(PRIVATE_NAMES),
            "excluded_suffixes": sorted(BLOCKED_SUFFIXES | {".backup"}),
            "native_contract_fixtures": sorted(NATIVE_CONTRACT_FIXTURES),
            "source_check_documents": sorted(PUBLIC_CHECK_DOCUMENTS),
            "public_comparison": "exact current_comparison_file and SHA-256 in the reviewed copy contract",
            "public_browser_media": BROWSER_MEDIA_POLICY,
            "additional_exclusions": ["remaining docs/release and other paths outside the listed source inputs", "private .env files",
                                     "GoogleService-Info variant files", "build_stale_*",
                                     "third_party/*/test/** upstream QA/auth fixtures; runtime and provenance retained"],
            "symlinks": "refused for source and candidate paths, including ancestor symlinks",
            "migration_versions": {"new": "unique positive 14-digit Supabase timestamp filename version in supabase/migrations"},
            "credential_screening": "recognized private-key/token patterns only; no security or privacy attestation"}


def git_names(root: Path) -> list[str]:
    try:
        raw = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                                      cwd=root, stderr=subprocess.DEVNULL)
        names = sorted({safe_relative(item.decode("utf-8")) for item in raw.split(b"\0") if item})
    except (OSError, subprocess.SubprocessError, UnicodeError) as error:
        raise ReleaseError("CANDIDATE_GIT_REQUIRED") from error
    return names


def regular_bytes(root: Path, name: str) -> tuple[bytes, int]:
    path = root
    for part in PurePosixPath(safe_relative(name)).parts:
        path = path / part
        if path.is_symlink():
            raise ReleaseError("CANDIDATE_SYMLINK_REFUSED", [name])
    try:
        before = path.stat()
        if not stat.S_ISREG(before.st_mode) or before.st_size > MAXIMUM_SOURCE_FILE:
            raise ReleaseError("CANDIDATE_SOURCE_FILE_INVALID", [name])
        # O_NOFOLLOW also refuses replacement of the final component at open.
        directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0))
        try:
            parts = PurePosixPath(name).parts
            for part in parts[:-1]:
                next_directory = os.open(part, os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0), dir_fd=directory)
                os.close(directory)
                directory = next_directory
            descriptor = os.open(parts[-1], os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0), dir_fd=directory)
        finally:
            os.close(directory)
        with os.fdopen(descriptor, "rb") as handle:
            data = handle.read(MAXIMUM_SOURCE_FILE + 1)
            after = os.fstat(handle.fileno())
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns) or len(data) != before.st_size:
            raise ReleaseError("CANDIDATE_SOURCE_CHANGED", [name])
        return data, stat.S_IMODE(after.st_mode)
    except FileNotFoundError as error:
        raise ReleaseError("CANDIDATE_SOURCE_MISSING", [name]) from error


TOKEN_PATTERNS = (
    rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----(?:\r?\n|\\n)[A-Za-z0-9+/]{20,}",
    rb"\bgh[pousr]_[A-Za-z0-9]{30,}\b",
    rb"\bgithub_pat_[A-Za-z0-9_]{40,}\b",
    rb"\bAKIA[A-Z0-9]{16}\b",
    rb"\bsk_(?:live|test)_[A-Za-z0-9]{20,}\b",
    rb"\bsk-proj-[A-Za-z0-9_-]{30,}\b",
    rb"(?i)\b(?:[a-z][a-z0-9_-]{0,31}[_-])?(?:secret|token|key)[_-][a-z0-9_-]{20,}\b",
)
JWT_PATTERN = re.compile(rb"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{16,}\b")


# Finite reviewed generic-pattern false positives. These exact source-line
# hashes cover public identifiers/enums and controlled local-test/sentinel
# literals. They are not a test-directory, synthetic-prefix or value allowlist.
# Any line/path change requires review again. Provider/private-key/JWT/JSON
# credential screening never consults this narrow generic-only context map.
MANAGED_JOBS_FIELD_NAME_LINES = frozenset((
    '476174d846c79a24e2bee3cf9ea957712b19f2c0f3059ffd80db4bb701cea7d8',
    'cfbb6e443d3feb8fd822e12c0229254ceda1baf0d18f9fe71884426b0764885e',
))
GENERIC_PUBLIC_SOURCE_LINES = {
    'supabase/migrations/20261117073850_collect_managed_jobs_hmac.sql': MANAGED_JOBS_FIELD_NAME_LINES,
    'supabase/migrations/20261117081411_collect_native_provider_budget.sql': MANAGED_JOBS_FIELD_NAME_LINES,
    'supabase/migrations/20261117134926_collect_native_provider_policy.sql': MANAGED_JOBS_FIELD_NAME_LINES,
    'scripts/supabase/managed-auth-archive/REFERENCE.json': frozenset(('50e1fbcc6b1c97dab6d541fb2e342bdcb64b48efa5fc66a3757713d654b233d4',)),
    'scripts/supabase/current-archive/bundle.mjs': frozenset(('319c34a67f96775c5fcfd8bdd0b0d0798a34ae0d447b11b9eda3cf163612e06c', 'a927d44911a34e7c6150d7de97018f6cfccdd3c8a46bce0c8c318e25e7c99af4')),
    'scripts/supabase/current-archive/operator.mjs': frozenset(('729d146227251983ef7c5e6e3ca6fd6cee64029af78e243e903479f1c4e0a59b',)),
    # A returned operation status and a schema field name for a key digest.
    'scripts/supabase/cloud-release/native-source-rebind-operator.mjs': frozenset((
        '94894a1d986de90f8ecfcd06a352fb3deb0f63a9c0b31e0aecd8d13787bb0078',
    )),
    'scripts/supabase/email_jobs_operator.mjs': frozenset((
        'c1e50af35abac276533f1b40aff0463e450f227a2fd59205ff3961dd98fe23aa',
    )),
    'supabase/jobs/email-bootstrap.sql': frozenset((
        'a6f03db6def5b515803df8a0d0cf77bf7216e189db3c4d19528afeade6ddf237',
        '7e9e66345e8dc636316518cb5ab6cbd531b4b194a76028cebc39ec27b94edeb0',
    )),
    'analysis_options.yaml': frozenset(('856267bb9cf05544b1bcb7d4d635d83ac98958944f91beed38364eb4c57f65d8',)),
    'scripts/cloudflare/platform_backup.mjs': frozenset(('a1f14510f3749b00a91675a3b70f4a3b7c40571294012ce38f2af72b33222b5d', '9a1e5335ffeeb9b237d40ba61e5428353709302f17e837c056da3fcb29b4ed64',)),
    'scripts/cloudflare/recovery_quarantine.mjs': frozenset(('cf3a20cafbefa427e3d42d11827593fb70907c381a1abb320486a48e15fae28b', '6c91bd6f58aa2dddfd5fe93b42c2124db9851adb360411e1df34c089c4ab6f7e',)),
    'scripts/google_play_production_upload.sh': frozenset(('11b90dfa9d26f3a2dbdaecb851bc9b35b5a5f14eedcbf587b914f0ba2e9b4821', 'f334a4c917a986e56bbf2466102fde704bcd049fbc6b8eebdeab1e1b1d81effb', '45c2f74fbd50c5be11a5410cd1c7c36904fe6b5af7587f2676db58f54a999ab0')),
    'scripts/tests/asset_hygiene_integration_test.rb': frozenset(('27b2228008849b62e74ff9308730c9031f0552dedbe0377af4bca0cff3c15ce8',)),
    'scripts/tests/recovery_quarantine_test.mjs': frozenset(('6b8f601643230bc408b6a1235d24509d11a83318a53438548cc5e101e9f54dce', 'f0b8bfd32fc3cd0e86cef7cce32b4ef3f8da8018fb16d7603bca7fa43993bc65')),
    'scripts/tests/test_collect_release_candidate.py': frozenset(('b22103bcb6205d0e5afbda5722db14d82dc1e18c2a437d20e74f89abb3fe7309',)),
    'tools/roster-decoder/test_dependency_security.py': frozenset(('a8be53a19391ee14c5b8b8c087e7b50e47add3048e8c3ad851bcd309c5b81356', 'fb0decb938601040642d4d7a764ef65fcc56e4dcac7ea3561f893edd09a0651f')),
    'scripts/supabase/jobs_config.mjs': frozenset((
        '3b3410b3796bcc5eed3fedc5613be9cb758406e55203588642ffa2d7a27c0279',
        'af03da7f6de3aafb23e7fe876bb5d4eaaa40b1363c488828c118f990de94653b',
    )),
    'scripts/supabase/jobs_test.mjs': frozenset(('f8d9eae32a8476ceae2e6aab8e60d75594120f1790dd1544f293c7570859d31e',)),
    'supabase/jobs/bootstrap.sql': frozenset((
        '34767fdf18de63e4c1fe888efa504fae83ee5d17668569ef4000258bb59ff435',
        '476174d846c79a24e2bee3cf9ea957712b19f2c0f3059ffd80db4bb701cea7d8',
        'b94efecd6e94b374618225799db97a308d996f822211e80485b93a5f4cd8022d',
        'c345c388eceb858060dd02595ba77cbb49e36e6a0eb83ddb229b55c7ad689314',
    )),
    'supabase/jobs/readiness.example.json': frozenset(('9dc52c463d96162b2ce8dfe256cf0df5b13e4c78e239356074d41b9f8433e6d3',)),
    'scripts/supabase/cloud-data-transfer/fenced-recovery-custody.mjs': frozenset((
        '1c80f9b691d10dab8264f1365926b7af73849867af8297fa079b59fbc587697e',
        '60772d2849a092918e11f87a50c91461db1d6729ec968cbe5828fac911934152',
        '6e99ed383aa642ac4a75cbfbf3f404005b74d184349561acb8496c6a7a54f2ab',
    )),
    'scripts/supabase/cloud-data-transfer/recovery-capsule.mjs': frozenset(('5b8b87feeb4877ec6d449b876bfb4b2af95b0ac844da470c02bed6c978964aaa',)),
    'scripts/supabase/cloud-release/managed-jobs-key-operator.mjs': frozenset((
        '1137b4127bf15c1ecb2562c17b69ee096c3841d17d7be5d0e473cf5ecf23e3b6',
        '17528d69d072bf026417a9d16c4082314fdf0c178d0eee4c7b7a095647c58d29',
        '2a574e59f25aee55f5f866be1376c8c9db0e4daec1a2335512325d85441c47b7',
        '3128f4be681e42f8c36814e768f3ac389b79c0fb3950b760b40c750f3f1cd964',
        '6d150aba136f445699211c2c8823d30e5a516cdb2e68bafa0873cf27cfbccdfe',
        'd72933fdea64efbd092f114f34681271c0b17d4b7789c6a8fbb7894011d1ec48',
    )),
    'scripts/supabase/current-pg-transfer/encrypted-inert-restore/managed_restore_test.py': frozenset(('315df0b24e0308a93de55e53269ecc45e6be107c79cba3e2360d3a83c63c6749',)),
    'scripts/supabase/current-pg-transfer/financial-inventory/README.md': frozenset(('cf25e6360e5de1af851ca08701404e4b5a11b604bd567f6726fc636fe1baafb5',)),
    'scripts/supabase/current-pg-transfer/financial-inventory/inventory.sql': frozenset(('2d3c599e643efd3384f7e25701cdca17d195b94a236142d79a5383c7d088557f',)),
    'scripts/supabase/managed-edge-capture-live-v1/core.mjs': frozenset(('90160257b22554eba12d8282361691550a5d0cf011f34e7ad8a5b3870593f8e7',)),
    'scripts/supabase/managed-edge-capture-live-v2/core.mjs': frozenset(('90160257b22554eba12d8282361691550a5d0cf011f34e7ad8a5b3870593f8e7',)),
    'scripts/supabase/managed-edge-capture-live-v2/offline.mjs': frozenset((
        '17c9efb2a4fbc046275b0b88e6b28af60b627fa58e6bae9c82942a2ad5336419',
        '538dffd60543a08c6a8ab381b52467116c18d56fd9332681d473a3718876299f',
    )),
    'scripts/supabase/managed-edge-capture-live-v3/core.mjs': frozenset(('90160257b22554eba12d8282361691550a5d0cf011f34e7ad8a5b3870593f8e7',)),
    'scripts/supabase/managed-edge-capture-live-v3/managed-edge-capture-live-v2/core.mjs': frozenset(('90160257b22554eba12d8282361691550a5d0cf011f34e7ad8a5b3870593f8e7',)),
    'scripts/supabase/managed-edge-capture-live-v3/managed-edge-capture-live-v2/offline.mjs': frozenset((
        '17c9efb2a4fbc046275b0b88e6b28af60b627fa58e6bae9c82942a2ad5336419',
        '538dffd60543a08c6a8ab381b52467116c18d56fd9332681d473a3718876299f',
    )),
    'scripts/supabase/managed-edge-capture-live-v3/offline.mjs': frozenset((
        '17c9efb2a4fbc046275b0b88e6b28af60b627fa58e6bae9c82942a2ad5336419',
        '538dffd60543a08c6a8ab381b52467116c18d56fd9332681d473a3718876299f',
    )),
    'scripts/supabase/managed-edge-capture/capture.mjs': frozenset(('90160257b22554eba12d8282361691550a5d0cf011f34e7ad8a5b3870593f8e7',)),
    'supabase/jobs/EMAIL.md': frozenset(('17a2f21c721322a422151a03e280197164016943f0e60eda5bb150045d1f6d69',)),
    'supabase/jobs/readiness.combined.example.json': frozenset(('9dc52c463d96162b2ce8dfe256cf0df5b13e4c78e239356074d41b9f8433e6d3',)),
    'supabase/jobs/readiness.notifications.example.json': frozenset(('9dc52c463d96162b2ce8dfe256cf0df5b13e4c78e239356074d41b9f8433e6d3',)),
    'supabase/jobs/readiness.processing.example.json': frozenset(('9dc52c463d96162b2ce8dfe256cf0df5b13e4c78e239356074d41b9f8433e6d3',)),
}
GENERIC_CONTROLLED_TEST_LINES = {
    'scripts/supabase/cloud-release/native-source-rebind-operator.test.mjs': frozenset((
        'd79e584b98020f74298a6dae413c4707f7e253fae706df5fac3e8b90ae01cc65',
    )),
    'scripts/supabase/email_jobs_operator.test.mjs': frozenset((
        '3247ec7af27d1b2238eb18060dbe926dac62c1863f47a62efdf2536509562330',
    )),
    'scripts/supabase/current-archive/custody.test.mjs': frozenset(('4b33e736bdd3a71e90adb04ae6a5d7d011ed0c9b52105e2f297a71610b43f3ed',)),
    'scripts/supabase/current-archive/operator.test.mjs': frozenset(('4774b2b622d6ad339ea76149a0b7c26f188922a346acfefc76733eeb2fb3d85a',)),
    'scripts/supabase/current-archive/root-curated.fixture.mjs': frozenset(('6db1fab4cd4788e610f75a3d853749f6a70bd40b71b7c40368cbaf19f68bf0fe',)),
    'scripts/supabase/current-archive/transport.test.mjs': frozenset(('99203b25e976f24e3fd48ebbae35a4f9a0f9c53050efe0a8d5177385366ab5a1',)),
    'scripts/tests/cloudflare_native_build_config_test.py': frozenset(('f4c920494f2c5c9d5062c8732e386eb557592d7b9a311d6aee8d7163d6b9ae52',)),
    'supabase/functions/_shared/tests/momo-provider-adapter.test.ts': frozenset(('142f3d03b7e36c290764d790e237af5b28b45e9ebd96bb8d1bb8d3d5cc7200e2',)),
    'deploy/platform-api/test/admin_support/fixture.mjs': frozenset(('b8f680a12042e47cc9f8398a51d95508a2b1d3daeafdeb28328ca8b1962e27be',)),
    'deploy/platform-api/test/auth_identity_keys.test.mjs': frozenset(('498236e1813058d295db3c2ce6039aa1d80016a3513fea8dc3e09e4ded168cbd',)),
    'deploy/platform-api/test/notification_registration.test.mjs': frozenset(('993cec7e3828a5021f6ea6687f328f7fc8af13fd88e6ead234f72f0edcc79a4b', 'b3219bae68cafbc32c8154f9895467449dec8c7e791b97ac47b70554a664b0ca')),
    'deploy/platform-api/test/receipt_security.test.mjs': frozenset(('c4279a99ac17285bbc6b58ff8d44eec1052922efeede4e50540ac1d73baa3302', '5bb5bdd90ff4c4aca553dea9f9ac51452ad86f3939e9b5dc47067df1fde22ea9',)),
    'deploy/platform-api/test/security.test.mjs': frozenset(('899216460b79bffe835660108d3fc3818ab4efdde5a8fcceabecb357f4bbeeb3',)),
    'deploy/platform-api/test/support/auth_fixture.mjs': frozenset(('9cdb871bd9e0e914971725f8f3d6da6b1642a675548137e97449a3379969127a', 'b45094f0a90749d740361f1aebfba43c411c2cf2f90ff75f97dd065439d5e6e0')),
    'deploy/platform-api/test/support/retention_fixture.mjs': frozenset(('ec5cb9e27e403649cc45686afc20e595aed9cf9096a1c5a317d1b60173272464',)),
    'scripts/tests/atomic_d1_restore_test.mjs': frozenset(('a2d6636439a4479f653a7469b9fd697d8f3ed31eed40a97ffbb7da043e44e626',)),
    'scripts/tests/recovery_quarantine_test.mjs': frozenset(('a2d6636439a4479f653a7469b9fd697d8f3ed31eed40a97ffbb7da043e44e626', 'f446331f6e399801bffea3df0c25f1aa29149a1d5aeb85b6c696971fda067e4c')),
    'test/features/privacy/privacy_request_screen_test.dart': frozenset(('1292980b41b16c96101735aabbf85ef74339dcf14791d6058d5f9ccd53843fcd',)),
    'deploy/platform-api/test/admin_member_support/fixture.mjs': frozenset(('b8f680a12042e47cc9f8398a51d95508a2b1d3daeafdeb28328ca8b1962e27be',)),
    'deploy/platform-api/test/admin_sms_support/fixture.mjs': frozenset(('b8f680a12042e47cc9f8398a51d95508a2b1d3daeafdeb28328ca8b1962e27be',)),
    'deploy/platform-api/test/support/notification_operator_fixture.mjs': frozenset(('b8f680a12042e47cc9f8398a51d95508a2b1d3daeafdeb28328ca8b1962e27be',)),
    'deploy/platform-api/test/support/notification_operator_integration_fixture.mjs': frozenset(('b8f680a12042e47cc9f8398a51d95508a2b1d3daeafdeb28328ca8b1962e27be',)),
    'deploy/platform-api/test/support/recovery12_fixture.mjs': frozenset(('9c24b0cb55086932a6b4b026c2d3d461535726d6d9a376fdf28a17e5c2a071ff',)),
    'scripts/supabase/jobs_test.mjs': frozenset(('2a80c6dd0136f09280d7485ce7f16430157e65371e0fc7c6e4752a0c0d912d96', 'c29ed4b2c25f339fc4461ef052cb03fe4d179ff3d16fddb9bd0508fc293f2c2a', 'f2a52815df0cfec16be68969f0f42fee177be8d8afed5ee76962b235e53941dc')),
    'scripts/tests/fixtures/recovery_profile11.mjs': frozenset(('fc033c5db79f98c4e7095c5a653c4a3b3cd5dde4ca0a701b63de9df433f33fc0',)),
    'scripts/tests/recovery_auth17_qualification_test.mjs': frozenset(('e42c05fcbbf4bd5d53e0bdf168cdc9d210c052ce5c13ce0838ca6bd7b0bb4e08', 'e6fecaf00b20b4aaa4f753eddd0294bc494112f3753edf873ebeb49e971f9550')),
    'supabase/functions/_shared/tests/admin-invitation-notice-pg.test.ts': frozenset(('f8be6b29f4244e83829217a4e00453333819f33b76b6676d837dcacd6cf45fba',)),
    'supabase/functions/_shared/tests/admin-invitation-pg.test.ts': frozenset(('3e028be2bff3a4b32af887e5a71cd93814ae80a8f42599c7a84bd379b58d8482',)),
    'supabase/functions/_shared/tests/admin-invitation.test.mjs': frozenset(('3e5a140e690508c639512c4e10705f3e170b8fea0b25cf5427ab410400d077f1',)),
    'supabase/functions/_shared/tests/auth-http-logout.test.mjs': frozenset(('7c5782544b7173731e6edbed8d91959540e392a7f298dc3dd246448b1bdcc2b7',)),
    'supabase/functions/_shared/tests/native-storage-semantics.test.mjs': frozenset(('4e15abd270a859b19fbfbfbc7e62ddd1cfa707b3b3cfc417501cf3ea8714092c',)),
    'supabase/functions/_shared/tests/private-retention.test.ts': frozenset(('1cd9abc4d868b7632e4a8cbf4dbfe376df92cddfe29f236a1382eee6932b3289',)),
    'supabase/functions/_shared/tests/runtime.test.ts': frozenset(('038976233490c2f7fd76d34df7712b6793e2cda7dfabcd2516ce1398e0833d94',)),
    'native/burimunsi/pipeline-tests/native_execution_test.py': frozenset(('393668f70fe6020ba9e692ebd4c4c6f1230a839f2adeb816da535f60a5b40dc5',)),
    'scripts/supabase/cloud-data-transfer/recovery-capsule.test.mjs': frozenset(('9fc402386d63009dc5122e52b47f3d9e8cc9c545f190bac7771e4a842df0f917',)),
    'scripts/supabase/cloud-release/managed-jobs-operator.test.mjs': frozenset(('51131968d46312b566024994e0c1a61ea1da4a65dde85c16569420581e8464ab',)),
    'scripts/supabase/cloud-release/managed-jobs-schedule-one-minute.test.mjs': frozenset(('04674d5d5716c158654aee3d568ad24191557d76e0b231248d4eacaebfcbe01f',)),
    'scripts/supabase/cloud-release/managed-jobs-scheduler.test.mjs': frozenset(('04674d5d5716c158654aee3d568ad24191557d76e0b231248d4eacaebfcbe01f',)),
    'scripts/supabase/cloud-release/native-provider-budget.test.mjs': frozenset(('665da68a8e338cca2e32bbfdd663d97852332e271377b08280a8ea67cc7c976c',)),
    'scripts/supabase/cloud-release/native-provider-policy.test.mjs': frozenset(('cf7bf7269a2bc14f15d63a1a306798ce8114df2e9bb0e5133f06cd2a86a2e02d',)),
    'scripts/supabase/current-pg-transfer/financial-inventory/inventory.test.mjs': frozenset(('cb65ce3d67dae305abe7cc335f40543de61af4a3f98efedac556bacc39a964e5',)),
    'scripts/supabase/jobs-config-contracts.test.mjs': frozenset(('f8d9eae32a8476ceae2e6aab8e60d75594120f1790dd1544f293c7570859d31e',)),
    'scripts/supabase/managed-component-refresh/preflight.test.mjs': frozenset((
        '1b9b61ee42da7b0d824e5f8b615a2544503326e2e12a46d78babb00d09db8edb',
        '8f2f5ec80115e09f7b740cc10da2c35b3bc2f41009aeba82a48ace05446f42a8',
    )),
    'scripts/supabase/testing/jobs-predecessor.sql': frozenset((
        '34767fdf18de63e4c1fe888efa504fae83ee5d17668569ef4000258bb59ff435',
        'c345c388eceb858060dd02595ba77cbb49e36e6a0eb83ddb229b55c7ad689314',
    )),
    'scripts/tests/osv_package_readback_test.py': frozenset(('4e92257bb704be688dc0c4109e6073a528559f11cea9ee5bdfa9f3dd3516a460',)),
    'scripts/tests/test_collect_ci_policy.py': frozenset(('3a9c03d7f0877790013d60f747454830d7b94b45ced05a323f2dcca19893d73c',)),
    'supabase/functions/_shared/tests/burimunsi/storage-witness-fixture.mjs': frozenset(('1d8455cd25719391a3b8a5c250a84f29aaf793a0ae38e76616d9468c56aa7fc9',)),
    'supabase/functions/_shared/tests/known-member-bootstrap.test.mjs': frozenset(('86c895bbf1d5a0a3688aa7eaf085ab8594df21cea9bac31a97954a501554d5a6',)),
    'tests/uiux_contract_test.py': frozenset(('dd74547d41f7146ab84ba14fe5b61563fcb315443759b4f65ead129a29a837dc',)),
}


def reviewed_generic_line(data: bytes, name: str, match: re.Match[bytes]) -> bool:
    start = data.rfind(b"\n", 0, match.start()) + 1
    end = data.find(b"\n", match.end())
    if end == -1:
        end = len(data)
    line_hash = sha(data[start:end])
    return (line_hash in GENERIC_PUBLIC_SOURCE_LINES.get(name, ()) or
            line_hash in GENERIC_CONTROLLED_TEST_LINES.get(name, ()))


def screen_credentials(data: bytes, name: str) -> None:
    for index, pattern in enumerate(TOKEN_PATTERNS):
        for match in re.finditer(pattern, data):
            if index == 6 and reviewed_generic_line(data, name, match):
                continue
            raise ReleaseError("CANDIDATE_CREDENTIAL_PATTERN", [name])
    for match in JWT_PATTERN.finditer(data):
        token = match.group().split(b".")
        if token[2].startswith(b"synthetic_signature_"):
            continue
        try:
            claims = json.loads(base64.urlsafe_b64decode(token[1] + b"=" * (-len(token[1]) % 4)))
        except (ValueError, UnicodeError):
            raise ReleaseError("CANDIDATE_CREDENTIAL_PATTERN", [name])
        raise ReleaseError("CANDIDATE_CREDENTIAL_PATTERN", [name])
    if PurePosixPath(name).suffix == ".json" and data.lstrip().startswith((b"{", b"[")):
        try:
            value = json.loads(data)
        except (ValueError, UnicodeError):
            return
        pending = [value]
        credential_keys = {"access_token", "refresh_token", "client_secret", "private_key", "secret_key", "service_role_key"}
        while pending:
            item = pending.pop()
            if isinstance(item, dict):
                for key, content in item.items():
                    if key.lower() in credential_keys and isinstance(content, str) and content and not content.startswith(("synthetic_", "placeholder_", "example_")):
                        raise ReleaseError("CANDIDATE_CREDENTIAL_PATTERN", [name])
                    if isinstance(content, (list, dict)):
                        pending.append(content)
            elif isinstance(item, list):
                pending.extend(child for child in item if isinstance(child, (list, dict)))


def verify_receiver_inputs(root: Path, files: dict) -> None:
    try:
        raw, _ = regular_bytes(root, RECEIVER_MANIFEST)
        if sha(raw) != files[RECEIVER_MANIFEST]["sha256"]:
            raise ReleaseError("CANDIDATE_RECEIVER_INPUT_CHANGED", [RECEIVER_MANIFEST])
        contract = json.loads(raw)
        folder = safe_relative(contract["root"])
        members = contract["files"]
        if not isinstance(members, dict) or not 1 <= len(members) <= 64:
            raise ValueError()
        for name, expected in members.items():
            if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*\.kt", name) or not re.fullmatch(r"[0-9a-f]{40}", expected):
                raise ValueError()
            path = f"upstream/collect/{folder}/{name}"
            if path not in files:
                raise ReleaseError("CANDIDATE_PREREQUISITE_MISSING", [path])
            data, _ = regular_bytes(root, path)
            blob = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
            if blob != expected or sha(data) != files[path]["sha256"]:
                raise ReleaseError("CANDIDATE_RECEIVER_INPUT_CHANGED", [path])
    except ReleaseError:
        raise
    except (TypeError, ValueError, KeyError) as error:
        raise ReleaseError("CANDIDATE_RECEIVER_MANIFEST_INVALID", [RECEIVER_MANIFEST]) from error


def browser_media_evidence(root: Path, names) -> dict[str, str]:
    if BROWSER_MEDIA_INDEX not in names:
        return {}
    raw, _ = regular_bytes(root, BROWSER_MEDIA_INDEX)
    try:
        index = json.loads(raw)
        if index.get("kind") != "browser_flutter_fixture":
            return {}
        if index.get("status") != "pass" or index.get("native_capture_passed") is not False:
            raise ValueError()
        selected = {}
        for field in ("capture_report", "visual_review"):
            name, digest = index[field], index[field + "_sha256"]
            if (not isinstance(name, str) or BROWSER_MEDIA_PROOF.fullmatch(name) is None
                    or PurePosixPath(name).stem != field.replace("_", "-")
                    or not isinstance(digest, str) or re.fullmatch(r"[a-f0-9]{64}", digest) is None):
                raise ValueError()
            selected[name] = digest
        if len({PurePosixPath(name).parent for name in selected}) != 1:
            raise ValueError()
        return selected
    except (AttributeError, KeyError, TypeError, ValueError) as error:
        raise ReleaseError("CANDIDATE_BROWSER_MEDIA_INDEX_INVALID", [BROWSER_MEDIA_INDEX]) from error


def source_check_inputs(root: Path, names, *, include_browser_media=True) -> dict:
    selected = dict.fromkeys(RWANDA_RECORDS) if RWANDA_SCOPE_READER in names else {}
    if include_browser_media:
        selected.update(browser_media_evidence(root, names))
    if PUBLIC_COPY_READER not in names:
        return selected
    raw, _ = regular_bytes(root, PUBLIC_COPY_CONTRACT)
    try:
        contract = json.loads(raw)
        if (type(contract["schema_version"]) is not int or contract["schema_version"] != 1
                or contract["status"] != "local_engineering_reviewed"
                or contract["publication_approved"] is not False or contract["legal_release_approved"] is not False):
            raise ValueError()
        current = contract.get("current_comparison_file", HISTORICAL_COPY_REVIEW)
        if not isinstance(current, str) or COMPARISON_PATH.fullmatch(current) is None:
            raise ValueError()
        hashes = {name: contract[field] for name, field in PUBLIC_COPY_HASH_FIELDS.items()}
        current_hash = contract.get("current_comparison_sha256", hashes[HISTORICAL_COPY_REVIEW])
        if current in hashes and hashes[current] != current_hash:
            raise ValueError()
        hashes[current] = current_hash
        reviewed = contract["reviewed_source_sha256"]
        if not isinstance(reviewed, dict) or PRODUCT_DOCUMENT not in reviewed:
            raise ValueError()
        for name, digest in reviewed.items():
            if name != PRODUCT_DOCUMENT and (not PurePosixPath(name).parts or safe_relative(name) != name
                                             or exclusion(name, public_inputs=())):
                raise ValueError()
            hashes[name] = digest
        if not all(isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value) for value in hashes.values()):
            raise ValueError()
    except (KeyError, TypeError, ValueError) as error:
        raise ReleaseError("CANDIDATE_PUBLIC_COPY_CONTRACT_INVALID", [PUBLIC_COPY_CONTRACT]) from error
    return {**selected, **hashes, PUBLIC_COPY_CONTRACT: sha(raw)}


def verify_source_check_inputs(selected, files):
    for name, expected in selected.items():
        if name not in files:
            raise ReleaseError("CANDIDATE_PREREQUISITE_MISSING", [name])
        if expected is not None and expected != files[name]["sha256"]:
            raise ReleaseError("CANDIDATE_PUBLIC_COPY_INPUT_CHANGED", [name])


def source_snapshot(root: Path, copy_into: Path | None = None, *, required=REQUIRED,
                    historical_roots=None, with_public_checks=True) -> tuple[dict, dict, list[str], dict]:
    files, excluded, absent, excluded_fixtures = {}, {}, [], {}
    names = git_names(root)
    selected = source_check_inputs(root, names) if with_public_checks and historical_roots is None else {}
    for name in names:
        reason = exclusion(name, historical_roots=historical_roots, public_inputs=selected)
        if reason:
            excluded[reason] = excluded.get(reason, 0) + 1
            if reason == "upstream_qa_fixture_source":
                if (root / name).exists() or (root / name).is_symlink():
                    data, mode = regular_bytes(root, name)
                    excluded_fixtures[name] = {"reason": reason, "sha256": sha(data), "bytes": len(data), "mode": mode}
                else:
                    excluded_fixtures[name] = {"reason": reason, "absent": True}
            continue
        if not (root / name).exists() and not (root / name).is_symlink():
            absent.append(name)
            continue
        data, mode = regular_bytes(root, name)
        screen_credentials(data, name)
        files[name] = {"sha256": sha(data), "bytes": len(data), "mode": mode}
        if copy_into is not None:
            target = copy_into / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            target.chmod(mode)
            copied, copied_mode = regular_bytes(copy_into, name)
            if {"sha256": sha(copied), "bytes": len(copied), "mode": copied_mode} != files[name]:
                raise ReleaseError("CANDIDATE_COPY_INVALID", [name])
    verify_source_check_inputs(selected, files)
    missing = sorted(required - files.keys())
    if missing:
        raise ReleaseError("CANDIDATE_PREREQUISITE_MISSING", missing)
    if historical_roots is None:
        verify_receiver_inputs(copy_into or root, files)
    migration_versions(files)
    return files, excluded, absent, excluded_fixtures


def migration_versions(names) -> dict:
    versions, invalid, duplicates = {}, [], []
    for name in sorted(names):
        path = PurePosixPath(name)
        if path.parts[:2] != ("supabase", "migrations") or path.suffix != ".sql":
            continue
        match = re.fullmatch(r"([0-9]{14})_[A-Za-z0-9][A-Za-z0-9_.-]*\.sql", path.name)
        if len(path.parts) != 3 or not match or int(match[1]) == 0:
            invalid.append(name)
            continue
        version = match[1]
        if version in versions:
            duplicates.extend([versions[version], name])
        else:
            versions[version] = name
    if invalid:
        raise ReleaseError("CANDIDATE_MIGRATION_VERSION_INVALID", invalid)
    if duplicates:
        raise ReleaseError("CANDIDATE_MIGRATION_VERSION_DUPLICATE", sorted(set(duplicates)))
    return versions


def collect_toolchain(root: Path, flutter_sdk: Path | None = None) -> dict:
    try:
        pin = json.loads((root / ".fvmrc").read_text())["flutter"]
        if not isinstance(pin, str) or not re.fullmatch(r"\d+\.\d+\.\d+", pin):
            raise ValueError()
        candidates = [flutter_sdk] if flutter_sdk else [root / ".fvm/flutter_sdk", Path("/Volumes/PRO-G40/Development/Flutter/flutter")]
        sdk = next(path.resolve() for path in candidates if path and (path / "bin/cache/flutter.version.json").is_file())
        metadata = json.loads((sdk / "bin/cache/flutter.version.json").read_text())
        flutter = sdk / "bin/flutter"
        if metadata["frameworkVersion"] != pin or not flutter.is_file():
            raise ReleaseError("CANDIDATE_FLUTTER_PIN_MISMATCH")
        node = shutil.which("node")
        if not node:
            raise ReleaseError("CANDIDATE_NODE_REQUIRED")
        version = subprocess.check_output([node, "--version"], stderr=subprocess.DEVNULL, timeout=5, text=True).strip()
        if not re.fullmatch(r"v\d+\.\d+\.\d+", version):
            raise ValueError()
        return {"flutter": {"pin": pin, "installed_version": metadata["frameworkVersion"],
                            "framework_revision": metadata["frameworkRevision"], "dart_version": metadata["dartSdkVersion"],
                            "sdk_path": str(sdk), "launcher_sha256": sha(flutter.read_bytes())},
                "node": {"version": version, "path": str(Path(node).resolve())},
                "python": {"version": sys.version.split()[0], "path": str(Path(sys.executable).resolve())},
                "lock_sha256": {name: sha((root / name).read_bytes()) for name in LOCKS},
                "toolchain_input_sha256": {name: sha((root / name).read_bytes()) for name in sorted(TOOLCHAIN_INPUTS)},
                "gradle_wrapper_properties_sha256": sha((root / "android/gradle/wrapper/gradle-wrapper.properties").read_bytes()),
                "scope": "Installed runtime metadata and exact source locks; no resolve/build/install/signature/advisory attestation"}
    except ReleaseError:
        raise
    except (OSError, KeyError, ValueError, StopIteration, subprocess.SubprocessError) as error:
        raise ReleaseError("CANDIDATE_TOOLCHAIN_REQUIRED") from error


def source_changes(expected: dict, observed: dict) -> list[dict]:
    changes = []
    for name in sorted(expected.keys() | observed.keys()):
        if name not in expected:
            changes.append({"path": name, "reason": "source_added"})
        elif name not in observed:
            changes.append({"path": name, "reason": "source_removed"})
        elif expected[name] != observed[name]:
            changes.append({"path": name, "reason": "source_changed"})
    return changes



PIN_INPUTS = frozenset(LOCKS) | TOOLCHAIN_INPUTS | {".fvmrc", "pubspec.yaml", "Gemfile", "android/app/build.gradle.kts",
    "android/build.gradle.kts", "android/settings.gradle.kts", "android/gradle/wrapper/gradle-wrapper.properties",
    "android/gradle/wrapper/gradle-wrapper.jar", "ios/Podfile",
    "deploy/platform-api/package.json"}


def pin_input_name(name):
    return name in PIN_INPUTS or name.endswith(".lock") or PurePosixPath(name).name in {
        "pnpm-lock.yaml", "package-lock.json", "gradle.lockfile", "Podfile.lock", "Package.resolved"}


def pin_source_snapshot(root):
    output = {}
    for name in git_names(root):
        if exclusion(name) or not pin_input_name(name) or not ((root / name).exists() or (root / name).is_symlink()):
            continue
        data, mode = regular_bytes(root, name)
        output[name] = {"sha256": sha(data), "bytes": len(data), "mode": mode}
    return output


def export_candidate(root: Path, destination: Path, flutter_sdk: Path | None = None,
                     retain_source_drift: bool = False) -> dict:
    root = root.resolve()
    # Resolve parents but refuse a preexisting destination or a checkout subtree.
    destination = destination.absolute()
    for ancestor in [destination, *destination.parents]:
        if ancestor.is_symlink():
            raise ReleaseError("CANDIDATE_DESTINATION_SYMLINK")
    destination = destination.resolve()
    if root == destination or root in destination.parents:
        raise ReleaseError("CANDIDATE_DESTINATION_NOT_ISOLATED")
    if destination.exists():
        raise ReleaseError("CANDIDATE_DESTINATION_EXISTS")
    capture_started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    if not retain_source_drift:
        files, excluded, absent, excluded_fixtures = source_snapshot(root)
        toolchain = collect_toolchain(root, flutter_sdk)
    else:
        # A non-atomic checkpoint captures each screened read once, immediately
        # hashing/copying those exact bytes. Never substitute later source bytes.
        toolchain = collect_toolchain(root, flutter_sdk)
        initial_pin_sources = pin_source_snapshot(root)
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".collect-export-", dir=destination.parent))
    try:
        if retain_source_drift:
            files, excluded, absent, excluded_fixtures = source_snapshot(root, copy_into=staging)
            captured_pins = {name: entry for name, entry in files.items() if pin_input_name(name)}
            pin_copy_changes = source_changes(initial_pin_sources, captured_pins)
            if pin_copy_changes:
                raise ReleaseError("CANDIDATE_PIN_INPUT_CHANGED", [item["path"] for item in pin_copy_changes])
            if any(files[name]["sha256"] != toolchain["lock_sha256"][name] for name in LOCKS):
                raise ReleaseError("CANDIDATE_PIN_INPUT_CHANGED", list(LOCKS))
        for name, entry in ([] if retain_source_drift else files.items()):
            data, mode = regular_bytes(root, name)
            if {"sha256": sha(data), "bytes": len(data), "mode": mode} != entry:
                raise ReleaseError("CANDIDATE_SOURCE_CHANGED", [name])
            target = staging / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            target.chmod(mode)
            if sha(target.read_bytes()) != entry["sha256"]:
                raise ReleaseError("CANDIDATE_COPY_INVALID", [name])
        copied_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        current, _, now_absent, now_excluded_fixtures = source_snapshot(root)
        source_observed_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        changes = source_changes(files, current)
        excluded_changes = source_changes(excluded_fixtures, now_excluded_fixtures)
        absence_changes = sorted(set(absent) ^ set(now_absent))
        drift = [{**item, "prior": files.get(item["path"]), "current": current.get(item["path"])} for item in changes]
        excluded_drift = [{**item, "prior": excluded_fixtures.get(item["path"]), "current": now_excluded_fixtures.get(item["path"])} for item in excluded_changes]
        if not retain_source_drift and (changes or excluded_changes or absence_changes):
            raise ReleaseError("CANDIDATE_SOURCE_CHANGED", [item["path"] for item in changes + excluded_changes] or absence_changes)
        if retain_source_drift:
            pin_drift = [item["path"] for item in changes if pin_input_name(item["path"])]
            if pin_drift:
                raise ReleaseError("CANDIDATE_PIN_INPUT_CHANGED", pin_drift)
            if collect_toolchain(root, flutter_sdk) != toolchain:
                raise ReleaseError("CANDIDATE_TOOLCHAIN_CHANGED")
        try:
            head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, stderr=subprocess.DEVNULL, text=True).strip()
        except subprocess.SubprocessError:
            head = None
        manifest = {"schema_version": SCHEMA_VERSION, "kind": "unapproved_collect_source_export", "source_root": str(root),
                    "created_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "base_head_observed": head, "approvals": dict(NO_APPROVAL), "policy": policy(),
                    "retain_source_drift": retain_source_drift, "source_current_tree_accepted": False,
                    "capture_classification": "unapproved_non_atomic_implementation_checkpoint" if retain_source_drift else "strict_unapproved_source_export",
                    "capture_interval": {"started_at_utc": capture_started, "copied_at_utc": copied_at, "source_observed_at_utc": source_observed_at},
                    "observed_source_drift": {"selected_files": drift, "excluded_upstream_fixtures": excluded_drift,
                        "indexed_absence_paths": absence_changes, "prior_indexed_absence": absent, "current_indexed_absence": now_absent,
                        "current_source_manifest_sha256": sha(canonical(current))},
                    "source_provenance": "Non-atomic implementation checkpoint; per-file bytes are exact, original-tree coherence/review/freeze/owner approval are not attested." if retain_source_drift else "Strict source comparison at export; no trust/review/freeze/owner attestation.",
                    "source_files": files, "file_count": len(files), "total_bytes": sum(item["bytes"] for item in files.values()),
                    "source_manifest_sha256": sha(canonical(files)), "toolchain": toolchain,
                    "migration_versions": migration_versions(files),
                    "all_selected_lock_inputs": {name: entry["sha256"] for name, entry in files.items()
                        if PurePosixPath(name).name in {"Package.resolved", "pnpm-lock.yaml", "package-lock.json", "gradle.lockfile", "Podfile.lock"}
                        or name.endswith(".lock")},
                    "excluded_file_counts": excluded, "absent_indexed_source_paths": absent,
                    "excluded_upstream_qa_source": excluded_fixtures,
                    "excluded_upstream_qa_sha256": sha(canonical(excluded_fixtures)),
                    "full_source_and_test_acceptance": "open; upstream fork regression fixtures remain in the checkout and require separate controlled coverage",
                    "private_or_ignored_inputs_copied": False,
                    "build_prerequisites_not_exported": list(PUBLIC_CONFIG_PREREQUISITES),
                    "build_notes": ["Restore pinned dependencies with frozen locks in the isolated export; generated SDK bindings are not source.",
                                    "Provision required native/provider public configuration separately through the governed build flow.",
                                    "A source export and installed toolchain do not constitute a build, review, frozen candidate or release approval."]}
        (staging / MANIFEST).write_bytes(canonical(manifest))
        staging.rename(destination)
        check = verify_candidate(destination, None if retain_source_drift else root)
        if check["status"] != "pass":
            raise ReleaseError("CANDIDATE_POST_EXPORT_INVALID", [item["path"] for item in check["changes"]])
        return {"status": "pass", "kind": manifest["kind"], "destination": str(destination),
                "manifest_sha256": sha((destination / MANIFEST).read_bytes()),
                "source_manifest_sha256": manifest["source_manifest_sha256"], "file_count": len(files),
                "total_bytes": manifest["total_bytes"], "approvals": dict(NO_APPROVAL), "source_readback": check,
                "capture_classification": manifest["capture_classification"], "capture_interval": manifest["capture_interval"],
                "source_current_tree_accepted": False, "observed_source_drift": manifest["observed_source_drift"]}
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def verify_candidate(candidate: Path, source: Path | None = None, expected_manifest_sha256: str | None = None) -> dict:
    if candidate.is_symlink():
        raise ReleaseError("CANDIDATE_SYMLINK_REFUSED")
    candidate = candidate.resolve()
    try:
        manifest_bytes, _ = regular_bytes(candidate, MANIFEST)
        if expected_manifest_sha256 is not None:
            if not re.fullmatch(r"[a-f0-9]{64}", expected_manifest_sha256):
                raise ReleaseError("CANDIDATE_MANIFEST_HASH_INVALID")
            if sha(manifest_bytes) != expected_manifest_sha256:
                raise ReleaseError("CANDIDATE_MANIFEST_HASH_CHANGED")
        manifest = json.loads(manifest_bytes)
        version = manifest["schema_version"]
        if type(version) is not int or version not in (1, 2, SCHEMA_VERSION) or manifest["kind"] != "unapproved_collect_source_export" or manifest["approvals"] != NO_APPROVAL:
            raise ValueError()
        manifest_policy = manifest["policy"]
        if not isinstance(manifest_policy, dict) or manifest_policy.get("public_browser_media") not in (None, BROWSER_MEDIA_POLICY):
            raise ValueError()
        files = manifest["source_files"]
        required, locks, historical_roots = REQUIRED, LOCKS, None
        if version == 1:
            required, locks = V1_REQUIRED, V1_LOCKS
            historical_roots = tuple(manifest_policy["source_roots"])
            old_roots = tuple(name for name in V1_ROOTS if name != "admin-web")
            if historical_roots not in (V1_ROOTS, old_roots):
                raise ValueError()
            if historical_roots == old_roots:
                locks = tuple(name for name in locks if not name.startswith("admin-web/"))
                required = {name for name in required if not name.startswith("admin-web/")} | {"lib/main_admin.dart"}
        if not isinstance(files, dict) or len(files) != manifest["file_count"] or not required <= files.keys() or sha(canonical(files)) != manifest["source_manifest_sha256"]:
            raise ValueError()
        if manifest["migration_versions"] != migration_versions(files):
            raise ValueError()
        if manifest["toolchain"]["lock_sha256"] != {name: files[name]["sha256"] for name in locks}:
            raise ValueError()
        if version >= 2 and manifest["toolchain"]["toolchain_input_sha256"] != {name: files[name]["sha256"] for name in TOOLCHAIN_INPUTS}:
            raise ValueError()
        if manifest.get("retain_source_drift") is True and (manifest.get("capture_classification") != "unapproved_non_atomic_implementation_checkpoint" or manifest.get("source_current_tree_accepted") is not False):
            raise ValueError()
        excluded_fixtures = manifest["excluded_upstream_qa_source"]
        if not isinstance(excluded_fixtures, dict) or sha(canonical(excluded_fixtures)) != manifest["excluded_upstream_qa_sha256"]:
            raise ValueError()
        for name, entry in excluded_fixtures.items():
            if exclusion(safe_relative(name)) != "upstream_qa_fixture_source" or entry.get("reason") != "upstream_qa_fixture_source":
                raise ValueError()
    except (OSError, KeyError, ValueError, TypeError) as error:
        if isinstance(error, ReleaseError):
            raise
        raise ReleaseError("CANDIDATE_MANIFEST_INVALID") from error
    changes = []
    observed = set()
    for parent, directories, names in os.walk(candidate, followlinks=False):
        for name in directories + names:
            path = Path(parent) / name
            if path.is_symlink():
                changes.append({"path": path.relative_to(candidate).as_posix(), "reason": "candidate_symlink"})
        for name in names:
            observed.add((Path(parent) / name).relative_to(candidate).as_posix())
    for name, entry in files.items():
        safe_relative(name)
        if exclusion(name, historical_roots=historical_roots, public_inputs=None if version == SCHEMA_VERSION else ()):
            raise ReleaseError("CANDIDATE_MANIFEST_INVALID")
        try:
            data, mode = regular_bytes(candidate, name)
            screen_credentials(data, name)
            if {"sha256": sha(data), "bytes": len(data), "mode": mode} != entry:
                changes.append({"path": name, "reason": "candidate_changed"})
        except ReleaseError as error:
            changes.append({"path": name, "reason": error.code})
    for name in sorted(observed - set(files) - {MANIFEST}):
        changes.append({"path": name, "reason": "candidate_unlisted_file"})
    if version >= 2 and not changes:
        verify_receiver_inputs(candidate, files)
        if version == SCHEMA_VERSION:
            selected = source_check_inputs(
                candidate, files, include_browser_media=manifest_policy.get("public_browser_media") == BROWSER_MEDIA_POLICY,
            )
            verify_source_check_inputs(selected, files)
            if any(exclusion(name, public_inputs=selected) for name in files):
                raise ReleaseError("CANDIDATE_MANIFEST_INVALID")
    if source is not None:
        if version == SCHEMA_VERSION:
            current, _, absent, now_excluded_fixtures = source_snapshot(source.resolve())
        else:
            current, _, absent, now_excluded_fixtures = source_snapshot(
                source.resolve(), required=required, historical_roots=historical_roots, with_public_checks=False)
        changes.extend(source_changes(files, current))
        changes.extend({"path": item["path"], "reason": "excluded_" + item["reason"]}
                       for item in source_changes(excluded_fixtures, now_excluded_fixtures))
        if absent != manifest["absent_indexed_source_paths"]:
            changes.extend({"path": name, "reason": "indexed_absence_changed"} for name in sorted(set(absent) ^ set(manifest["absent_indexed_source_paths"])))
    return {"status": "pass" if not changes else "blocked", "file_count": len(files), "changes": changes,
            "manifest_sha256": sha(manifest_bytes), "schema_version": version,
            "source_comparison_performed": source is not None, "covers_current_product_scope": version == SCHEMA_VERSION,
            "approvals": dict(NO_APPROVAL), "scope": "Exact bytes/modes/readback only; self-recorded hashes do not attest source trust"}


class SafeParser(argparse.ArgumentParser):
    def error(self, message):
        self.exit(2, '{"status":"blocked","reason_code":"RELEASE_ARGUMENTS_INVALID"}\n')


def main() -> int:
    parser = SafeParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    modes = parser.add_subparsers(dest="mode", required=True)
    export = modes.add_parser("export")
    export.add_argument("--destination", required=True, type=Path)
    export.add_argument("--flutter-sdk", type=Path)
    export.add_argument("--retain-source-drift", action="store_true", help="Explicit unapproved non-atomic checkpoint; locks/toolchain must remain stable")
    verify = modes.add_parser("verify")
    verify.add_argument("--candidate", required=True, type=Path)
    verify.add_argument("--compare-source", action="store_true")
    verify.add_argument("--expected-manifest-sha256")
    for mode in [export, verify]:
        mode.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        if args.mode == "export":
            report = export_candidate(args.root, args.destination, args.flutter_sdk, args.retain_source_drift)
        elif args.mode == "verify":
            report = verify_candidate(args.candidate, args.root if args.compare_source else None, args.expected_manifest_sha256)
    except ReleaseError as error:
        report = {"status": "blocked", "reason_code": error.code, "affected_source_paths": error.paths,
                  "production_mutations": 0, "credential_values_reported": False}
    except Exception:
        report = {"status": "blocked", "reason_code": "RELEASE_TOOLING_FAILED", "credential_values_reported": False}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_bytes(canonical(report))
    print(json.dumps(report, sort_keys=True))
    return 0 if report["status"] == "pass" else 2


if __name__ == "__main__":
    raise SystemExit(main())
