#!/usr/bin/env python3
"""Compare the Collect file_saver fork with the pinned pub.dev 0.4.0 archive."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tarfile
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FORK = ROOT / "third_party/file_saver"
CACHE = ROOT / ".cache/file-saver-upstream-0.4.0"
METADATA = CACHE / "metadata.json"
ARCHIVE = CACHE / "file_saver-0.4.0.tar.gz"
OUTPUT = ROOT / "docs/release/import-export-protection-2026-09-30/file-saver-fork-comparison.json"
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
ADDED = {"COLLECT_FORK.md"}
EXCLUDED = {".git", ".gradle", ".dart_tool", "build", "__pycache__"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch() -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(API, timeout=30) as response:
        metadata_bytes = response.read(1_000_001)
    require(len(metadata_bytes) <= 1_000_000, "Registry metadata too large")
    metadata = json.loads(metadata_bytes)
    require(metadata.get("version") == "0.4.0", "Unexpected registry package")
    archive_url = metadata.get("archive_url", "")
    parsed = urllib.parse.urlparse(archive_url)
    require(parsed.scheme == "https" and parsed.hostname == "pub.dev" and
            parsed.path == "/api/archives/file_saver-0.4.0.tar.gz" and
            metadata.get("archive_sha256") == ARCHIVE_SHA256,
            "Unexpected registry archive location or integrity hash")
    with urllib.request.urlopen(archive_url, timeout=30) as response:
        archive_bytes = response.read(25_000_001)
    require(len(archive_bytes) <= 25_000_000 and
            sha256(archive_bytes) == ARCHIVE_SHA256,
            "Published archive content hash mismatch")
    METADATA.write_text(json.dumps(metadata, sort_keys=True, indent=2) + "\n")
    ARCHIVE.write_bytes(archive_bytes)


def archive_files() -> dict[str, bytes]:
    require(METADATA.is_file() and ARCHIVE.is_file(),
            "Official archive absent; run with --fetch")
    metadata = json.loads(METADATA.read_text())
    require(metadata.get("version") == "0.4.0" and
            metadata.get("archive_sha256") == ARCHIVE_SHA256 and
            sha256(ARCHIVE.read_bytes()) == ARCHIVE_SHA256,
            "Cached registry archive changed")
    result = {}
    with tarfile.open(ARCHIVE, "r:gz") as package:
        for member in package.getmembers():
            path = Path(member.name)
            require(not path.is_absolute() and
                    all(part not in (".", "..") for part in path.parts),
                    "Unsafe archive path")
            if member.isdir():
                continue
            require(member.isfile() and member.name not in result,
                    "Archive contains link, duplicate or unsupported entry")
            stream = package.extractfile(member)
            require(stream is not None, "Archive member unreadable")
            result[member.name] = stream.read()
    return result


def tree_files(base: Path) -> dict[str, bytes]:
    return {
        path.relative_to(base).as_posix(): path.read_bytes()
        for path in sorted(base.rglob("*"))
        if path.is_file() and not any(part in EXCLUDED
                                      for part in path.relative_to(base).parts)
    }


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
    cached = Path.home() / ".pub-cache/hosted/pub.dev/file_saver-0.4.0"
    cache_matches = None
    if cached.is_dir():
        cache_matches = tree_files(cached) == upstream
    upstream_names, fork_names = set(upstream), set(fork)
    added = sorted(fork_names - upstream_names)
    removed = sorted(upstream_names - fork_names)
    changed = sorted(name for name in upstream_names & fork_names
                     if upstream[name] != fork[name])
    require(set(added) == ADDED and set(changed) == CHANGED,
            "Fork file delta differs from the reviewed set")
    allowed_removed = lambda name: (name == "README.md" or
                                    name == "file_saver.iml" or
                                    name.startswith(("example/", "images/", "test/")))
    require(all(allowed_removed(name) for name in removed),
            "Fork omits a runtime, platform, licence or package file")
    require(upstream["LICENSE"] == fork["LICENSE"],
            "Upstream licence text changed")
    mime_equivalent = formatted_source_equal(
        upstream["lib/src/utils/mime_types.dart"],
        FORK / "lib/src/utils/mime_types.dart")
    require(mime_equivalent, "MIME source differs beyond Dart formatting")
    changed_hashes = {
        name: {"upstream_sha256": sha256(upstream[name]),
               "fork_sha256": sha256(fork[name])}
        for name in changed
    }
    metadata = json.loads(METADATA.read_text())
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
        "local_pub_cache_matches_registry_archive": cache_matches,
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
    args = parser.parse_args()
    if args.fetch:
        fetch()
    document = json.dumps(build(), indent=2, sort_keys=True) + "\n"
    if args.check:
        require(OUTPUT.is_file() and OUTPUT.read_text() == document,
                "Fork comparison report is stale")
        print("Fork comparison report matches the official archive and local source")
        return
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(document)
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
