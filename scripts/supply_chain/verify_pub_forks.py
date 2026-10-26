#!/usr/bin/env python3
"""Authenticate exact pub.dev releases and verify reviewed Collect fork bytes.

Fetch is a separate public-download operation. Verification never uses the network,
installs packages, edits a fork, or infers behavior, rights or release approval.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = {"firebase_messaging": "16.5.0"}
# Trust roots are reviewed together with the exact-byte delta manifests. There is
# intentionally no command that learns/accepts a new delta from the current tree.
REVIEWED_MANIFEST_SHA256 = {
    "firebase_messaging": "c9eb98078e89ab37a3341f930c38e0b7f81da4ce21082fd50f2ffd93ed414c09",
}
MAX_METADATA = 1_000_000
MAX_ARCHIVE = 25_000_000
MAX_FILE = 10_000_000
MAX_TREE = 100_000_000
MAX_ENTRIES = 5_000


def require(value: bool, message: str) -> None:
    if not value:
        raise ValueError(message)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def strict_json(data: bytes) -> dict:
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "Duplicate JSON key: " + key)
            result[key] = value
        return result
    result = json.loads(data, object_pairs_hook=pairs)
    require(isinstance(result, dict), "JSON document must be an object")
    return result


def safe_name(name: str, *, directory: bool = False) -> str:
    require(isinstance(name, str) and bool(name), "Empty/non-string path")
    # A trailing slash is tar's directory spelling, never a second file identity.
    value = name[:-1] if directory and name.endswith("/") else name
    parts = value.split("/")
    require(not value.startswith("/") and "\\" not in value and
            not re.match(r"^[A-Za-z]:", value) and
            all(part not in ("", ".", "..") for part in parts) and
            all(ord(char) >= 32 and ord(char) != 127 for char in value) and
            PurePosixPath(value).as_posix() == value,
            "Unsafe/noncanonical path: " + repr(name))
    return value


def no_symlinks(path: Path) -> None:
    for parent in (path.absolute(), *path.absolute().parents):
        require(not parent.is_symlink(), "Symlink input: " + str(parent))


def regular_bytes(path: Path, maximum: int) -> bytes:
    path = path.absolute()
    no_symlinks(path)
    initial = path.lstat()
    require(stat.S_ISREG(initial.st_mode) and initial.st_size <= maximum,
            "Input is not a bounded regular file: " + str(path))
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_size <= maximum and
                (info.st_dev, info.st_ino) == (initial.st_dev, initial.st_ino),
                "Input is not a bounded regular file: " + str(path))
        data = stream.read(maximum + 1)
    require(len(data) <= maximum, "Input exceeded size bound: " + str(path))
    return data


def archive_files(data: bytes) -> dict[str, bytes]:
    require(len(data) <= MAX_ARCHIVE, "Archive exceeds compressed size bound")
    result, entries, total = {}, {}, 0
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            require(len(entries) < MAX_ENTRIES, "Archive entry limit exceeded")
            name = safe_name(member.name, directory=member.isdir())
            require(name not in entries, "Duplicate archive path: " + name)
            require(member.isdir() or member.isfile(),
                    "Archive link/device/unsupported entry: " + name)
            entries[name] = "directory" if member.isdir() else "file"
            if member.isdir():
                continue
            require(0 <= member.size <= MAX_FILE, "Archive member exceeds size bound")
            total += member.size
            require(total <= MAX_TREE, "Archive expanded size bound exceeded")
            stream = archive.extractfile(member)
            require(stream is not None, "Unreadable archive member: " + name)
            content = stream.read(MAX_FILE + 1)
            require(len(content) == member.size, "Archive member size mismatch: " + name)
            result[name] = content
    require(bool(result), "Archive contains no files")
    for name in entries:
        for parent in PurePosixPath(name).parents:
            require(entries.get(parent.as_posix()) != "file",
                    "Archive file/directory collision: " + name)
    return result


def tree_files(directory: Path) -> dict[str, bytes]:
    require(directory.is_dir(), "Fork directory missing: " + str(directory))
    for parent in (directory.absolute(), *directory.absolute().parents):
        require(not parent.is_symlink(), "Symlink fork directory: " + str(parent))
    result, total = {}, 0
    # No generated/cache exclusions: this verifier binds every retained file.
    def traversal_error(error):
        raise error
    for current, dirs, files in os.walk(directory, followlinks=False, onerror=traversal_error):
        for name in sorted(dirs + files):
            path = Path(current) / name
            require(not path.is_symlink(), "Symlink fork input: " + str(path))
        for name in sorted(files):
            path = Path(current) / name
            relative = safe_name(path.relative_to(directory).as_posix())
            require(len(result) < MAX_ENTRIES, "Fork entry limit exceeded")
            content = regular_bytes(path, MAX_FILE)
            total += len(content)
            require(total <= MAX_TREE, "Fork size bound exceeded")
            result[relative] = content
    return result


def hashes(files: dict[str, bytes]) -> dict[str, str]:
    return {name: digest(content) for name, content in sorted(files.items())}


def tree_digest(files: dict[str, bytes]) -> str:
    # Same path/hash convention as the repository inventory, relative to package.
    return digest("".join(f"{name} {sha}\n" for name, sha in hashes(files).items()).encode())


def load_reviewed(name: str, manifest_dir: Path) -> tuple[dict, bytes]:
    raw = regular_bytes(manifest_dir / (name + ".json"), MAX_METADATA)
    require(digest(raw) == REVIEWED_MANIFEST_SHA256[name],
            "Reviewed delta manifest drift: " + name)
    manifest = strict_json(raw)
    require(manifest.get("schema_version") == 1 and manifest.get("package") == name and
            manifest.get("version") == PACKAGES[name] and
            manifest.get("fork_path") == "third_party/" + name,
            "Reviewed manifest package identity mismatch")
    return manifest, raw


def validate_metadata(metadata: dict, manifest: dict) -> None:
    name, version = manifest["package"], manifest["version"]
    expected = f"https://pub.dev/api/archives/{name}-{version}.tar.gz"
    pubspec = metadata.get("pubspec")
    require(metadata.get("version") == version and isinstance(pubspec, dict) and
            pubspec.get("name") == name and str(pubspec.get("version")) == version and
            metadata.get("archive_url") == expected and
            metadata.get("archive_sha256") == manifest["archive_sha256"],
            "Official metadata origin/identity/digest mismatch: " + name)


def compare(manifest: dict, upstream: dict[str, bytes], fork: dict[str, bytes]) -> dict:
    for name in (*upstream, *fork):
        safe_name(name)
    upstream_hashes = hashes(upstream)
    cached = fork.get("UPSTREAM-SHA256.json")
    require(cached is not None and digest(cached) == manifest["upstream_manifest_sha256"],
            "Retained upstream cache manifest drift")
    require(strict_json(cached) == upstream_hashes,
            "Retained upstream cache manifest does not match official archive files")
    license_names = {name for name in upstream if
                     PurePosixPath(name).name.upper() in
                     {"LICENSE", "LICENSE.TXT", "COPYING", "NOTICE", "NOTICE.TXT"}}
    require("LICENSE" in license_names and all(name in fork and fork[name] == upstream[name]
                                               for name in license_names),
            "Upstream license/notice loss or mutation")
    changed = sorted(name for name in upstream.keys() & fork.keys()
                     if upstream[name] != fork[name])
    added, omitted = sorted(fork.keys() - upstream.keys()), sorted(upstream.keys() - fork.keys())
    actual = {"changed": changed, "added": added, "omitted": omitted}
    for kind, names in actual.items():
        reviewed = manifest.get("delta", {}).get(kind)
        require(isinstance(reviewed, dict) and set(reviewed) == set(names),
                "Unreviewed fork delta: " + kind)
        for name in names:
            row = reviewed[name]
            require(isinstance(row, dict) and isinstance(row.get("rationale"), str) and
                    bool(row["rationale"].strip()), "Delta rationale missing: " + name)
            if kind != "added":
                require(row.get("upstream_sha256") == digest(upstream[name]),
                        "Reviewed upstream byte drift: " + name)
            if kind != "omitted":
                require(row.get("fork_sha256") == digest(fork[name]),
                        "Reviewed fork byte drift: " + name)
            if kind == "omitted":
                require(name.startswith(("example/", "test/")),
                        "Runtime/platform/package/license omission: " + name)
    return {
        "upstream_file_count": len(upstream), "retained_file_count": len(fork),
        "identical_common_file_count": len(upstream.keys() & fork.keys()) - len(changed),
        "changed": changed, "added": added, "omitted": omitted,
        "upstream_files_sha256": upstream_hashes, "retained_files_sha256": hashes(fork),
        "upstream_tree_sha256": tree_digest(upstream), "retained_tree_sha256": tree_digest(fork),
        "upstream_cache_manifest_matches_official_files": True,
        "unchanged_license_notice_files": sorted(license_names),
    }


def public_download(url: str, maximum: int) -> bytes:
    class ExactOrigin(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            require(newurl == url, "Unexpected public-download redirect origin")
            return super().redirect_request(req, fp, code, msg, headers, newurl)
    with urllib.request.build_opener(ExactOrigin()).open(url, timeout=30) as response:
        require(response.url == url, "Unexpected public-download origin")
        raw = response.read(maximum + 1)
    require(len(raw) <= maximum, "Public download exceeds size bound")
    return raw


def fetch(name: str, manifest: dict, cache_dir: Path) -> dict:
    api = f"https://pub.dev/api/packages/{name}/versions/{manifest['version']}"
    metadata_raw = public_download(api, MAX_METADATA)
    metadata = strict_json(metadata_raw)
    validate_metadata(metadata, manifest)
    archive = public_download(metadata["archive_url"], MAX_ARCHIVE)
    require(digest(archive) == manifest["archive_sha256"], "Official archive content digest mismatch")
    # Inspect before saving; neither fetch nor verify extracts tar paths to disk.
    archive_files(archive)
    directory = cache_dir / name
    no_symlinks(directory)
    directory.mkdir(parents=True, exist_ok=True)
    outputs = ((directory / "metadata.json", metadata_raw),
               (directory / f"{name}-{manifest['version']}.tar.gz", archive))
    require(all(not path.exists() and not path.is_symlink() for path, _ in outputs),
            "Fetch destination already exists; verify it or use a new cache directory")
    for path, raw in outputs:
        with path.open("xb") as stream:
            stream.write(raw)
    return {"package": name, "metadata_url": api, "archive_url": metadata["archive_url"],
            "metadata_sha256": digest(metadata_raw), "archive_sha256": digest(archive)}


def verify(name: str, manifest: dict, cache_dir: Path, root: Path) -> dict:
    directory = cache_dir / name
    metadata_raw = regular_bytes(directory / "metadata.json", MAX_METADATA)
    metadata = strict_json(metadata_raw)
    validate_metadata(metadata, manifest)
    archive = regular_bytes(directory / f"{name}-{manifest['version']}.tar.gz", MAX_ARCHIVE)
    require(digest(archive) == manifest["archive_sha256"], "Cached official archive content digest mismatch")
    upstream = archive_files(archive)
    fork = tree_files(root / manifest["fork_path"])
    result = compare(manifest, upstream, fork)
    require(tree_files(root / manifest["fork_path"]) == fork and
            regular_bytes(directory / "metadata.json", MAX_METADATA) == metadata_raw and
            regular_bytes(directory / f"{name}-{manifest['version']}.tar.gz", MAX_ARCHIVE) == archive,
            "Verification inputs changed during comparison")
    return {"package": name, "version": manifest["version"], "fork_path": manifest["fork_path"],
            "official_metadata_url": f"https://pub.dev/api/packages/{name}/versions/{manifest['version']}",
            "official_archive_url": metadata["archive_url"], "published": metadata.get("published"),
            "metadata_sha256": digest(metadata_raw), "archive_sha256": digest(archive), **result}


def overlaps_protected(path: Path, protected: list[Path]) -> bool:
    target = path.resolve(strict=False)
    canonical = [item.resolve(strict=False) for item in protected]
    if any(target == item or target.is_relative_to(item) for item in canonical):
        return True
    # resolve() preserves case spelling on macOS/ExFAT. Existing ancestor inode
    # identities also catch case/unicode aliases into a protected directory.
    identities = set()
    for item in canonical:
        try:
            info = item.stat()
            identities.add((info.st_dev, info.st_ino))
        except FileNotFoundError:
            pass
    for item in (target, *target.parents):
        try:
            info = item.stat()
            if (info.st_dev, info.st_ino) in identities:
                return True
        except FileNotFoundError:
            pass
    return False


def safe_output(path: Path, protected: list[Path]) -> None:
    no_symlinks(path)
    require(not overlaps_protected(path, protected), "Output may not modify verification inputs")
    if path.exists():
        info = path.lstat()
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
                "Output is not an unaliased regular file")


def write_output(path: Path, text: str, protected: list[Path]) -> None:
    safe_output(path, protected)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Replace the directory entry rather than truncating an existing inode. A
    # raced hardlink alias cannot write through into a verified source/cache file.
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
            safe_output(path, protected)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("fetch", "verify"))
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--cache-dir", type=Path, default=ROOT / ".cache/pub-fork-origin-v1")
    parser.add_argument("--manifest-dir", type=Path)
    parser.add_argument("--package", choices=tuple(PACKAGES), action="append")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    require(args.operation == "verify" or args.output is None, "Fetch does not write a verification receipt")
    root = args.root.absolute()
    no_symlinks(root)
    require(root.is_dir(), "Repository root missing")
    root = root.resolve()
    for target in (args.cache_dir.absolute(), args.output.absolute() if args.output else None):
        if target is not None:
            no_symlinks(target)
            require(not overlaps_protected(target, [root / "third_party" / name for name in PACKAGES]),
                    "Output/cache may not modify a fork")
    manifest_dir = args.manifest_dir or root / "scripts/supply_chain/fork_deltas"
    protected = [root / "third_party" / name for name in PACKAGES]
    protected += [Path(__file__), manifest_dir, args.cache_dir]
    if args.output:
        safe_output(args.output, protected)
    verifier_before = digest(regular_bytes(Path(__file__), MAX_FILE))
    results, inputs = [], {}
    for name in args.package or PACKAGES:
        manifest, raw = load_reviewed(name, manifest_dir)
        inputs[name] = digest(raw)
        results.append(fetch(name, manifest, args.cache_dir) if args.operation == "fetch" else
                       verify(name, manifest, args.cache_dir, root))
    # Per-package checks alone cannot establish a combined receipt: package one
    # may change while package two is read. Recheck the entire captured set.
    for result in results:
        name = result["package"]
        _, raw = load_reviewed(name, manifest_dir)
        require(digest(raw) == inputs[name], "Reviewed manifest changed during execution")
        directory = args.cache_dir / name
        require(digest(regular_bytes(directory / "metadata.json", MAX_METADATA)) == result["metadata_sha256"] and
                digest(regular_bytes(directory / f"{name}-{PACKAGES[name]}.tar.gz", MAX_ARCHIVE)) == result["archive_sha256"],
                "Package cache changed before combined receipt")
        if args.operation == "verify":
            require(hashes(tree_files(root / "third_party" / name)) == result["retained_files_sha256"],
                    "Fork changed before combined receipt: " + name)
    require(digest(regular_bytes(Path(__file__), MAX_FILE)) == verifier_before,
            "Verifier changed during execution")
    document = {"schema_version": 1, "status": "fetched_verified_public_archives" if args.operation == "fetch"
                else "pass_exact_official_origin_and_reviewed_fork_bytes",
                "network_used": args.operation == "fetch", "reviewed_delta_sha256": inputs,
                "verifier_sha256": verifier_before, "packages": results,
                "behavior_verified": False, "artifact_license_approval": False, "release_approved": False,
                "limitations": ["HTTPS pub.dev metadata and pinned archive hashes authenticate this registry origin; no independent publisher signature attestation.",
                                "Source comparison does not prove callback/auth behavior, provider/device acceptance, resolved signed-artifact contents, current advisory clearance or redistribution approval."]}
    text = json.dumps(document, indent=2, sort_keys=True) + "\n"
    if args.output:
        write_output(args.output, text, protected)
    else:
        print(text, end="")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, json.JSONDecodeError, tarfile.TarError) as error:
        raise SystemExit(str(error)) from error
