#!/usr/bin/env python3
"""Build a deterministic source-level supply-chain inventory for Collect.

This is a candidate inventory, not an installed or signed-artifact SBOM. It
does not contact registries, install packages, or mutate dependency inputs.
Requires PyYAML for the repository's YAML lockfiles.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
from collections import Counter
from pathlib import Path
from urllib.parse import urlsplit

import yaml


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "docs/release/supply-chain-2026-09-28/candidate-inventory.json"


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def source(path: str, sources: dict[str, str]) -> Path:
    target = ROOT / path
    if not target.is_file():
        raise FileNotFoundError(path)
    sources[path] = digest(target)
    return target


def read_yaml(path: str, sources: dict[str, str]) -> dict:
    return yaml.safe_load(source(path, sources).read_text(encoding="utf-8"))


def read_json(path: str, sources: dict[str, str]) -> dict:
    return json.loads(source(path, sources).read_text(encoding="utf-8"))


def locked_json(path: str, sources: dict[str, str]) -> dict:
    """Bind the parsed lock to the same bytes and reject ambiguous JSON keys."""
    target = ROOT / path
    if target.is_symlink() or not target.is_file() or not target.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Lock source missing or outside checkout: " + path)
    raw = target.read_bytes()
    sources[path] = hashlib.sha256(raw).hexdigest()
    def unique(pairs):
        out = {}
        for key, value in pairs:
            if key in out:
                raise ValueError("Duplicate JSON key in " + path)
            out[key] = value
        return out
    value = json.loads(raw, object_pairs_hook=unique)
    if not isinstance(value, dict):
        raise ValueError("Lock object required: " + path)
    return value


def require_sri(value: str) -> str:
    match = re.fullmatch(r"sha(256|384|512)-([A-Za-z0-9+/=]+)", value) if isinstance(value, str) else None
    if not match:
        raise ValueError("Strong lock integrity required")
    try:
        raw = base64.b64decode(match[2], validate=True)
    except ValueError as error:
        raise ValueError("Invalid lock integrity") from error
    if len(raw) * 8 != int(match[1]) or base64.b64encode(raw).decode() != match[2]:
        raise ValueError("Invalid lock integrity")
    return value


def local_tree_hash(directory: str, sources: dict[str, str] | None = None) -> tuple[str, int]:
    base = ROOT / directory
    if not base.is_dir() or base.is_symlink() or not base.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Local package tree is absent or escapes checkout: " + directory)
    if any(parent.is_symlink() for parent in (base, *base.parents) if parent.is_relative_to(ROOT)):
        raise ValueError("Local package source symlink is unsupported: " + directory)
    excluded = {".git", ".gradle", ".dart_tool", "build", "__pycache__"}
    candidates = [path for path in base.rglob("*")
                  if not any(part in excluded for part in path.relative_to(base).parts)]
    if any(path.is_symlink() or not path.resolve().is_relative_to(base.resolve()) for path in candidates):
        raise ValueError("Local package source symlink is unsupported: " + directory)
    paths = sorted(path for path in candidates if path.is_file())
    hashes = {rel(path): digest(path) for path in paths}
    if sources is not None:
        sources.update(hashes)
    manifest = "".join(f"{path} {sha}\n" for path, sha in hashes.items())
    return hashlib.sha256(manifest.encode("utf-8")).hexdigest(), len(paths)


def row(ecosystem: str, name: str, version: str | None, relationship: str,
        evidence: str, *, integrity: str | None = None,
        license_assertion: str | None = None, license_evidence: str = "unknown",
        origin: str | None = None, qualifier: str | None = None) -> dict:
    return {
        "ecosystem": ecosystem,
        "name": name,
        "version": version,
        "relationship": relationship,
        "evidence": evidence,
        "integrity": integrity,
        "license_assertion": license_assertion,
        "license_evidence": license_evidence,
        "origin": origin,
        "qualifier": qualifier,
    }


def dart_packages(sources: dict[str, str]) -> tuple[list[dict], dict]:
    manifest = read_yaml("pubspec.yaml", sources)
    lock = read_yaml("pubspec.lock", sources)
    declared = {}
    for section in ("dependencies", "dev_dependencies", "dependency_overrides"):
        declared.update(manifest.get(section, {}))
    licensed_paths = {"file_saver": ("third_party/file_saver", "BSD-3-Clause"),
                      "firebase_messaging": ("third_party/firebase_messaging", "BSD-3-Clause")}
    forks = {}
    packages = []
    for name, entry in sorted(lock["packages"].items()):
        desc = entry.get("description") or {}
        src = entry.get("source")
        origin = desc.get("url") if isinstance(desc, dict) else None
        integrity = desc.get("sha256") if isinstance(desc, dict) else None
        license_assertion = None
        if src == "path":
            path = desc.get("path") if isinstance(desc, dict) else None
            declaration = declared.get(name)
            if (not isinstance(path, str) or not path or Path(path).is_absolute()
                    or ".." in Path(path).parts or Path(path).as_posix() != path
                    or "\\" in path or any(ord(char) < 32 for char in path)
                    or path == "." or desc.get("relative") is not True
                    or not isinstance(declaration, dict) or declaration.get("path") != path):
                raise ValueError("Local package lock/declaration path mismatch: " + name)
            fork_sha, fork_files = local_tree_hash(path, sources)
            fork = read_yaml(path + "/pubspec.yaml", sources)
            if fork.get("name") != name or str(fork.get("version")) != str(entry.get("version")):
                raise ValueError("Local package name/version does not match lock: " + name)
            source(path + "/LICENSE", sources)
            source(path + "/COLLECT_FORK.md", sources)
            license_path, license_id = licensed_paths.get(name, (None, None))
            license_assertion = license_id if path == license_path else None
            forks[name] = {"path": path, "version": fork.get("version"),
                           "tree_sha256": fork_sha, "tree_file_count": fork_files,
                           "integrity_scope": "Path/name plus SHA-256 manifest of local regular source files; not a hosted archive digest",
                           "license_text": path + "/LICENSE", "upstream_provenance": path + "/COLLECT_FORK.md"}
            upstream_path = path + "/UPSTREAM-SHA256.json"
            if (ROOT / upstream_path).is_file():
                upstream = read_json(upstream_path, sources)
                if not isinstance(upstream, dict) or not upstream:
                    raise ValueError("Local upstream source manifest is empty or malformed: " + name)
                for relative, sha in upstream.items():
                    if (not isinstance(relative, str) or not relative or Path(relative).is_absolute()
                            or ".." in Path(relative).parts or Path(relative).as_posix() != relative
                            or "\\" in relative or any(ord(char) < 32 for char in relative)
                            or relative == "." or not isinstance(sha, str)
                            or not re.fullmatch(r"[0-9a-f]{64}", sha)):
                        raise ValueError("Local upstream source manifest path/hash is invalid: " + name)
                current = {key[len(path) + 1:]: value for key, value in sources.items() if key.startswith(path + "/")}
                forks[name].update({"upstream_source_manifest": upstream_path,
                                    "upstream_file_count": len(upstream),
                                    "upstream_missing_files": sorted(set(upstream) - set(current)),
                                    "upstream_changed_files": sorted(key for key in upstream if key in current and upstream[key] != current[key]),
                                    "fork_added_files": sorted(set(current) - set(upstream)),
                                    "upstream_comparison_scope": "Recorded original cached-source hashes; no independent hosted archive authenticity or change approval claim"})
        packages.append(row(
            "dart", name, str(entry.get("version")), entry.get("dependency", "unknown"),
            "pubspec.lock", integrity=integrity,
            license_assertion=license_assertion,
            license_evidence="local_license_text" if name in forks else "unknown",
            origin=origin or (desc.get("path") if isinstance(desc, dict) else src),
            qualifier=src,
        ))
        if name in forks:
            packages[-1].update({"local_tree_sha256": forks[name]["tree_sha256"],
                                "local_tree_file_count": forks[name]["tree_file_count"],
                                "local_provenance": forks[name]["upstream_provenance"]})
    for name, declaration in declared.items():
        if isinstance(declaration, dict) and "path" in declaration and name not in forks:
            raise ValueError("Declared local package is absent from path lock: " + name)
    direct = set(declared)
    missing = sorted(direct - set(lock["packages"]))
    return packages, {
        "pubspec_version": manifest.get("version"),
        "dart_sdk_constraint": manifest.get("environment", {}).get("sdk"),
        "lock_sdk_constraints": lock.get("sdks"),
        "manifest_direct_not_in_lock": missing,
        "local_forks": forks,
        "local_file_saver": forks.get("file_saver"),
    }


def gradle_lock_packages(sources: dict[str, str]) -> tuple[list[dict], dict]:
    """Read only the app's reviewed production classpaths, without artifact claims."""
    path = "android/app/gradle.lockfile"
    if not (ROOT / path).is_file():
        return [], {"present": False, "scope": "No reviewed app dependency lock"}
    content = source(path, sources).read_text(encoding="utf-8")
    allowed = {"productionReleaseRuntimeClasspath", "productionReleaseCompileClasspath"}
    rows, seen, configurations = [], set(), set()
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        coordinate, separator, config_text = line.partition("=")
        if not separator:
            raise ValueError("Malformed app Gradle lock line")
        configs = set(config_text.split(",")) if config_text else set()
        if not configs <= allowed or (coordinate != "empty" and not configs):
            raise ValueError("Gradle lock includes an unreviewed configuration")
        configurations.update(configs)
        if coordinate == "empty":
            continue
        pieces = coordinate.split(":")
        if len(pieces) != 3 or not all(pieces) or coordinate in seen:
            raise ValueError("Malformed or duplicate Gradle lock coordinate")
        group, name, version = pieces
        if "+" in version or "SNAPSHOT" in version or any(x in version for x in "[],()"):
            raise ValueError("Changing or dynamic Gradle dependency lock version")
        seen.add(coordinate)
        rows.append(row("maven", group + ":" + name, version,
                        "reviewed app production dependency lock", path,
                        qualifier=",".join(sorted(configs))))
    if configurations != allowed:
        raise ValueError("App Gradle lock must cover both production classpaths")
    return rows, {"present": True, "entry_count": len(rows),
                  "configurations": sorted(configurations),
                  "scope": "Selected app module versions; artifact hashes and dependency edges are separate observed evidence"}


def gradle_packages(sources: dict[str, str]) -> tuple[list[dict], dict]:
    files = [
        "android/settings.gradle.kts", "android/build.gradle.kts",
        "android/app/build.gradle.kts", "android/gradle/wrapper/gradle-wrapper.properties",
        "third_party/file_saver/android/build.gradle",
        "third_party/file_saver/android/settings.gradle",
        "third_party/file_saver/android/gradle/wrapper/gradle-wrapper.properties",
    ]
    content = {path: source(path, sources).read_text(encoding="utf-8") for path in files}
    wrapper_jar = "android/gradle/wrapper/gradle-wrapper.jar"
    source(wrapper_jar, sources)
    packages = []
    settings = "android/settings.gradle.kts"
    for plugin, version in re.findall(r'id\("([^" ]+)"\)\s+version\s+"([^"]+)"', content[settings]):
        packages.append(row("gradle-plugin", plugin, version, "direct plugin declaration", settings))
    app = "android/app/build.gradle.kts"
    for scope, coordinate in re.findall(
        r'^\s*(implementation|testImplementation|coreLibraryDesugaring)\("([^"]+)"\)',
        content[app], re.MULTILINE,
    ):
        group, name, version = coordinate.split(":", 2)
        packages.append(row("maven", f"{group}:{name}", version, "direct " + scope, app))
    fork = "third_party/file_saver/android/build.gradle"
    body = content[fork]
    vars_ = dict(re.findall(r'^\s*ext\.(\w+)\s*=\s*[\'"]([^\'"]+)[\'"]', body, re.MULTILINE))
    for scope, quote, coordinate in re.findall(
        r'^\s*(classpath|implementation)\s*([\'"])([^\'"]+)\2', body, re.MULTILINE,
    ):
        for name, version in vars_.items():
            coordinate = coordinate.replace("${" + name + "}", version).replace("$" + name, version)
        if coordinate.count(":") != 2:
            raise ValueError(f"Unresolved Gradle coordinate: {coordinate}")
        group, name, version = coordinate.split(":", 2)
        packages.append(row("maven", f"{group}:{name}", version,
                            "local fork direct " + scope, fork))
    wrapper_versions = {}
    for path in ("android/gradle/wrapper/gradle-wrapper.properties",
                 "third_party/file_saver/android/gradle/wrapper/gradle-wrapper.properties"):
        match = re.search(r'gradle-([\d.]+)-(?:all|bin)\.zip', content[path])
        wrapper_versions[path] = match.group(1) if match else None
    locked, lock_check = gradle_lock_packages(sources)
    packages.extend(locked)
    return packages, {
        "wrapper_versions": wrapper_versions,
        "wrapper_jar_sha256": sources[wrapper_jar],
        "wrapper_distribution_sha256_pinned": {
            path: "distributionSha256Sum=" in content[path]
            for path in wrapper_versions
        },
        "resolved_dependency_lock": lock_check,
        "resolved_graph_status": "App module versions locked; observed graph edges/artifact hashes are retained in the native build packet" if lock_check["present"] else "No reviewed app dependency lockfile found",
    }


def ios_packages(sources: dict[str, str]) -> tuple[list[dict], dict]:
    source("ios/Podfile", sources)
    pod = read_yaml("ios/Podfile.lock", sources)
    packages = []
    for entry in pod.get("PODS", []):
        value = entry if isinstance(entry, str) else next(iter(entry))
        match = re.match(r'([^ (]+) \(([^)]+)\)', value)
        if match:
            packages.append(row("cocoapods", match.group(1), match.group(2),
                                "resolved lock entry", "ios/Podfile.lock"))
    paths = [
        "ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        "ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
    ]
    resolved = [read_json(path, sources) for path in paths]
    for pin in sorted(resolved[0].get("pins", []), key=lambda entry: entry["identity"]):
        state = pin.get("state", {})
        packages.append(row(
            "swiftpm", pin["identity"], state.get("version"),
            "resolved pin; direct/transitive unknown", paths[0],
            integrity=state.get("revision"), origin=pin.get("location"),
            qualifier=pin.get("kind"),
        ))
    return packages, {
        "podfile_lock_cocoapods": pod.get("COCOAPODS"),
        "pod_lock_package_count": len(pod.get("PODS", [])),
        "swiftpm_resolved_files_identical": resolved[0] == resolved[1],
        "swiftpm_pin_count": len(resolved[0].get("pins", [])),
        "native_plugin_resolution_status": "not verified against a fresh iOS build",
    }


def node_packages(sources: dict[str, str]) -> tuple[list[dict], dict]:
    packages, projects = [], {}
    for directory in ("tools/public-photography", "deploy/admin-api", "deploy/platform-api"):
        manifest = read_json(directory + "/package.json", sources)
        lock_path = directory + "/package-lock.json"
        lock = read_json(lock_path, sources)
        direct = set(manifest.get("dependencies", {})) | set(manifest.get("devDependencies", {}))
        observed = set()
        for path, entry in sorted(lock["packages"].items()):
            if not path:
                continue
            name = path.rsplit("node_modules/", 1)[-1]
            observed.add(name)
            assertion = entry.get("license")
            packages.append(row("npm", name, entry.get("version"),
                "direct" if name in direct else "transitive or optional", lock_path,
                integrity=entry.get("integrity"), license_assertion=assertion,
                license_evidence="lock_metadata_only" if assertion else "unknown",
                origin=entry.get("resolved"), qualifier="optional" if entry.get("optional") else None))
        projects[directory] = {"lockfile_version": lock.get("lockfileVersion"),
                               "direct_not_in_lock": sorted(direct - observed)}
    return packages, projects


LOCK_VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?")
LOCK_NAME = re.compile(r"(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*")


def lock_name_version(key: str) -> tuple[str, str]:
    if not isinstance(key, str) or '@' not in key:
        raise ValueError("Exact locked package identity required")
    name, version = key.rsplit('@', 1)
    if not LOCK_NAME.fullmatch(name) or not LOCK_VERSION.fullmatch(version):
        raise ValueError("Exact locked package identity required")
    return name, version


def deno_lock_packages(sources: dict[str, str]) -> tuple[list[dict], dict]:
    path = 'supabase/functions/deno.lock'
    lock = locked_json(path, sources)
    if lock.get('version') != '5' or not all(isinstance(lock.get(k), dict) for k in ('specifiers', 'npm', 'jsr')):
        raise ValueError('Unsupported Deno lock format')
    packages = []
    for ecosystem in ('npm', 'jsr'):
        for key, entry in sorted(lock[ecosystem].items()):
            name, version = lock_name_version(key)
            if not isinstance(entry, dict):
                raise ValueError('Deno locked package object required')
            integrity = entry.get('integrity')
            deps = entry.get('dependencies', [])
            if not isinstance(deps, list) or any(not isinstance(dep, str) or not dep for dep in deps):
                raise ValueError('Invalid Deno lock dependency tokens')
            if ecosystem == 'npm':
                integrity = require_sri(integrity)
            elif not isinstance(integrity, str) or not re.fullmatch(r'[a-f0-9]{64}', integrity):
                raise ValueError('Invalid JSR lock integrity token')
            item = row(ecosystem, name, version, 'Deno lock entry; runtime/test reachability unverified', path,
                       integrity=integrity if ecosystem == 'npm' else None, qualifier='Deno v5 lock declaration')
            item['lock_metadata_dependencies'] = deps
            if ecosystem == 'jsr':
                # A JSR lock token is preserved as metadata, not asserted to be
                # the hash of an installed package archive or image.
                item['lock_metadata_integrity'] = integrity
            packages.append(item)
    for specifier, version in lock['specifiers'].items():
        if not isinstance(specifier, str) or not isinstance(version, str) or not LOCK_VERSION.fullmatch(version):
            raise ValueError('Invalid Deno lock specifier')
        match = re.fullmatch(r'(npm|jsr):(.+)@([^@]+)', specifier)
        if not match or not LOCK_NAME.fullmatch(match[2]) or match[2] + '@' + version not in lock[match[1]]:
            raise ValueError('Deno lock specifier does not resolve to a locked entry')
        selector = match[3]
        requested = selector[1:] if selector[:1] in ('^', '~') else selector
        if not LOCK_VERSION.fullmatch(requested) or (selector == requested and requested != version):
            raise ValueError('Invalid or mismatched Deno lock specifier')
    return packages, {'lock_version': '5', 'npm_entries': len(lock['npm']), 'jsr_entries': len(lock['jsr']),
                      'specifier_count': len(lock['specifiers']), 'range_satisfaction': 'not evaluated',
                      'installed_or_runtime_reachability': 'not verified'}


def supabase_tool_packages(sources: dict[str, str]) -> tuple[list[dict], dict]:
    directory = 'scripts/supabase'
    manifest_path, lock_path = directory + '/package.json', directory + '/package-lock.json'
    manifest, lock = locked_json(manifest_path, sources), locked_json(lock_path, sources)
    entries = lock.get('packages')
    if lock.get('lockfileVersion') != 3 or not isinstance(entries, dict) or not isinstance(entries.get(''), dict):
        raise ValueError('Unsupported npm tooling lock format')
    name, version = manifest.get('name'), manifest.get('version')
    if not isinstance(name, str) or not LOCK_NAME.fullmatch(name) or not isinstance(version, str) or not LOCK_VERSION.fullmatch(version) or any(record.get('name') != name or record.get('version') != version for record in (lock, entries[''])):
        raise ValueError('Tooling project identity mismatch')
    declarations = {}
    for field in ('dependencies', 'devDependencies'):
        declared, locked = manifest.get(field, {}), entries[''].get(field, {})
        if not isinstance(declared, dict) or declared != locked:
            raise ValueError('Tooling manifest/lock declarations differ')
        for name, version in declared.items():
            if not isinstance(name, str) or not LOCK_NAME.fullmatch(name) or not isinstance(version, str) or not LOCK_VERSION.fullmatch(version) or name in declarations:
                raise ValueError('Exact tooling declaration required')
            declarations[name] = (field, version)
    packages = []
    path_pattern = re.compile(r'(?:node_modules/(?:@[^/]+/)?[^/]+/)*node_modules/(?:@[^/]+/)?[^/]+')
    for path, entry in sorted(entries.items()):
        if path == '':
            continue
        if not isinstance(path, str) or not path_pattern.fullmatch(path) or not isinstance(entry, dict) or entry.get('link'):
            raise ValueError('Unsupported tooling lock path')
        name = path.rsplit('node_modules/', 1)[-1]
        version = entry.get('version')
        if not LOCK_NAME.fullmatch(name) or not isinstance(version, str) or not LOCK_VERSION.fullmatch(version):
            raise ValueError('Exact tooling lock version required')
        integrity = require_sri(entry.get('integrity'))
        url = entry.get('resolved')
        parsed = urlsplit(url) if isinstance(url, str) else None
        if not parsed or parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
            raise ValueError('Resolved HTTPS tooling package required')
        for flag in ('dev', 'optional', 'peer'):
            if flag in entry and type(entry[flag]) is not bool:
                raise ValueError('Invalid tooling lock flag')
        platforms = {}
        for field in ('os', 'cpu', 'libc'):
            if field in entry:
                if not isinstance(entry[field], list) or any(not isinstance(value, str) or not value for value in entry[field]):
                    raise ValueError('Invalid tooling platform metadata')
                platforms[field] = entry[field]
        direct = path == 'node_modules/' + name and name in declarations
        if direct and (version != declarations[name][1] or (declarations[name][0] == 'devDependencies') != entry.get('dev', False)):
            raise ValueError('Tooling direct lock version or scope mismatch')
        item = row('npm', name, version, 'tooling direct ' + declarations[name][0] if direct else 'tooling transitive or optional',
                   lock_path, integrity=integrity, license_assertion=entry.get('license'),
                   license_evidence='lock_metadata_only' if entry.get('license') else 'unknown', origin=url,
                   qualifier='Supabase operator/test tooling; installed membership unverified')
        item.update(lock_path=path, development=entry.get('dev', False), optional=entry.get('optional', False),
                    peer=entry.get('peer', False), platform_metadata=platforms)
        packages.append(item)
    for name, (_, version) in declarations.items():
        if entries.get('node_modules/' + name, {}).get('version') != version:
            raise ValueError('Tooling direct dependency absent from lock')
    return packages, {'lockfile_version': 3, 'locked_entries': len(packages), 'direct_declarations': len(declarations),
                      'installed_or_artifact_membership': 'not verified'}


def selfhost_image_packages(sources: dict[str, str]) -> tuple[list[dict], dict]:
    path = 'deploy/self-hosted/images.lock.json'
    lock = locked_json(path, sources)
    services = lock.get('services')
    if lock.get('format') != 'collect.selfhost.images.v1' or not isinstance(services, dict) or not services:
        raise ValueError('Unsupported self-host image lock')
    packages, count = [], 0
    for service, entry in sorted(services.items()):
        if not isinstance(service, str) or not re.fullmatch(r'[a-z0-9][a-z0-9_-]*', service) or not isinstance(entry, dict):
            raise ValueError('Invalid image service')
        tag, reference, manifest, platforms = (entry.get(key) for key in ('tag', 'reference', 'manifest_digest', 'platforms'))
        if not isinstance(tag, str) or not re.fullmatch(r'[^\s@]+', tag) or not isinstance(manifest, str) or not re.fullmatch(r'sha256:[a-f0-9]{64}', manifest) or reference != tag + '@' + manifest:
            raise ValueError('Image tag/reference/manifest mismatch')
        if not isinstance(platforms, list) or not platforms:
            raise ValueError('Declared image platform descriptors required')
        seen = set()
        for descriptor in platforms:
            if not isinstance(descriptor, dict) or not set(descriptor).issubset({'os', 'architecture', 'digest', 'variant', 'os.version'}) or not all(isinstance(descriptor.get(k), str) and descriptor[k] for k in ('os', 'architecture', 'digest')) or not re.fullmatch(r'sha256:[a-f0-9]{64}', descriptor['digest']):
                raise ValueError('Invalid image platform descriptor')
            if any(not isinstance(value, str) or not value for value in descriptor.values()):
                raise ValueError('Invalid image platform descriptor')
            key = json.dumps(descriptor, sort_keys=True, separators=(',', ':'))
            if key in seen:
                raise ValueError('Duplicate image platform descriptor')
            seen.add(key)
        item = row('oci', tag, None, 'self-host image manifest declaration', path, origin=reference,
                   qualifier='Service ' + service + '; image contents and platform selection unverified')
        item.update(image_service=service, declared_manifest_digest=manifest, declared_platforms=platforms)
        packages.append(item);count += len(platforms)
    return packages, {'services': len(packages), 'platform_descriptors': count,
                      'pulled_or_deployed_image_contents': 'not verified'}


def ruby_packages(sources: dict[str, str]) -> tuple[list[dict], dict]:
    gemfile = source("Gemfile", sources).read_text(encoding="utf-8")
    lock = source("Gemfile.lock", sources).read_text(encoding="utf-8")
    direct = set(re.findall(r'^gem\s+[\'"]([^\'"]+)', gemfile, re.MULTILINE))
    packages = [
        row("rubygems", name, version, "direct" if name in direct else "transitive",
            "Gemfile.lock")
        for name, version in re.findall(r'^    ([A-Za-z0-9_.-]+) \(([^)]+)\)$', lock, re.MULTILINE)
    ]
    return packages, {"direct_not_in_lock": sorted(direct - {p["name"] for p in packages})}


def decoder_packages(sources: dict[str, str]) -> tuple[list[dict], dict]:
    """Inventory the explicitly architecture-scoped decoder lock and OCI pin.

    Hash pins are declaration evidence, not registry, installed-wheel or image
    attestation. Other architectures need their own independently resolved lock.
    """
    lock_path = "tools/roster-decoder/requirements.lock"
    direct_path = "tools/roster-decoder/requirements.in"
    docker_path = "tools/roster-decoder/Dockerfile"
    lock = source(lock_path, sources).read_text(encoding="utf-8")
    direct = source(direct_path, sources).read_text(encoding="utf-8")
    docker = source(docker_path, sources).read_text(encoding="utf-8")
    for path in ["tools/roster-decoder/decoder.py", "tools/roster-decoder/server.py"]:
        source(path, sources)
    normalize = lambda name: re.sub(r"[-_.]+", "-", name).lower()
    declared = {}
    for line in direct.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)==([^\s]+)", line.strip())
        if not match:
            raise ValueError("Unpinned decoder requirement declaration")
        declared[normalize(match[1])] = match[2]
    packages, locked = [], {}
    for line in lock.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)==([^\s]+) --hash=sha256:([0-9a-f]{64})", line.strip())
        if not match:
            raise ValueError("Unpinned or unhashed decoder requirement lock")
        name = normalize(match[1])
        if name in locked:
            raise ValueError("Duplicate decoder lock package: " + name)
        locked[name] = match[2]
        packages.append(row("pypi", name, match[2], "decoder hash-pinned lock entry",
                            lock_path, integrity=match[3], qualifier="Linux aarch64 / Python3.12 wheel lock"))
    mismatch = sorted(name for name in set(declared) | set(locked) if declared.get(name) != locked.get(name))
    base = re.search(r"(?m)^FROM\s+([^\s@]+)@sha256:([0-9a-f]{64})\s*$", docker)
    if not base:
        raise ValueError("Digest-pinned decoder OCI base required")
    image = base[1]
    packages.append(row("oci", image, None, "digest-pinned decoder base image declaration",
                        docker_path, integrity=base[2], origin=image,
                        qualifier="Registry digest declaration; platform image contents not verified by inventory"))
    return packages, {"architecture_scope": "Linux aarch64 / Python3.12",
                      "requirements_declaration_lock_mismatches": mismatch,
                      "hash_pinned_wheel_count": len(locked), "base_image_digest_pinned": True,
                      "installed_wheel_and_image_contents": "not verified by source inventory"}


def assets(sources: dict[str, str], pubspec: dict) -> tuple[list[dict], dict]:
    source("assets/typefaces/OFL-Inter.txt", sources)
    marketing = read_json("assets/marketing/SOURCE.json", sources)
    catalog = read_json("assets/group_covers/rwanda/catalog.v1.json", sources)
    runtime = read_json("assets/group_covers/rwanda/runtime-manifest.json", sources)
    paths = set()
    for declaration in pubspec["flutter"].get("assets", []):
        target = ROOT / declaration
        if declaration.endswith("/"):
            paths.update(file for file in target.rglob("*") if file.is_file())
        else:
            paths.add(target)
    for family in pubspec["flutter"].get("fonts", []):
        paths.update(ROOT / font["asset"] for font in family.get("fonts", []))
    paths.update(ROOT / path for path in pubspec["flutter"].get("licenses", []))
    marketing_sources = {entry["path"]: entry for entry in marketing.get("files", [])}
    catalog_paths = {
        path for asset in catalog.get("assets", [])
        for role, path in asset.get("planned_files", {}).items() if role in {"cover", "thumbnail"}
    }
    rows = []
    missing = []
    mismatches = []
    for path in sorted(paths):
        name = rel(path)
        if not path.is_file():
            missing.append(name)
            continue
        license_assertion = "OFL-1.1" if name in {
            "assets/typefaces/Inter-Variable.ttf", "assets/typefaces/OFL-Inter.txt"
        } else None
        evidence = "assets/typefaces/OFL-Inter.txt" if license_assertion else "unknown"
        if name in marketing_sources and not license_assertion:
            evidence = "provenance_only; no redistribution grant recorded"
        if name in catalog_paths:
            evidence = "generated image provenance; license review pending"
        known_sha = marketing_sources.get(name, {}).get("sha256")
        actual = digest(path)
        if known_sha and actual != known_sha:
            mismatches.append(name)
        rows.append({
            "path": name, "bytes": path.stat().st_size, "sha256": actual,
            "declared_in": "pubspec.yaml", "license_assertion": license_assertion,
            "license_evidence": evidence,
            "cataloged_group_derivative": name in catalog_paths,
        })
    derivative_failures = []
    derivative_count = 0
    source_failures = []
    source_count = 0
    for record in runtime.get("records", []):
        source_path = ROOT / record["source"]
        source_count += 1
        if not source_path.is_file() or digest(source_path) != record.get("source_sha256"):
            source_failures.append(record["source"])
        for entry in record.get("derivatives", []):
            derivative_count += 1
            path = ROOT / entry["path"]
            if not path.is_file() or digest(path) != entry.get("sha256") or path.stat().st_size != entry.get("bytes"):
                derivative_failures.append(entry["path"])
    return rows, {
        "declared_asset_path_count": len(rows),
        "declared_asset_missing": missing,
        "marketing_source_sha256_mismatches": mismatches,
        "group_catalog_concepts": len(catalog.get("assets", [])),
        "group_source_images_checked": source_count,
        "group_source_image_mismatches": source_failures,
        "group_runtime_derivatives_checked": derivative_count,
        "group_runtime_derivative_mismatches": derivative_failures,
        "group_catalog_paths_missing_from_declared_assets": sorted(catalog_paths - {r["path"] for r in rows}),
        "aeonik_license_evidence_files_in_typefaces": sorted(
            rel(path) for path in (ROOT / "assets/typefaces").glob("*Aeonik*LICEN*") if path.is_file()
        ),
    }


def build() -> dict:
    sources: dict[str, str] = {}
    source(rel(Path(__file__).resolve()), sources)
    package_rows = []
    checks = {}
    for label, collector in (
        ("dart", dart_packages), ("gradle", gradle_packages),
        ("ios", ios_packages),
        ("node", node_packages), ("ruby", ruby_packages), ("decoder", decoder_packages),
        ("supabase_deno", deno_lock_packages), ("supabase_tooling", supabase_tool_packages),
        ("selfhost_images", selfhost_image_packages),
    ):
        rows, check = collector(sources)
        package_rows.extend(rows)
        checks[label] = check
    pubspec = yaml.safe_load((ROOT / "pubspec.yaml").read_text(encoding="utf-8"))
    asset_rows, asset_checks = assets(sources, pubspec)
    checks["assets"] = asset_checks
    package_rows.sort(key=lambda p: (p["ecosystem"], p["name"], p["version"] or "", p["evidence"]))
    counts = Counter(p["ecosystem"] for p in package_rows)
    return {
        "schema_version": 1,
        "kind": "source-level candidate dependency and declared-asset inventory",
        "coverage": {
            "included": [
                "pubspec.lock and declared local Dart forks, regular-source tree hashes, license texts and provenance", "Gradle declarations and wrapper versions",
                "Podfile.lock", "two Swift Package.resolved files",
                "Cloudflare service and public-photography npm locks", "Gemfile.lock", "pubspec declared asset paths and fonts",
                "Supabase Deno npm/JSR lock declarations and Supabase operator/test tooling npm lock",
                "self-host service image manifest and platform descriptor declarations",
                "Rwanda group runtime derivative hash checks",
                "Linux aarch64/Python3.12 roster decoder wheel hashes and OCI base digest declarations",
                "Reviewed app production compile/runtime Gradle dependency lock entries when present",
            ],
            "excluded": [
                "Android observed dependency graph edges and AAR/JAR bytes (separate native inventory packet)",
                "installed SDK/cache contents", "native artifact contents and signed AAB/IPA SBOM",
                "registry advisory/current maintenance queries", "full asset reachability and legal license approval",
                "decoder image platform attestation and installed wheel contents",
                "Supabase Deno range satisfaction and runtime/test reachability, installed tooling membership and pulled/deployed image contents or platform attestation",
            ],
        },
        "source_sha256": dict(sorted(sources.items())),
        "packages": package_rows,
        "assets": asset_rows,
        "checks": checks,
        "summary": {
            "packages_total": len(package_rows),
            "packages_by_ecosystem": dict(sorted(counts.items())),
            "packages_without_license_evidence": sum(p["license_evidence"] == "unknown" for p in package_rows),
            "asset_paths_total": len(asset_rows),
            "assets_without_license_assertion": sum(a["license_assertion"] is None for a in asset_rows),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="Compare output with the saved JSON without writing")
    args = parser.parse_args()
    output = args.output.resolve()
    document = json.dumps(build(), indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    if args.check:
        if not output.is_file() or output.read_text(encoding="utf-8") != document:
            print(f"candidate inventory stale or missing: {output}")
            return 1
        print(f"candidate inventory reproducible: {output}")
        return 0
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(document, encoding="utf-8")
    print(f"wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
