#!/usr/bin/env python3
"""Export and verify unapproved Collect source; discover local MCP without reads.

Only export writes source copies. No command commits, deploys, signs in, requests
an OTP, invokes an MCP tool, or attests that a candidate is reviewed/frozen.
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
    "third_party", "supabase", "deploy", "tools", "scripts", "test",
    "integration_test", "test_driver", "tool", "contracts", "fastlane",
)
ROOT_FILES = {
    "AGENTS.md", "README.md", "Makefile", "pubspec.yaml", "pubspec.lock",
    "analysis_options.yaml", ".metadata", ".fvmrc", ".dvmrc", ".gitignore",
    ".gitleaks.toml", ".env.example", "Gemfile", "Gemfile.lock", ".supabase-cli-version",
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
    "supabase/functions/deno.lock", "tools/collect-notification-mcp/pnpm-lock.yaml",
)
REQUIRED = frozenset(LOCKS) | {
    ".fvmrc", ".dvmrc", "pubspec.yaml", "lib/main.dart", "lib/main_admin.dart",
    "android/app/build.gradle.kts", "android/gradle/wrapper/gradle-wrapper.properties",
    "android/gradle/wrapper/gradle-wrapper.jar", "ios/Podfile",
    "ios/Runner.xcodeproj/project.pbxproj", "tools/collect-notification-mcp/package.json",
    "tools/collect-notification-mcp/src/server.ts",
}
# Preserve already-established minute-granularity history. New migrations must
# use full timestamps; rewriting historical versions would break provenance.
LEGACY_MIGRATION_VERSIONS = frozenset({f"20260523{number:04d}" for number in range(1, 18)}
                                    | {"202605250001", "202605270001"})
READ_TOOLS = frozenset({
    "collect_notification_health", "collect_list_pending_receipts", "get_collect_health",
    "get_notification_status", "list_notification_failures",
})
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
            "migration_versions": {"new": "unique valid YYYYMMDDHHMMSS",
                                   "preserved_legacy_minute_versions": sorted(LEGACY_MIGRATION_VERSIONS)},
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
    rb"\bsb_secret_[A-Za-z0-9_-]{20,}\b",
)
JWT_PATTERN = re.compile(rb"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{16,}\b")


def screen_credentials(data: bytes, name: str) -> None:
    for pattern in TOKEN_PATTERNS:
        for match in re.finditer(pattern, data):
            # Exact synthetic source fixture prefix, never a general 'test' bypass.
            if match.group().startswith(b"sb_secret_synthetic_"):
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
        # A public Supabase anon project identifier is not a current-user or
        # privileged secret; credential-bearing JWT roles are excluded.
        if not isinstance(claims, dict) or claims.get("role") != "anon":
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
        if len(path.parts) != 3 or path.parts[:2] != ("supabase", "migrations") or path.suffix != ".sql":
            continue
        match = re.fullmatch(r"([0-9]{12}|[0-9]{14})_[A-Za-z0-9][A-Za-z0-9_.-]*\.sql", path.name)
        if not match:
            invalid.append(name)
            continue
        version = match[1]
        if len(version) == 12 and version not in LEGACY_MIGRATION_VERSIONS:
            invalid.append(name)
            continue
        try:
            datetime(int(version[:4]), int(version[4:6]), int(version[6:8]),
                     int(version[8:10]), int(version[10:12]), int(version[12:14]) if len(version) == 14 else 0)
        except ValueError:
            invalid.append(name)
            continue
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
        package = json.loads((root / "tools/collect-notification-mcp/package.json").read_text())
        return {"flutter": {"pin": pin, "installed_version": metadata["frameworkVersion"],
                            "framework_revision": metadata["frameworkRevision"], "dart_version": metadata["dartSdkVersion"],
                            "sdk_path": str(sdk), "launcher_sha256": sha(flutter.read_bytes())},
                "node": {"version": version, "path": str(Path(node).resolve())},
                "python": {"version": sys.version.split()[0], "path": str(Path(sys.executable).resolve())},
                "deno": {"declared_pin": (root / ".dvmrc").read_text().strip(), "installed_path": shutil.which("deno")},
                "mcp_declared_packages": {**package.get("dependencies", {}), **package.get("devDependencies", {})},
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



PIN_INPUTS = frozenset(LOCKS) | {".fvmrc", ".dvmrc", "pubspec.yaml", "Gemfile", "android/app/build.gradle.kts",
    "android/build.gradle.kts", "android/settings.gradle.kts", "android/gradle/wrapper/gradle-wrapper.properties",
    "android/gradle/wrapper/gradle-wrapper.jar", "ios/Podfile", "tools/collect-notification-mcp/package.json",
    "supabase/functions/deno.json", "supabase/functions/deno.jsonc"}


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


def safe_host_profile(config: Path, root: Path) -> dict:
    try:
        import tomllib
        profile = tomllib.loads(config.read_text())["mcp_servers"]["collect-notifications"]
        enabled = profile["enabled_tools"]
        if not isinstance(enabled, list) or len(enabled) != 5 or any(not isinstance(name, str) for name in enabled) or set(enabled) != READ_TOOLS or profile.get("enabled") is False:
            raise ReleaseError("MCP_FIVE_READ_ALLOWLIST_REQUIRED")
        bridge = (root / "tools/collect-notification-mcp").resolve()
        command = Path(profile["command"])
        args = profile["args"]
        if not command.is_absolute() or not command.is_file() or command.resolve().name != "node" or Path(profile["cwd"]).resolve() != bridge or not isinstance(args, list) or len(args) != 2 or args[0] != "--experimental-strip-types" or Path(args[1]).resolve() != bridge / "src/server.ts":
            raise ReleaseError("MCP_FIXED_BRIDGE_REQUIRED")
        package = json.loads((bridge / "package.json").read_text())
        installed = {}
        for name in ["@modelcontextprotocol/server", "zod"]:
            version = json.loads((bridge / "node_modules" / name / "package.json").read_text())["version"]
            if package["dependencies"][name] != version:
                raise ReleaseError("MCP_INSTALLED_DEPENDENCY_MISMATCH")
            installed[name] = version
        return {"command": str(command), "args": args, "cwd": str(bridge), "enabled_tools": enabled,
                "installed_packages": installed, "server_source_sha256": sha((bridge / "src/server.ts").read_bytes()),
                "startup_timeout_sec": profile.get("startup_timeout_sec"), "tool_timeout_sec": profile.get("tool_timeout_sec")}
    except ReleaseError:
        raise
    except (OSError, KeyError, TypeError, ValueError) as error:
        raise ReleaseError("MCP_LOCAL_PREREQUISITE_MISSING") from error


def discover_mcp(profile: dict, timeout_seconds: float = 15) -> dict:
    if not 0 < timeout_seconds <= 15:
        raise ReleaseError("MCP_DEADLINE_INVALID")
    deadline = time.monotonic() + timeout_seconds
    child = subprocess.Popen([profile["command"], *profile["args"]], cwd=profile["cwd"],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             env={"PATH": os.environ.get("PATH", ""), "NO_COLOR": "1"})
    selector = selectors.DefaultSelector()
    selector.register(child.stdout, selectors.EVENT_READ)
    buffer = b""
    counter = 0
    def request(method: str, params: dict) -> dict:
        nonlocal buffer, counter
        counter += 1
        child.stdin.write(canonical({"jsonrpc": "2.0", "id": counter, "method": method, "params": params}))
        child.stdin.flush()
        while True:
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                try:
                    value = json.loads(line)
                    if not isinstance(value, dict) or value.get("jsonrpc") != "2.0":
                        raise ValueError()
                    if "id" not in value and isinstance(value.get("method"), str):
                        continue
                    if value.get("id") != counter or "error" in value or not isinstance(value.get("result"), dict):
                        raise ValueError()
                    return value["result"]
                except (ValueError, TypeError) as error:
                    raise ReleaseError("MCP_PROTOCOL_INVALID") from error
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise ReleaseError("MCP_DISCOVERY_DEADLINE")
            data = os.read(child.stdout.fileno(), 64 * 1024)
            if not data:
                raise ReleaseError("MCP_LOCAL_PROCESS_CLOSED")
            buffer += data
            if len(buffer) > 256 * 1024:
                raise ReleaseError("MCP_RESPONSE_TOO_LARGE")
    try:
        initialized = request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
            "clientInfo": {"name": "collect-offline-release-preflight", "version": "1"}})
        if initialized.get("protocolVersion") != "2025-11-25" or initialized.get("serverInfo", {}).get("name") != "collect-notification-operator" or not isinstance(initialized.get("capabilities", {}).get("tools"), dict):
            raise ReleaseError("MCP_INITIALIZE_INVALID")
        child.stdin.write(canonical({"jsonrpc": "2.0", "method": "notifications/initialized"}))
        child.stdin.flush()
        discovered = request("tools/list", {}).get("tools")
        if not isinstance(discovered, list) or len(discovered) > 100:
            raise ReleaseError("MCP_CATALOG_INVALID")
        names, reads = [], {}
        for item in discovered:
            if not isinstance(item, dict) or not isinstance(item.get("name"), str) or item["name"] in names:
                raise ReleaseError("MCP_CATALOG_INVALID")
            names.append(item["name"])
            if item["name"] in READ_TOOLS:
                schema = item.get("inputSchema")
                if not isinstance(schema, dict) or schema.get("type") != "object" or item.get("annotations", {}).get("readOnlyHint") is not True:
                    raise ReleaseError("MCP_READ_SCHEMA_INVALID")
                reads[item["name"]] = {"input_schema": schema, "read_only_hint": True}
        if set(reads) != READ_TOOLS:
            raise ReleaseError("MCP_READ_TOOL_MISSING")
        return {"status": "pass", "protocol_version": initialized["protocolVersion"],
                "server_name": initialized["serverInfo"]["name"], "registered_tool_count": len(names),
                "host_enabled_tools": sorted(profile["enabled_tools"]), "enabled_read_schemas": reads,
                "read_schema_sha256": sha(canonical(reads)), "installed_packages": profile["installed_packages"],
                "server_source_sha256": profile["server_source_sha256"],
                "node_version": subprocess.check_output([profile["command"], "--version"], stderr=subprocess.DEVNULL, timeout=5, text=True).strip(),
                "host_startup_timeout_sec": profile.get("startup_timeout_sec"), "host_tool_timeout_sec": profile.get("tool_timeout_sec"),
                "mcp_tool_calls": 0, "credential_environment_forwarded": False, "config_environment_reported": False,
                "backend_reads": 0, "otp_requests": 0, "production_connection_verified": False,
                "scope": "Offline installation/profile/runtime initialize and tools/list; host reload and live authentication remain unverified"}
    except (OSError, BrokenPipeError, subprocess.SubprocessError) as error:
        raise ReleaseError("MCP_LOCAL_PROCESS_FAILURE") from error
    finally:
        selector.close()
        child.stdin.close()
        try:
            child.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            child.terminate()
            try:
                child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=1)
        child.stdout.close()


def offline_mcp(root: Path, config: Path, candidate_path: Path | None = None,
                expected_manifest_sha256: str | None = None) -> dict:
    root = root.resolve()
    readback = None
    if candidate_path is not None:
        readback = verify_candidate(candidate_path, root, expected_manifest_sha256)
        if readback["status"] != "pass":
            raise ReleaseError("MCP_CANDIDATE_SOURCE_STALE", [item["path"] for item in readback["changes"]])
    elif expected_manifest_sha256 is not None:
        raise ReleaseError("CANDIDATE_PREREQUISITE_MISSING")
    report = discover_mcp(safe_host_profile(config, root))
    if candidate_path is not None:
        manifest = json.loads((candidate_path / MANIFEST).read_text())
        packages = manifest["toolchain"]["mcp_declared_packages"]
        if report["server_source_sha256"] != manifest["source_files"]["tools/collect-notification-mcp/src/server.ts"]["sha256"] or any(packages.get(key) != version for key, version in report["installed_packages"].items()):
            raise ReleaseError("MCP_CANDIDATE_METADATA_CHANGED")
        report["candidate_manifest_sha256"] = readback["manifest_sha256"]
    report["candidate_source_bound"] = candidate_path is not None
    return report


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
    mcp = modes.add_parser("mcp-offline")
    mcp.add_argument("--config", type=Path, default=Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))) / "config.toml")
    mcp.add_argument("--candidate", type=Path)
    mcp.add_argument("--expected-manifest-sha256")
    for mode in [export, verify, mcp]:
        mode.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        if args.mode == "export":
            report = export_candidate(args.root, args.destination, args.flutter_sdk, args.retain_source_drift)
        elif args.mode == "verify":
            report = verify_candidate(args.candidate, args.root if args.compare_source else None, args.expected_manifest_sha256)
        else:
            report = offline_mcp(args.root, args.config, args.candidate, args.expected_manifest_sha256)
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
