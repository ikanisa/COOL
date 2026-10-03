#!/usr/bin/env python3
"""Bind actual resolved Pub/plugin inputs for local native compilation.

Hosted inputs are copied into the export. SDK packages remain in the explicit
pinned SDK and their source bytes are recorded. This is a local byte binding,
not registry authenticity or a complete SDK/artifact attestation.
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit

EXCLUDED_ROOTS = {".git", ".dart_tool", ".gradle", "build", "Pods", "example", "examples",
                  "test", "tests", "doc", "docs", "benchmark", "benchmarks", "__pycache__"}
PRIVATE_NAMES = {"key.properties", "google-services.json", "GoogleService-Info.plist"}
PRIVATE_SUFFIXES = {".jks", ".keystore", ".p12", ".pfx", ".p8", ".mobileprovision", ".key"}
SDK_PACKAGES = {"flutter", "flutter_test", "flutter_localizations", "integration_test",
                "sky_engine", "flutter_web_plugins", "flutter_driver", "fuchsia_remote_debug_protocol"}
LOCAL_PACKAGES = {"collect_app": "", "file_saver": "third_party/file_saver",
                  "gotrue": "third_party/gotrue", "firebase_messaging": "third_party/firebase_messaging"}
MAX_FILES = 100_000
MAX_BYTES = 4 * 1024 ** 3


def sha(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def canonical(directory: Path) -> Path:
    if not directory.is_dir() or directory.absolute() != directory.resolve() or directory.is_symlink():
        raise ValueError("Explicit canonical directory required")
    return directory


def source_files(directory: Path) -> dict[str, str]:
    """Observe all regular source/assets/platform files outside root QA/caches."""
    canonical(directory)
    files, size = {}, 0
    pending = [directory]
    while pending:
        current = pending.pop()
        for path in sorted(current.iterdir()):
            relative = path.relative_to(directory)
            if relative.parts[0] in EXCLUDED_ROOTS:
                continue
            if path.is_symlink():
                raise ValueError("Resolved package source contains a symlink: " + relative.as_posix())
            if path.is_dir():
                pending.append(path)
            elif path.is_file():
                if (path.name in PRIVATE_NAMES or path.suffix.lower() in PRIVATE_SUFFIXES
                        or path.name.startswith(".env")):
                    raise ValueError("Private configuration in a resolved package source")
                size += path.stat().st_size
                if len(files) >= MAX_FILES or size > MAX_BYTES:
                    raise ValueError("Resolved package source exceeds local resource bounds")
                files[relative.as_posix()] = sha(path)
            else:
                raise ValueError("Unsupported resolved package source entry")
    if not files:
        raise ValueError("Resolved package source is empty")
    return dict(sorted(files.items()))


def resolved_path(config_path: Path, uri: str) -> Path:
    if not isinstance(uri, str) or not uri:
        raise ValueError("Missing resolved package URI")
    resolved = urlsplit(urljoin(config_path.as_uri(), uri))
    if resolved.scheme != "file" or resolved.netloc or resolved.query or resolved.fragment:
        raise ValueError("Resolved package must have a local file URI")
    path = Path(unquote(resolved.path))
    if path.absolute() != path.resolve() or path.is_symlink() or not path.is_dir():
        raise ValueError("Resolved package source is missing or aliased")
    return path


def bind(export: Path, sdk: Path, pub_cache: Path) -> dict:
    export, sdk, pub_cache = map(canonical, (export, sdk, pub_cache))
    config_path = export / ".dart_tool/package_config.json"
    plugins_path = export / ".flutter-plugins-dependencies"
    original_config, original_plugins = config_path.read_bytes(), plugins_path.read_bytes()
    config, plugins = json.loads(original_config), json.loads(original_plugins)
    packages = config.get("packages")
    if config.get("configVersion") != 2 or not isinstance(packages, list) or not 1 <= len(packages) <= 512:
        raise ValueError("Malformed resolved package inventory")
    destination = export / ".qa_native_dependencies"
    if destination.exists():
        raise ValueError("Fresh native dependency destination required")
    rows, names, targets = {}, set(), {}
    total_files, total_bytes = 0, 0
    for package in packages:
        name = package.get("name") if isinstance(package, dict) else None
        if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", name) or name in names:
            raise ValueError("Missing, duplicate or unsafe resolved package name")
        names.add(name)
        source = resolved_path(config_path, package.get("rootUri"))
        if name in LOCAL_PACKAGES:
            expected = export / LOCAL_PACKAGES[name]
            if source != expected:
                raise ValueError("Controlled local package points outside export: " + name)
            targets[name] = source
            continue
        if name in SDK_PACKAGES:
            expected = sdk / ("bin/cache/pkg/sky_engine" if name == "sky_engine" else "packages/" + name)
            if source != expected:
                raise ValueError("SDK package points outside selected SDK: " + name)
            role, target = "sdk", source
        else:
            if not source.is_relative_to(pub_cache / "hosted"):
                raise ValueError("Hosted package points outside selected Pub cache: " + name)
            role, target = "hosted", destination / name
        files = source_files(source)
        total_files += len(files)
        total_bytes += sum((source / relative).stat().st_size for relative in files)
        if total_files > MAX_FILES or total_bytes > MAX_BYTES:
            raise ValueError("Aggregate resolved inputs exceed local resource bounds")
        rows[name] = {"role": role, "original_root": str(source), "build_root": str(target),
                      "files": files}
        targets[name] = target
    if not set(LOCAL_PACKAGES).issubset(names):
        raise ValueError("Controlled app/fork bindings are incomplete")
    # Validate every plugin before mutating generated bindings or creating copies.
    platforms = plugins.get("plugins")
    if not isinstance(platforms, dict) or any(not isinstance(value, list) for value in platforms.values()):
        raise ValueError("Malformed resolved plugin inventory")
    for entries in platforms.values():
        for plugin in entries:
            if not isinstance(plugin, dict) or plugin.get("name") not in targets:
                raise ValueError("Plugin source is absent from resolved package inventory")
            name = plugin["name"]
            path = plugin.get("path")
            expected = Path(rows[name]["original_root"]) if name in rows else targets[name]
            if not isinstance(path, str) or Path(path).resolve() != expected or Path(path).is_symlink():
                raise ValueError("Plugin source differs from resolved package")
    destination.mkdir()
    for name, row in rows.items():
        if row["role"] != "hosted":
            continue
        source, target = Path(row["original_root"]), Path(row["build_root"])
        target.mkdir()
        for relative, digest in row["files"].items():
            original, copied = source / relative, target / relative
            copied.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(original, copied)
            if sha(original) != digest or sha(copied) != digest:
                raise ValueError("Hosted input changed while copying: " + name)
    for name, row in rows.items():
        if source_files(Path(row["original_root"])) != row["files"]:
            raise ValueError("Resolved input set changed during copying: " + name)
        if row["role"] == "hosted" and source_files(Path(row["build_root"])) != row["files"]:
            raise ValueError("Copied hosted input set differs: " + name)
    if config_path.read_bytes() != original_config or plugins_path.read_bytes() != original_plugins:
        raise ValueError("Generated bindings changed during dependency copy")
    for package in packages:
        if package["name"] in rows and rows[package["name"]]["role"] == "hosted":
            package["rootUri"] = targets[package["name"]].as_uri() + "/"
    for entries in platforms.values():
        for plugin in entries:
            plugin["path"] = str(targets[plugin["name"]]) + "/"
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    plugins_path.write_text(json.dumps(plugins, indent=2) + "\n")
    return {"schema_version": 1, "kind": "actual_resolved_native_package_byte_binding",
            "packages": rows, "local_roots": {name: str(targets[name]) for name in LOCAL_PACKAGES},
            "package_config_sha256": sha(config_path), "plugin_binding_sha256": sha(plugins_path),
            "original_package_config_sha256": hashlib.sha256(original_config).hexdigest(),
            "original_plugin_binding_sha256": hashlib.sha256(original_plugins).hexdigest(),
            "excluded_root_directories": sorted(EXCLUDED_ROOTS),
            "scope": "Copied hosted compiler/plugin source, assets and native files; actual SDK package source bytes. Root examples/tests/docs/generated caches are excluded. No registry authenticity or complete SDK/toolchain attestation."}


def verify(binding: dict, export: Path) -> dict:
    canonical(export)
    changes = {}
    for name, row in binding["packages"].items():
        root = Path(row["build_root"])
        observed = source_files(root)
        expected = row["files"]
        drift = {path: {"before": expected.get(path), "after": observed.get(path)}
                 for path in sorted(expected.keys() | observed.keys()) if expected.get(path) != observed.get(path)}
        if drift:
            changes[name] = drift
    config = export / ".dart_tool/package_config.json"
    plugins = export / ".flutter-plugins-dependencies"
    if sha(config) != binding["package_config_sha256"] or sha(plugins) != binding["plugin_binding_sha256"]:
        changes["generated_bindings"] = {"package_config_sha256": sha(config), "plugin_binding_sha256": sha(plugins)}
    return {"status": "pass" if not changes else "fail", "changes": changes,
            "packages": len(binding["packages"]),
            "bound_package_files": sum(len(row["files"]) for row in binding["packages"].values()),
            "scope": binding["scope"]}
