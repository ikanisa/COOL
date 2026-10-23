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
SOURCE_ROOTS = (
    ".github", "lib", "assets", "licenses", "android", "ios", "web", "content",
    "third_party", "deploy", "tools", "scripts", "test",
    "integration_test", "test_driver", "tool", "contracts", "fastlane", "supabase",
)
ROOT_FILES = {
    "AGENTS.md", "README.md", "Makefile", "pubspec.yaml", "pubspec.lock",
    "analysis_options.yaml", ".metadata", ".fvmrc", ".gitignore",
    ".gitleaks.toml", ".env.example", "Gemfile", "Gemfile.lock",
}
PRIVATE_NAMES = {
    "key.properties", "local.properties", "google-services.json", "GoogleService-Info.plist",
    "Generated.xcconfig", "MapsKeys.xcconfig", "flutter_export_environment.sh",
    ".flutter-plugins-dependencies", "credentials.json", "service-account.json",
}
BLOCKED_PARTS = {
    "node_modules", "Pods", ".symlinks", ".gradle", ".kotlin", ".dart_tool",
    ".pub-cache", ".pub", ".swiftpm", ".build", ".git", ".cache", ".wrangler",
    "build", "coverage", "output", "failures", "__pycache__", "DerivedData", ".temp",
}
BLOCKED_SUFFIXES = {
    ".jks", ".keystore", ".p12", ".pfx", ".p8", ".pem", ".key", ".mobileprovision",
    ".apk", ".aab", ".ipa", ".dSYM", ".class", ".pyc", ".log", ".dump", ".sql.gz",
    ".csv", ".tsv", ".xlsx", ".xls", ".pdf", ".zip", ".tar", ".gz", ".bak", ".old",
}
LOCKS = (
    "pubspec.lock", "Gemfile.lock", "android/app/gradle.lockfile", "ios/Podfile.lock",
    "deploy/platform-api/package-lock.json",
)
REQUIRED = frozenset(LOCKS) | {
    ".fvmrc", "pubspec.yaml", "lib/main.dart", "lib/main_admin.dart",
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


def exclusion(name: str) -> str | None:
    path = PurePosixPath(name)
    if path.name in PRIVATE_NAMES or (path.name.startswith(".env") and path.name != ".env.example"):
        return "private_configuration"
    if any(part in BLOCKED_PARTS or part.startswith("build_stale_") for part in path.parts):
        return "cache_or_build_output"
    if len(path.parts) >= 3 and path.parts[0] == "third_party" and path.parts[2] == "test":
        return "upstream_qa_fixture_source"
    if path.suffix.lower() in BLOCKED_SUFFIXES or path.name.startswith("GoogleService-Info-") or any(part.endswith(".dSYM") for part in path.parts):
        return "private_artifact_or_payload_format"
    if path.parts[0] not in SOURCE_ROOTS and name not in ROOT_FILES:
        return "outside_declared_source_scope"
    return None


def policy() -> dict:
    return {"git_selection": "tracked plus nonignored untracked; missing indexed files recorded as absent",
            "source_roots": list(SOURCE_ROOTS), "top_level_source_files": sorted(ROOT_FILES),
            "excluded_path_components": sorted(BLOCKED_PARTS), "excluded_names": sorted(PRIVATE_NAMES),
            "excluded_suffixes": sorted(BLOCKED_SUFFIXES),
            "additional_exclusions": ["all docs/release and other non-source roots", "private .env files",
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
GENERIC_PUBLIC_SOURCE_LINES = {
    'scripts/supabase/current-archive/bundle.mjs': frozenset(('319c34a67f96775c5fcfd8bdd0b0d0798a34ae0d447b11b9eda3cf163612e06c', 'a927d44911a34e7c6150d7de97018f6cfccdd3c8a46bce0c8c318e25e7c99af4')),
    'scripts/supabase/current-archive/operator.mjs': frozenset(('729d146227251983ef7c5e6e3ca6fd6cee64029af78e243e903479f1c4e0a59b',)),
    'analysis_options.yaml': frozenset(('856267bb9cf05544b1bcb7d4d635d83ac98958944f91beed38364eb4c57f65d8',)),
    'scripts/cloudflare/platform_backup.mjs': frozenset(('a1f14510f3749b00a91675a3b70f4a3b7c40571294012ce38f2af72b33222b5d', '9a1e5335ffeeb9b237d40ba61e5428353709302f17e837c056da3fcb29b4ed64',)),
    'scripts/cloudflare/recovery_quarantine.mjs': frozenset(('cf3a20cafbefa427e3d42d11827593fb70907c381a1abb320486a48e15fae28b', '6c91bd6f58aa2dddfd5fe93b42c2124db9851adb360411e1df34c089c4ab6f7e',)),
    'scripts/google_play_production_upload.sh': frozenset(('11b90dfa9d26f3a2dbdaecb851bc9b35b5a5f14eedcbf587b914f0ba2e9b4821', 'f334a4c917a986e56bbf2466102fde704bcd049fbc6b8eebdeab1e1b1d81effb', '45c2f74fbd50c5be11a5410cd1c7c36904fe6b5af7587f2676db58f54a999ab0')),
    'scripts/tests/asset_hygiene_integration_test.rb': frozenset(('27b2228008849b62e74ff9308730c9031f0552dedbe0377af4bca0cff3c15ce8',)),
    'scripts/tests/recovery_quarantine_test.mjs': frozenset(('6b8f601643230bc408b6a1235d24509d11a83318a53438548cc5e101e9f54dce', 'f0b8bfd32fc3cd0e86cef7cce32b4ef3f8da8018fb16d7603bca7fa43993bc65')),
    'scripts/tests/test_collect_release_candidate.py': frozenset(('b22103bcb6205d0e5afbda5722db14d82dc1e18c2a437d20e74f89abb3fe7309',)),
    'tools/roster-decoder/test_dependency_security.py': frozenset(('a8be53a19391ee14c5b8b8c087e7b50e47add3048e8c3ad851bcd309c5b81356', 'fb0decb938601040642d4d7a764ef65fcc56e4dcac7ea3561f893edd09a0651f')),
    'scripts/supabase/jobs_config.mjs': frozenset(('af03da7f6de3aafb23e7fe876bb5d4eaaa40b1363c488828c118f990de94653b',)),
    'scripts/supabase/jobs_test.mjs': frozenset(('f8d9eae32a8476ceae2e6aab8e60d75594120f1790dd1544f293c7570859d31e',)),
    'supabase/jobs/bootstrap.sql': frozenset(('34767fdf18de63e4c1fe888efa504fae83ee5d17668569ef4000258bb59ff435', 'c345c388eceb858060dd02595ba77cbb49e36e6a0eb83ddb229b55c7ad689314')),
    'supabase/jobs/readiness.example.json': frozenset(('9dc52c463d96162b2ce8dfe256cf0df5b13e4c78e239356074d41b9f8433e6d3',)),
}
GENERIC_CONTROLLED_TEST_LINES = {
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


def source_snapshot(root: Path, copy_into: Path | None = None) -> tuple[dict, dict, list[str], dict]:
    files, excluded, absent, excluded_fixtures = {}, {}, [], {}
    for name in git_names(root):
        reason = exclusion(name)
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
    missing = sorted(REQUIRED - files.keys())
    if missing:
        raise ReleaseError("CANDIDATE_PREREQUISITE_MISSING", missing)
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



PIN_INPUTS = frozenset(LOCKS) | {".fvmrc", "pubspec.yaml", "Gemfile", "android/app/build.gradle.kts",
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
        manifest = {"schema_version": 1, "kind": "unapproved_collect_source_export", "source_root": str(root),
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
        if manifest["schema_version"] != 1 or manifest["kind"] != "unapproved_collect_source_export" or manifest["approvals"] != NO_APPROVAL:
            raise ValueError()
        files = manifest["source_files"]
        if not isinstance(files, dict) or len(files) != manifest["file_count"] or not REQUIRED <= files.keys() or sha(canonical(files)) != manifest["source_manifest_sha256"]:
            raise ValueError()
        if manifest["migration_versions"] != migration_versions(files):
            raise ValueError()
        if manifest["toolchain"]["lock_sha256"] != {name: files[name]["sha256"] for name in LOCKS}:
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
        if exclusion(name):
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
    if source is not None:
        current, _, absent, now_excluded_fixtures = source_snapshot(source.resolve())
        changes.extend(source_changes(files, current))
        changes.extend({"path": item["path"], "reason": "excluded_" + item["reason"]}
                       for item in source_changes(excluded_fixtures, now_excluded_fixtures))
        if absent != manifest["absent_indexed_source_paths"]:
            changes.extend({"path": name, "reason": "indexed_absence_changed"} for name in sorted(set(absent) ^ set(manifest["absent_indexed_source_paths"])))
    return {"status": "pass" if not changes else "blocked", "file_count": len(files), "changes": changes,
            "manifest_sha256": sha(manifest_bytes), "source_comparison_performed": source is not None,
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
