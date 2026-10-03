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


def generated_local_packages(export, binding):
    """Require the complete, independently bound generated compiler aliases."""
    if binding is None:
        return {}
    require(binding.get("status") == "pass"
            and binding.get("kind") == "actual_generated_swift_compiler_input_binding",
            "Unknown generated compiler binding")
    aliases = export / "ios/Flutter/ephemeral/Packages/.packages"
    require(binding["alias_root"] == str(aliases), "Generated aliases belong to another export")
    rows = {}
    packages = binding["packages"]
    require(isinstance(packages, dict) and packages, "Missing bound local plugins")
    for name, row in packages.items():
        alias = Path(row["alias"])
        require(alias.parent == aliases and alias.is_symlink(), "Unknown local package alias")
        require(os.readlink(alias) == row["bound_link"]
                and alias.resolve(strict=True) == Path(row["compiler_root"]), "Local compiler alias changed")
        tree = artifact_tree(Path(row["compiler_root"]))
        require(not any(value["kind"] == "symlink" for value in tree.values()), "Unbound local compiler symlink")
        files = {path: value["sha256"] for path, value in tree.items() if value["kind"] == "file"}
        require(files == row["files"], "Bound local compiler files changed")
        identity = alias.name.lower()
        require(identity not in rows, "Duplicate generated local identity")
        rows[identity] = {"location": str(alias), "name": name}
    framework = aliases / "FlutterFramework"
    require(binding["framework_root"] == str(framework), "Unknown generated framework path")
    tree = artifact_tree(framework)
    require(not any(value["kind"] == "symlink" for value in tree.values()), "Unbound framework symlink")
    require({path: value["sha256"] for path, value in tree.items() if value["kind"] == "file"}
            == binding["framework_files"], "Bound generated framework files changed")
    rows["flutterframework"] = {"location": str(framework), "name": "FlutterFramework"}
    require(sorted(path.name for path in aliases.iterdir()) == binding["alias_names"]
            and {path.name.lower() for path in aliases.iterdir()} == set(rows), "Local alias inventory differs")
    return rows


def checked_state(export, state, prior_cache=None, local_packages=None):
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
    local_identities = []
    local_packages = local_packages or {}
    changes = []
    for row in dependencies:
        identity = row["packageRef"]["identity"]
        if row["packageRef"]["kind"] == "fileSystem":
            matches = [(key, value) for key, value in local_packages.items()
                       if value["name"] == row["packageRef"]["name"]]
            require(len(matches) == 1, "Unbound local workspace dependency")
            current_identity, expected = matches[0]
            require(row["subpath"].lower() == identity and row.get("basedOn") is None,
                    "Unknown local dependency metadata")
            require(row["state"]["name"] == "fileSystem", "Unknown local dependency state")
            location = Path(expected["location"])
            prior = Path(row["packageRef"]["location"])
            if prior_cache:
                require(prior.parent == prior_cache.parents[2] / location.parent.relative_to(export)
                        and prior.name.lower() == identity
                        and (prior.name == location.name or re.fullmatch(
                            re.escape(expected["name"]) + r"-[0-9]+(?:[A-Za-z0-9.+-]*)", prior.name)),
                        "Unknown prior local package alias")
            else:
                require(identity == current_identity and prior == location,
                        "Local workspace dependency refers outside its expected export")
            require(row["packageRef"]["location"] == row["state"]["path"] == str(prior),
                    "Local workspace dependency refers outside its expected export")
            if prior_cache:
                row["packageRef"]["location"] = row["state"]["path"] = str(location)
                row["packageRef"]["identity"] = current_identity
                row["subpath"] = location.name
                changes.append({"kind": "local_package", "before_identity": identity,
                                "after_identity": current_identity, "before": str(prior), "after": str(location)})
            local_identities.append(current_identity)
            continue
        require(row["packageRef"]["kind"] == "remoteSourceControl", "Unknown dependency input kind")
        require(identity in pins and isinstance(row["subpath"], str)
                and row["subpath"].lower() == identity, "Unexpected dependency identity/path")
        require(row["state"]["name"] == "sourceControlCheckout", "Unknown dependency state")
        require(row["state"]["checkoutState"]["revision"] == pins[identity], "Dependency revision differs from lock")
        identities.append(identity)
    require(len(identities) == len(set(identities)) and set(identities) == set(pins), "Workspace dependency set differs from lock")
    require(len(local_identities) == len(set(local_identities)) and set(local_identities) == set(local_packages),
            "Workspace local dependency set differs from generated bindings")
    artifacts = contents.get("artifacts")
    require(isinstance(artifacts, list) and artifacts, "Missing binary artifacts")
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


def bind(export, prior_cache, generated_binding=None):
    export, prior_cache = Path(export), Path(prior_cache)
    require(export.is_absolute() and export.resolve() == export, "Export is not an explicit regular root")
    require(prior_cache.is_absolute() and prior_cache.resolve() == prior_cache, "Prior cache is not an explicit regular root")
    state_path = export / "build/ios/SourcePackages/workspace-state.json"
    prior_state_path = prior_cache / "workspace-state.json"
    state = regular_json(state_path)
    require(state == regular_json(prior_state_path), "Copied workspace state differs before relocation")
    before_sha = digest(state_path)
    locals = generated_local_packages(export, generated_binding)
    changes = checked_state(export, state, prior_cache, locals)
    tree = artifact_tree(export / "build/ios/SourcePackages/artifacts")
    require(tree == artifact_tree(prior_cache / "artifacts"), "Copied binary artifacts differ from the preserved cache")
    require(digest(state_path) == before_sha, "Workspace state changed before guarded relocation")
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    checked_state(export, regular_json(state_path), local_packages=locals)
    return {
        "status": "pass", "kind": "copied_swift_binary_artifact_binding", "export": str(export),
        "prior_cache": str(prior_cache), "workspace_state_before_sha256": before_sha,
        "workspace_state_after_sha256": digest(state_path), "workspace_state": state,
        "package_lock_sha256": digest(export / "ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved"),
        "relocations": changes, "artifact_tree": tree,
        "generated_compiler_binding": generated_binding, "local_package_count": len(locals),
        "regular_file_count": sum(row["kind"] == "file" for row in tree.values()),
        "symlink_count": sum(row["kind"] == "symlink" for row in tree.values()),
        "regular_file_bytes": sum(row.get("bytes", 0) for row in tree.values()),
        "scope": "Actual copied cache bytes, modes, complete entry set and internal symlinks; exact locked dependency identities and revisions; guarded path-only workspace relocation. Recorded archive checksums are not download authenticity, toolchain or runtime acceptance.",
    }


def workspace_metadata(state):
    """Swift resolver dependencies and artifacts are unique, unordered entries."""
    result = json.loads(json.dumps(state))
    contents = result["object"]
    contents["dependencies"].sort(key=lambda row: row["packageRef"]["identity"])
    contents["artifacts"].sort(key=lambda row: (row["packageRef"]["identity"], row["targetName"]))
    return result


def verify(binding):
    require(binding.get("status") == "pass" and binding.get("kind") == "copied_swift_binary_artifact_binding", "Unknown artifact binding")
    export = Path(binding["export"])
    state_path = export / "build/ios/SourcePackages/workspace-state.json"
    state = regular_json(state_path)
    locals = generated_local_packages(export, binding.get("generated_compiler_binding"))
    require(len(locals) == binding.get("local_package_count", 0), "Generated local package count changed")
    checked_state(export, state, local_packages=locals)
    require(workspace_metadata(state) == workspace_metadata(binding["workspace_state"]),
            "Workspace metadata changed during compilation")
    require(digest(export / "ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved") == binding["package_lock_sha256"], "Swift package lock changed")
    tree = artifact_tree(export / "build/ios/SourcePackages/artifacts")
    require(tree == binding["artifact_tree"], "Cached binary artifact input changed, appeared or disappeared")
    return {
        "status": "pass", "cached_binary_inputs_unchanged": True,
        "workspace_metadata_unchanged": True, "workspace_state_after_build_sha256": digest(state_path),
        "workspace_entry_order_changed": state != binding["workspace_state"],
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
    parser.add_argument("--generated-binding", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.operation == "bind":
        require(args.export is not None and args.prior_cache is not None, "Bind requires both roots")
        result = bind(args.export, args.prior_cache,
                      regular_json(args.generated_binding) if args.generated_binding else None)
    else:
        require(args.binding is not None, "Verify requires a binding")
        result = verify(regular_json(args.binding))
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: result[key] for key in ["status", "regular_file_count", "symlink_count", "regular_file_bytes"]}))


if __name__ == "__main__":
    main()
