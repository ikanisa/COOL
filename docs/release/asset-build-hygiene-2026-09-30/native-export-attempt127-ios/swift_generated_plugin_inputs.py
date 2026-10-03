#!/usr/bin/env python3
"""Bind the generated Swift compiler aliases after Flutter's config-only step.

The resolved Dart/plugin JSON alone is insufficient: Flutter may regenerate
Swift aliases from cached plugin roots. This observes those actual aliases,
redirects hosted sources to their byte-verified export copies, and permits
only the pinned generator's relative plugin-dependency manifest rewrite.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path

MAX_FILES = 100_000
MAX_BYTES = 4 * 1024 ** 3
PACKAGE_NAME = re.compile(r"[a-z_][a-z0-9_]*")
DEPENDENCY = re.compile(r'\.package\(\s*name:\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*,\s*path:\s*"([^"\n]+)"\s*\)')


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def regular_tree(root: Path) -> dict[str, str]:
    if not root.is_dir() or root.is_symlink() or root.resolve() != root:
        raise ValueError("Canonical compiler source directory required")
    files, size = {}, 0
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError("Unexpected alias inside compiler source")
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError("Unsupported compiler source entry")
        if path.name.startswith(".env") or path.suffix in {".key", ".p12", ".p8", ".mobileprovision"}:
            raise ValueError("Private input inside compiler source")
        size += path.stat().st_size
        if len(files) >= MAX_FILES or size > MAX_BYTES:
            raise ValueError("Compiler source exceeds resource bound")
        files[path.relative_to(root).as_posix()] = sha(path)
    if not files:
        raise ValueError("Empty compiler source")
    return files


def _inventory(export: Path, binding: dict) -> tuple[Path, dict, dict, dict]:
    if export.resolve() != export or export.is_symlink():
        raise ValueError("Canonical immutable export required")
    plugins_path = export / ".flutter-plugins-dependencies"
    if sha(plugins_path) != binding["plugin_binding_sha256"]:
        raise ValueError("Resolved plugin binding changed")
    plugins = json.loads(plugins_path.read_text())["plugins"]["ios"]
    roots = {name: Path(row["build_root"]) for name, row in binding["packages"].items()}
    roots.update({name: Path(root) for name, root in binding["local_roots"].items()})
    expected, originals = {}, {}
    for plugin in plugins:
        name = plugin["name"]
        if not PACKAGE_NAME.fullmatch(name) or name in originals or name not in roots:
            raise ValueError("Invalid or duplicate resolved iOS plugin")
        root = roots[name]
        if Path(plugin["path"]).resolve() != root:
            raise ValueError("iOS plugin path differs from bound package")
        original = Path(binding["packages"].get(name, {}).get("original_root", root))
        originals[name] = original
        suffix = Path("darwin" if plugin.get("shared_darwin_source") else "ios") / name
        native = root / suffix
        if (native / "Package.swift").is_file():
            expected[name] = {"root": root, "original": original, "suffix": suffix, "native": native}
    package_dir = export / "ios/Flutter/ephemeral/Packages"
    aliases = package_dir / ".packages"
    generated = package_dir / "FlutterGeneratedPluginSwiftPackage"
    text = (generated / "Package.swift").read_text()
    matches = DEPENDENCY.findall(text)
    if len(matches) != text.count(".package(") or not matches:
        raise ValueError("Unknown generated Swift dependency directive")
    dependencies = {}
    for name, relative in matches:
        if name in dependencies or not relative.startswith("../.packages/"):
            raise ValueError("Duplicate or escaped Swift dependency")
        alias = relative.removeprefix("../.packages/")
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.+\-]*", alias):
            raise ValueError("Unsafe Swift alias")
        dependencies[name] = alias
    if set(dependencies) != set(expected) | {"FlutterFramework"}:
        raise ValueError("Generated Swift dependency inventory differs from bound plugins")
    if not aliases.is_dir() or aliases.is_symlink() or aliases.resolve() != aliases:
        raise ValueError("Canonical generated aliases required")
    if {p.name for p in aliases.iterdir()} != set(dependencies.values()):
        raise ValueError("Unknown, duplicate or missing generated alias")
    return aliases, generated, expected, dependencies


def bind(export: Path, binding: dict, declared_sources: dict[str, str], *, dry_run: bool = False) -> dict:
    aliases, generated, expected, dependencies = _inventory(export, binding)
    generated_files = regular_tree(generated)
    framework = aliases / dependencies["FlutterFramework"]
    if dependencies["FlutterFramework"] != "FlutterFramework" or framework.is_symlink():
        raise ValueError("Unknown generated Flutter framework alias")
    framework_files = regular_tree(framework)
    rows, plans = {}, []
    # CocoaPods and build hooks may consume a different generated alias tree.
    # Bind those package-root pointers too; full package byte verification is
    # supplied by the existing resolved-input receipt before and after build.
    pod_root = export / "ios/.symlinks/plugins"
    plugins = json.loads((export / ".flutter-plugins-dependencies").read_text())["plugins"]["ios"]
    native_plugins = {p["name"]: p for p in plugins if p.get("native_build") is True}
    if (not pod_root.is_dir() or pod_root.is_symlink() or pod_root.resolve() != pod_root
            or {p.name for p in pod_root.iterdir()} != set(native_plugins)):
        raise ValueError("Unknown or missing generated native plugin alias")
    pod_rows = {}
    for name, plugin in native_plugins.items():
        alias, target = pod_root / name, Path(plugin["path"]).resolve()
        original = Path(binding["packages"].get(name, {}).get("original_root", target))
        if not alias.is_symlink() or alias.resolve(strict=True) not in {target, original}:
            raise ValueError("Native plugin alias escapes bound package")
        prior = os.readlink(alias)
        if alias.resolve(strict=True) != target:
            plans.append((alias, prior, target))
        pod_rows[name] = {"alias": str(alias), "original_link": prior, "compiler_package_root": str(target)}
    for name, source in expected.items():
        alias = aliases / dependencies[name]
        valid_names = {name, source["root"].name, source["original"].name}
        if alias.name not in valid_names or not alias.is_symlink():
            raise ValueError("Unexpected native plugin alias: " + name)
        raw_target = os.readlink(alias)
        target = alias.resolve(strict=True)
        original_native = source["original"] / source["suffix"]
        copy_native = export / "build/ios/SourcePackages" / alias.name / source["suffix"]
        allowed = {source["native"], original_native, copy_native}
        if target not in allowed:
            raise ValueError("Compiler alias escapes declared input: " + name)
        source_map = regular_tree(source["native"])
        if name in binding["packages"]:
            prefix = source["suffix"].as_posix() + "/"
            expected_map = {path.removeprefix(prefix): digest
                            for path, digest in binding["packages"][name]["files"].items()
                            if path.startswith(prefix)}
        else:
            prefix = source["native"].relative_to(export).as_posix() + "/"
            expected_map = {path.removeprefix(prefix): digest
                            for path, digest in declared_sources.items() if path.startswith(prefix)}
        if not expected_map or source_map != expected_map:
            raise ValueError("Declared native source changed before alias binding: " + name)
        generated_rewrites = []
        if target == copy_native:
            actual_map = regular_tree(target)
            manifest = (source["native"] / "Package.swift").read_text()
            transformed = manifest
            # This is the pinned Flutter generator's exact replaceAll rule.
            # Every replacement refers to another declared Swift plugin alias.
            for dependency_name, dependency_alias in dependencies.items():
                old, new = '"../' + dependency_name + '"', '"../' + dependency_alias + '"'
                if old != new and old in transformed:
                    transformed = transformed.replace(old, new)
                    generated_rewrites.append({"original": old, "replacement": new})
            accepted_map = dict(source_map)
            accepted_map["Package.swift"] = hashlib.sha256(transformed.encode()).hexdigest()
            if not generated_rewrites or actual_map != accepted_map:
                raise ValueError("Unreviewed generated plugin source/manifest difference: " + name)
            build_native, before = target, actual_map
        else:
            if regular_tree(target) != source_map:
                raise ValueError("Generated alias target bytes differ: " + name)
            build_native, before = source["native"], source_map
            if target != build_native:
                plans.append((alias, raw_target, build_native))
        rows[name] = {"alias": str(alias), "original_link": raw_target,
                      "compiler_root": str(build_native), "files": before,
                      "declared_native_root": str(source["native"]), "declared_files": source_map,
                      "generated_manifest_rewrites": generated_rewrites}
    if dry_run:
        return {"status": "pass", "dry_run": True, "packages": rows,
                "native_package_aliases": pod_rows,
                "planned_redirections": [{"alias": str(alias), "before": prior, "after": str(target)}
                                         for alias, prior, target in plans],
                "generated_files": generated_files, "framework_files": framework_files,
                "scope": "Read-only actual generated compiler-path reconciliation; no aliases or historical build evidence changed and no immutable compiler-root acceptance claimed."}
    # Validate every input before redirecting any alias; then check exact guards.
    for alias, prior, target in plans:
        if not alias.is_symlink() or os.readlink(alias) != prior:
            raise ValueError("Compiler alias changed before binding")
        alias.unlink()
        alias.symlink_to(target, target_is_directory=True)
    for row in rows.values():
        alias = Path(row["alias"])
        row["bound_link"] = os.readlink(alias)
        if alias.resolve(strict=True) != Path(row["compiler_root"]) or regular_tree(Path(row["compiler_root"])) != row["files"]:
            raise ValueError("Compiler source changed during alias binding")
    for row in pod_rows.values():
        alias = Path(row["alias"])
        row["bound_link"] = os.readlink(alias)
        if alias.resolve(strict=True) != Path(row["compiler_package_root"]):
            raise ValueError("Native plugin alias changed during binding")
    if regular_tree(generated) != generated_files or regular_tree(framework) != framework_files:
        raise ValueError("Generated Swift scaffold changed during binding")
    return {"schema_version": 1, "status": "pass", "kind": "actual_generated_swift_compiler_input_binding",
            "packages": rows, "generated_root": str(generated), "generated_files": generated_files,
            "framework_root": str(framework), "framework_files": framework_files,
            "alias_root": str(aliases), "alias_names": sorted(p.name for p in aliases.iterdir()),
            "native_package_alias_root": str(pod_root), "native_package_aliases": pod_rows,
            "plugin_binding_sha256": binding["plugin_binding_sha256"],
            "declared_application_source_map_sha256": hashlib.sha256(json.dumps(declared_sources, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
            "scope": "Actual generated plugin Swift compiler roots and aliases bound before Xcode; hosted aliases redirected to immutable export copies. Only exact declared relative plugin-version rewrites are permitted in generated platform copies. Generated scaffolds are byte bound; no complete Xcode/SDK cache attestation."}


def verify(receipt: dict, export: Path) -> dict:
    changes = {}
    aliases = Path(receipt["alias_root"])
    if sorted(p.name for p in aliases.iterdir()) != receipt["alias_names"]:
        changes["alias_inventory"] = "Generated alias added or deleted"
    if aliases.is_symlink() or aliases.resolve() != aliases:
        changes["alias_inventory"] = "Generated alias directory replaced"
    pod_root = Path(receipt["native_package_alias_root"])
    if (pod_root.is_symlink() or pod_root.resolve() != pod_root
            or {p.name for p in pod_root.iterdir()} != set(receipt["native_package_aliases"])):
        changes["native_package_aliases"] = "Generated native alias directory/inventory changed"
    for name, row in receipt["native_package_aliases"].items():
        alias = Path(row["alias"])
        if (not alias.is_symlink() or os.readlink(alias) != row["bound_link"]
                or alias.resolve(strict=True) != Path(row["compiler_package_root"])):
            changes["native_alias_" + name] = "Generated native package pointer changed"
    for name, row in receipt["packages"].items():
        alias = Path(row["alias"])
        if (not alias.is_symlink() or os.readlink(alias) != row["bound_link"]
                or alias.resolve(strict=True) != Path(row["compiler_root"])):
            changes[name] = "Actual compiler alias changed"
        elif (regular_tree(Path(row["compiler_root"])) != row["files"]
              or regular_tree(Path(row["declared_native_root"])) != row["declared_files"]):
            changes[name] = "Actual or declared compiler source changed"
    for label in ("generated", "framework"):
        if regular_tree(Path(receipt[label + "_root"])) != receipt[label + "_files"]:
            changes[label] = "Generated Swift source added, deleted or changed"
    if sha(export / ".flutter-plugins-dependencies") != receipt["plugin_binding_sha256"]:
        changes["plugins"] = "Resolved plugin binding changed"
    return {"status": "pass" if not changes else "fail", "changes": changes,
            "compiler_packages": len(receipt["packages"]), "scope": receipt["scope"]}
