#!/usr/bin/env python3
"""Bind copied Swift binary artifacts before Xcode can read an older export.

The recorded remote archive checksums are metadata, not verified downloads.
This tool binds actual extracted bytes, modes and internal symlink targets.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat


def require(condition, message):
    if not condition:
        raise ValueError(message)


def regular_json(path):
    require(path.is_file() and not path.is_symlink(), "Expected regular JSON input")
    return json.loads(path.read_text())


def digest(path):
    before = path.stat()
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    after = path.stat()
    require(
        (before.st_size, before.st_mtime_ns, before.st_ino)
        == (after.st_size, after.st_mtime_ns, after.st_ino),
        "Input changed while hashing",
    )
    return result.hexdigest()


def artifact_tree(root):
    require(root.is_dir() and not root.is_symlink(), "Missing regular artifact root")
    require(root.resolve() == root, "Artifact root contains an alias")
    result = {}
    total_bytes = 0
    for base, directories, files in os.walk(root, followlinks=False):
        for name in sorted(directories + files):
            path = Path(base) / name
            relative = path.relative_to(root).as_posix()
            info = path.lstat()
            mode = stat.S_IMODE(info.st_mode)
            if path.is_symlink():
                target = path.resolve(strict=True)
                require(target.is_relative_to(root), "Artifact symlink escapes its copied root")
                require(target.is_file() or target.is_dir(), "Unsupported artifact symlink target")
                result[relative] = {
                    "kind": "symlink",
                    "mode": mode,
                    "target": os.readlink(path),
                    "resolved_relative_path": target.relative_to(root).as_posix(),
                }
            elif path.is_dir():
                result[relative] = {"kind": "directory", "mode": mode}
            else:
                require(stat.S_ISREG(info.st_mode), "Unsupported artifact filesystem input")
                require(info.st_size <= 512 * 1024 * 1024, "Artifact file exceeds size bound")
                total_bytes += info.st_size
                require(total_bytes <= 5 * 1024 * 1024 * 1024, "Artifact tree exceeds size bound")
                result[relative] = {
                    "kind": "file", "mode": mode, "bytes": info.st_size, "sha256": digest(path)
                }
            require(len(result) <= 100000, "Artifact tree exceeds entry bound")
    require(result, "Artifact tree is empty")
    return result


def checked_state(export, state, prior_cache=None):
    cache = export / "build/ios/SourcePackages"
    artifact_root = cache / "artifacts"
    lock = regular_json(export / "ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    pins = {row["identity"]: row["state"]["revision"] for row in lock["pins"]}
    require(len(pins) == len(lock["pins"]) and pins, "Duplicate or missing locked package")
    require(isinstance(state, dict) and isinstance(state.get("version"), int), "Unknown workspace state")
    contents = state.get("object")
    require(isinstance(contents, dict), "Missing workspace state object")
    require(contents.get("prebuilts") == [], "Unbound Swift prebuilt inputs")
    dependencies = contents.get("dependencies")
    require(isinstance(dependencies, list), "Missing workspace dependencies")
    identities = []
    for row in dependencies:
        identity = row["packageRef"]["identity"]
        require(row["packageRef"]["kind"] == "remoteSourceControl", "Unknown dependency input kind")
        require(identity in pins and row["subpath"] == identity, "Unexpected dependency identity/path")
        require(row["state"]["name"] == "sourceControlCheckout", "Unknown dependency state")
        require(row["state"]["checkoutState"]["revision"] == pins[identity], "Dependency revision differs from lock")
        identities.append(identity)
    require(len(identities) == len(set(identities)) and set(identities) == set(pins), "Workspace dependency set differs from lock")
    artifacts = contents.get("artifacts")
    require(isinstance(artifacts, list) and artifacts, "Missing binary artifacts")
    changes = []
    paths = set()
    for row in artifacts:
        identity = row["packageRef"]["identity"]
        target = row["targetName"]
        require(identity in pins and re.fullmatch(r"[a-z0-9-]+", identity), "Unknown binary package")
        require(re.fullmatch(r"[A-Za-z0-9_]+", target), "Invalid binary target")
        relative = Path(identity) / target / (target + ".xcframework")
        expected = artifact_root / relative
        prior = Path(row["path"])
        if prior_cache is None:
            require(prior == expected, "Binary artifact refers outside this export")
        else:
            require(prior == prior_cache / "artifacts" / relative, "Unexpected prior artifact path")
            row["path"] = str(expected)
            changes.append({"before": str(prior), "after": str(expected)})
        require(str(expected) not in paths, "Duplicate binary artifact path")
        paths.add(str(expected))
        require(expected.is_dir() and expected.resolve() == expected, "Missing or aliased binary artifact")
        source = row["source"]
        require(source.get("type") == "remote", "Unknown binary artifact source")
        require(re.fullmatch(r"[a-f0-9]{64}", source.get("checksum", "")), "Invalid recorded archive checksum")
        require(source.get("url", "").startswith("https://dl.google.com/"), "Unexpected recorded binary archive origin")
    allowed_roots = {row["packageRef"]["identity"] for row in artifacts} | {"extract"}
    require(all(path.name in allowed_roots for path in artifact_root.iterdir()), "Unknown cached artifact root")
    return changes


def bind(export, prior_cache):
    export, prior_cache = Path(export), Path(prior_cache)
    require(export.is_absolute() and export.resolve() == export, "Export is not an explicit regular root")
    require(prior_cache.is_absolute() and prior_cache.resolve() == prior_cache, "Prior cache is not an explicit regular root")
    state_path = export / "build/ios/SourcePackages/workspace-state.json"
    prior_state_path = prior_cache / "workspace-state.json"
    state = regular_json(state_path)
    require(state == regular_json(prior_state_path), "Copied workspace state differs before relocation")
    before_sha = digest(state_path)
    changes = checked_state(export, state, prior_cache)
    tree = artifact_tree(export / "build/ios/SourcePackages/artifacts")
    require(tree == artifact_tree(prior_cache / "artifacts"), "Copied binary artifacts differ from the preserved cache")
    require(digest(state_path) == before_sha, "Workspace state changed before guarded relocation")
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    checked_state(export, regular_json(state_path))
    return {
        "status": "pass", "kind": "copied_swift_binary_artifact_binding", "export": str(export),
        "prior_cache": str(prior_cache), "workspace_state_before_sha256": before_sha,
        "workspace_state_after_sha256": digest(state_path), "workspace_state": state,
        "package_lock_sha256": digest(export / "ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved"),
        "relocations": changes, "artifact_tree": tree,
        "regular_file_count": sum(row["kind"] == "file" for row in tree.values()),
        "symlink_count": sum(row["kind"] == "symlink" for row in tree.values()),
        "regular_file_bytes": sum(row.get("bytes", 0) for row in tree.values()),
        "scope": "Actual copied cache bytes, modes, complete entry set and internal symlinks; exact locked dependency identities and revisions; guarded path-only workspace relocation. Recorded archive checksums are not download authenticity, toolchain or runtime acceptance.",
    }


def verify(binding):
    require(binding.get("status") == "pass" and binding.get("kind") == "copied_swift_binary_artifact_binding", "Unknown artifact binding")
    export = Path(binding["export"])
    state_path = export / "build/ios/SourcePackages/workspace-state.json"
    state = regular_json(state_path)
    checked_state(export, state)
    require(state == binding["workspace_state"], "Workspace metadata changed during compilation")
    require(digest(export / "ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved") == binding["package_lock_sha256"], "Swift package lock changed")
    tree = artifact_tree(export / "build/ios/SourcePackages/artifacts")
    require(tree == binding["artifact_tree"], "Cached binary artifact input changed, appeared or disappeared")
    return {
        "status": "pass", "cached_binary_inputs_unchanged": True,
        "workspace_metadata_unchanged": True, "workspace_state_after_build_sha256": digest(state_path),
        "workspace_bytes_unchanged": digest(state_path) == binding["workspace_state_after_sha256"],
        "regular_file_count": binding["regular_file_count"], "symlink_count": binding["symlink_count"],
        "regular_file_bytes": binding["regular_file_bytes"], "scope": binding["scope"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["bind", "verify"])
    parser.add_argument("--export", type=Path)
    parser.add_argument("--prior-cache", type=Path)
    parser.add_argument("--binding", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.operation == "bind":
        require(args.export is not None and args.prior_cache is not None, "Bind requires both roots")
        result = bind(args.export, args.prior_cache)
    else:
        require(args.binding is not None, "Verify requires a binding")
        result = verify(regular_json(args.binding))
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: result[key] for key in ["status", "regular_file_count", "symlink_count", "regular_file_bytes"]}))


if __name__ == "__main__":
    main()
