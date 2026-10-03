#!/usr/bin/env python3
"""Compare the Collect file_saver fork with the pinned pub.dev 0.4.0 archive."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_pub_forks as origin


ROOT = Path(__file__).resolve().parents[2]
FORK = ROOT / "third_party/file_saver"
CACHE = ROOT / ".cache/file-saver-upstream-0.4.0"
METADATA = CACHE / "metadata.json"
ARCHIVE = CACHE / "file_saver-0.4.0.tar.gz"
OUTPUT = ROOT / "docs/release/critical-implementation-2026-10-01/kotlin-dependency-batch1/file-saver-fork-comparison.json"
API = "https://pub.dev/api/packages/file_saver/versions/0.4.0"
ARCHIVE_SHA256 = "68c9a085d9bb4546e0a31d1e583a48d7c17a6987d538788ea064f0043b1fc02d"
CHANGED = {
    "android/build.gradle", "android/gradle/wrapper/gradle-wrapper.properties",
    "lib/src/utils/mime_types.dart", "pubspec.yaml",
    "android/src/main/kotlin/com/incrediblezayed/file_saver/Dialog.kt",
    "android/src/main/kotlin/com/incrediblezayed/file_saver/FileSaverPlugin.kt",
    "android/src/main/kotlin/com/incrediblezayed/file_saver/FileUtils.kt",
    "ios/file_saver/Sources/file_saver/Dialog.swift",
}
ADDED = {"COLLECT_FORK.md", "COLLECT_FORK_DELTA.json"}
REVIEWED_DELTA_SHA256 = "ee7fc65799bb40e7083633dda3c3eea0a2b46c2d19e18c8ee2c1cd26b936f9b9"
EXCLUDED = {".git", ".gradle", ".dart_tool", "build", "__pycache__"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch() -> None:
    origin.no_symlinks(CACHE)
    CACHE.mkdir(parents=True, exist_ok=True)
    metadata_bytes = origin.public_download(API, origin.MAX_METADATA)
    metadata = origin.strict_json(metadata_bytes)
    origin.validate_metadata(metadata, {"package": "file_saver", "version": "0.4.0",
                                        "archive_sha256": ARCHIVE_SHA256})
    archive_bytes = origin.public_download(metadata["archive_url"], origin.MAX_ARCHIVE)
    require(sha256(archive_bytes) == ARCHIVE_SHA256,
            "Published archive content hash mismatch")
    origin.archive_files(archive_bytes)
    origin.write_output(METADATA, json.dumps(metadata, sort_keys=True, indent=2) + "\n",
                        [FORK, Path(__file__).resolve()])
    origin.no_symlinks(ARCHIVE)
    with tempfile.NamedTemporaryFile(dir=CACHE, delete=False) as temporary:
        temporary.write(archive_bytes)
        temporary_path = Path(temporary.name)
    try:
        os.replace(temporary_path, ARCHIVE)
    finally:
        temporary_path.unlink(missing_ok=True)


def archive_files() -> dict[str, bytes]:
    require(METADATA.is_file() and ARCHIVE.is_file(),
            "Official archive absent; run with --fetch")
    metadata = origin.strict_json(origin.regular_bytes(METADATA, origin.MAX_METADATA))
    archive = origin.regular_bytes(ARCHIVE, origin.MAX_ARCHIVE)
    require(metadata.get("version") == "0.4.0" and
            metadata.get("archive_sha256") == ARCHIVE_SHA256 and
            sha256(archive) == ARCHIVE_SHA256,
            "Cached registry archive changed")
    origin.validate_metadata(metadata, {"package": "file_saver", "version": "0.4.0",
                                        "archive_sha256": ARCHIVE_SHA256})
    return origin.archive_files(archive)


def tree_files(base: Path) -> dict[str, bytes]:
    origin.no_symlinks(base)
    def traversal_error(error):
        raise error
    result = {}
    for current, dirs, files in os.walk(base, followlinks=False, onerror=traversal_error):
        require(not any((Path(current) / name).is_symlink() for name in dirs + files), "Symlink fork input")
        dirs[:] = [name for name in dirs if name not in EXCLUDED]
        for name in sorted(files):
            if name in EXCLUDED:
                continue
            path = Path(current) / name
            result[origin.safe_name(path.relative_to(base).as_posix())] = origin.regular_bytes(path, origin.MAX_FILE)
    return result


def formatted_source_equal(upstream: bytes, fork: Path) -> bool:
    with tempfile.TemporaryDirectory(dir=CACHE) as temporary:
        upstream_file = Path(temporary) / "mime_types.dart"
        upstream_file.write_bytes(upstream)
        def formatted(path: Path) -> str:
            result = subprocess.run(
                ["dart", "format", "--output=json", str(path)],
                capture_output=True, text=True, timeout=20, check=True)
            return json.loads(result.stdout.splitlines()[0])["source"]
        return formatted(upstream_file) == formatted(fork)


def build() -> dict:
    upstream = archive_files()
    fork = tree_files(FORK)
    upstream_names, fork_names = set(upstream), set(fork)
    added = sorted(fork_names - upstream_names)
    removed = sorted(upstream_names - fork_names)
    changed = sorted(name for name in upstream_names & fork_names
                     if upstream[name] != fork[name])
    require("LICENSE" in fork and upstream["LICENSE"] == fork["LICENSE"],
            "Upstream licence text changed or missing")
    require(set(added) == ADDED and set(changed) == CHANGED,
            "Fork file delta differs from the reviewed set")
    allowed_removed = lambda name: (name == "README.md" or
                                    name == "file_saver.iml" or
                                    name.startswith(("example/", "images/", "test/")))
    require(all(allowed_removed(name) for name in removed),
            "Fork omits a runtime, platform, licence or package file")
    delta_raw = fork["COLLECT_FORK_DELTA.json"]
    require(sha256(delta_raw) == REVIEWED_DELTA_SHA256, "Reviewed exact-byte delta manifest drift")
    delta = origin.strict_json(delta_raw)
    require(delta.get("schema_version") == 1 and delta.get("upstream_version") == "0.4.0" and
            delta.get("upstream_archive_sha256") == ARCHIVE_SHA256 and
            delta.get("license_sha256") == sha256(upstream["LICENSE"]), "Reviewed delta identity mismatch")
    require(set(delta["changed"]) == set(changed) and
            set(delta["added"]) == set(added) - {"COLLECT_FORK_DELTA.json"} and
            set(delta["omitted"]) == set(removed), "Unreviewed exact-byte delta set")
    for kind, names in (("changed", changed), ("added", ["COLLECT_FORK.md"]), ("omitted", removed)):
        for name in names:
            row = delta[kind][name]
            require(isinstance(row.get("rationale"), str) and bool(row["rationale"].strip()), "Missing delta rationale")
            if kind != "added":
                require(row.get("upstream_sha256") == sha256(upstream[name]), "Reviewed upstream byte drift: " + name)
            if kind != "omitted":
                require(row.get("fork_sha256") == sha256(fork[name]), "Reviewed fork byte drift: " + name)
    mime_equivalent = formatted_source_equal(
        upstream["lib/src/utils/mime_types.dart"],
        FORK / "lib/src/utils/mime_types.dart")
    require(mime_equivalent, "MIME source differs beyond Dart formatting")
    changed_hashes = {
        name: {"upstream_sha256": sha256(upstream[name]),
               "fork_sha256": sha256(fork[name])}
        for name in changed
    }
    metadata = origin.strict_json(origin.regular_bytes(METADATA, origin.MAX_METADATA))
    origin.validate_metadata(metadata, {"package": "file_saver", "version": "0.4.0",
                                        "archive_sha256": ARCHIVE_SHA256})
    require(tree_files(FORK) == fork and archive_files() == upstream,
            "Fork or official cache input drift during comparison")
    return {
        "status": "pass_source_fork_comparison_not_signed_artifact_assurance",
        "upstream_registry_api": API,
        "upstream_version": "0.4.0",
        "upstream_published": metadata.get("published"),
        "upstream_archive_sha256": ARCHIVE_SHA256,
        "upstream_files": len(upstream),
        "fork_files": len(fork),
        "identical_common_files": sum(upstream[name] == fork[name]
                                      for name in upstream_names & fork_names),
        "added_files": added,
        "removed_files": removed,
        "removed_files_are_examples_tests_docs_or_images": True,
        "changed_files": changed_hashes,
        "mime_source_format_equivalent": mime_equivalent,
        "upstream_license_unchanged": True,
        "reviewed_exact_byte_delta_sha256": REVIEWED_DELTA_SHA256,
        "limitations": [
            "Gradle migration and package semantics require native build review",
            "No signed AAB or IPA component/notice inspection",
            "No current package advisory or distribution-rights approval",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true",
                        help="Fetch the exact versioned package from pub.dev")
    parser.add_argument("--check", action="store_true",
                        help="Compare with the saved report without writing")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    if args.fetch:
        fetch()
    document = json.dumps(build(), indent=2, sort_keys=True) + "\n"
    if args.check:
        require(args.output.is_file() and args.output.read_text() == document,
                "Fork comparison report is stale")
        print("Fork comparison report matches the official archive and local source")
        return
    origin.write_output(args.output, document, [FORK, CACHE, Path(__file__).resolve()])
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
