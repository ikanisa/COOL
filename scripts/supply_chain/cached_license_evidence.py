#!/usr/bin/env python3
"""Collect bounded local license witnesses for exact Dart/Maven declarations.

Explicit cache roots only; no downloads, package execution, SPDX inference or
license approval. This companion preserves the source inventory's own scope.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote, urljoin, urlsplit
import xml.etree.ElementTree as ET

import yaml

MAX_TEXT = 1024 * 1024
LICENSE_NAME = re.compile(r"(?:licen[sc]e|copying|notice)(?:[._-][A-Za-z0-9._-]+)?", re.I)
PART = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.+-]*")


class Witnesses:
    def __init__(self):
        self.inputs: dict[str, dict] = {}
        self.memberships: dict[str, list[str]] = {}
        self.resolved: dict[str, tuple[Path, Path]] = {}

    def read(self, path: Path, root: Path) -> str:
        path, root = path.absolute(), root.resolve()
        if (not path.resolve().is_relative_to(root) or not path.is_file()
                or any(p.is_symlink() for p in (path, *path.parents) if p.is_relative_to(root))):
            raise ValueError("Witness is not a regular file inside its explicit root: " + str(path))
        if path.stat().st_size > MAX_TEXT:
            raise ValueError("Witness exceeds the bounded text limit: " + str(path))
        raw = path.read_bytes()
        if len(raw) > MAX_TEXT:
            raise ValueError("Witness grew beyond the bounded text limit")
        value = {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}
        previous = self.inputs.setdefault(str(path), value)
        if previous != value:
            raise ValueError("Witness changed while being read: " + str(path))
        binding = (path.resolve(), root)
        if self.resolved.setdefault(str(path), binding) != binding:
            raise ValueError("Witness path changed while being read")
        return raw.decode("utf-8")

    def members(self, directory: Path, pattern: str) -> list[Path]:
        # A package's immediate license files or one exact Maven version's
        # content-addressed POM children; never a recursive computer search.
        found = sorted(directory.glob(pattern)) if directory.is_dir() else []
        key = str(directory.absolute()) + "|" + pattern
        names = [str(p.absolute()) for p in found]
        if self.memberships.setdefault(key, names) != names:
            raise ValueError("Witness membership changed: " + key)
        return found

    def finish(self):
        for path, expected in self.inputs.items():
            p = Path(path)
            resolved, root = self.resolved[path]
            if (p.resolve() != resolved or not p.resolve().is_relative_to(root)
                    or any(q.is_symlink() for q in (p, *p.parents) if q.is_relative_to(root))
                    or not p.is_file() or p.stat().st_size != expected["bytes"]
                    or hashlib.sha256(p.read_bytes()).hexdigest() != expected["sha256"]):
                raise ValueError("Witness changed after collection: " + path)
        for key, expected in self.memberships.items():
            directory, pattern = key.rsplit("|", 1)
            actual = [str(p.absolute()) for p in sorted(Path(directory).glob(pattern))] if Path(directory).is_dir() else []
            if actual != expected:
                raise ValueError("Witness membership changed after collection: " + key)


def identity(row: dict) -> dict:
    return {k: row.get(k) for k in ("ecosystem", "name", "version", "integrity", "origin", "qualifier", "evidence")}


def dart_witness(row: dict, entries: dict, roots: list[Path], config: Path, read: Witnesses) -> dict:
    entry = entries.get(row["name"])
    if entry is None:
        return {"status": "package_not_resolved"}
    uri = urlsplit(urljoin(config.absolute().as_uri(), entry["rootUri"]))
    if uri.scheme != "file" or uri.netloc or uri.query or uri.fragment:
        return {"status": "package_root_not_local"}
    directory = Path(unquote(uri.path))
    matches = [r for r in roots if directory.resolve().is_relative_to(r.resolve())]
    if not matches:
        return {"status": "package_root_outside_explicit_scope"}
    root = max(matches, key=lambda p: len(p.parts))
    metadata = directory / "pubspec.yaml"
    if not metadata.is_file():
        return {"status": "package_metadata_missing"}
    spec = yaml.safe_load(read.read(metadata, root))
    if not isinstance(spec, dict) or spec.get("name") != row["name"] or str(spec.get("version")) != row.get("version"):
        return {"status": "package_identity_unproved", "metadata": str(metadata.absolute())}
    texts = []
    for path in read.members(directory, "*"):
        if LICENSE_NAME.fullmatch(path.name):
            if not read.read(path, root).strip():
                continue
            texts.append(str(path.absolute()))
    return {"status": "local_license_text" if texts else "license_text_missing",
            "metadata": str(metadata.absolute()), "license_texts": texts,
            "package_archive_integrity_verified": False}


def maven_witness(row: dict, roots: list[Path], read: Witnesses) -> dict:
    split = row["name"].split(":")
    if len(split) != 2 or any(not PART.fullmatch(p) or p in {".", ".."} for p in [*split, row.get("version") or ""]):
        raise ValueError("Invalid exact Maven coordinate")
    group, name = split
    candidates = []
    for root in roots:
        directory = root / group / name / row["version"]
        for path in read.members(directory, "*/*.pom"):
            raw = read.read(path, root)
            if re.search(r"<!\s*(?:DOCTYPE|ENTITY)\b", raw, re.I):
                raise ValueError("External/entity-bearing POM is not accepted: " + str(path))
            document = ET.fromstring(raw)
            ns = {"m": "http://maven.apache.org/POM/4.0.0"} if document.tag.startswith("{") else {}
            prefix = "m:" if ns else ""
            def value(key):
                text = document.findtext(prefix + key, namespaces=ns)
                return text.strip() if text else None
            actual = (value("groupId") or value("parent/" + prefix + "groupId"), value("artifactId"), value("version") or value("parent/" + prefix + "version"))
            if actual != (group, name, row["version"]):
                continue
            licenses = []
            for license_node in document.findall(prefix + "licenses/" + prefix + "license", ns):
                item = {key: (license_node.findtext(prefix + key, namespaces=ns) or "").strip() for key in ["name", "url", "distribution", "comments"]}
                if item["name"] and not any("${" in v for v in item.values()):
                    licenses.append(item)
            candidates.append({"path": str(path.absolute()), "declared_licenses": licenses})
    if not candidates:
        return {"status": "exact_pom_unavailable"}
    variants = {json.dumps(c["declared_licenses"], sort_keys=True) for c in candidates}
    status = "conflicting_pom_license_metadata" if len(variants) > 1 else "pom_license_metadata" if candidates[0]["declared_licenses"] else "pom_license_metadata_missing"
    return {"status": status, "poms": candidates, "artifact_license_contents_verified": False}


def build(inventory: Path, repo: Path, config: Path | None = None,
          dart_roots: list[Path] | None = None, maven_roots: list[Path] | None = None) -> dict:
    read = Witnesses()
    data = json.loads(read.read(inventory, inventory.parent))
    rows = data["packages"]
    if not isinstance(rows, list) or len(rows) > 10000:
        raise ValueError("Invalid inventory package count")
    entries = {}
    if config:
        parsed = json.loads(read.read(config, config.parent))
        for entry in parsed["packages"]:
            if entry["name"] in entries:
                raise ValueError("Duplicate resolved package name")
            entries[entry["name"]] = entry
    for row in rows:
        if row["ecosystem"] not in {"dart", "maven"}:
            continue
        relative = Path(row["evidence"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Inventory declaration escapes repository")
        path = repo / relative
        read.read(path, repo)
        if read.inputs[str(path.absolute())]["sha256"] != data["source_sha256"].get(relative.as_posix()):
            raise ValueError("Inventory declaration changed: " + str(relative))
    results = []
    for row in rows:
        if row["ecosystem"] == "dart" and config:
            witness = dart_witness(row, entries, dart_roots or [], config, read)
        elif row["ecosystem"] == "maven":
            witness = maven_witness(row, maven_roots or [], read)
        else:
            witness = {"status": "ecosystem_not_collected"}
        results.append({"identity": identity(row), **witness, "license_approval": False})
    read.finish()
    counts = Counter(r["status"] for r in results)
    return {"schema_version": 1, "kind": "local_cached_license_witness_companion",
            "scope": "Exact declared Dart package local text and Maven POM declarations; source inventory is unchanged.",
            "excluded": ["downloads", "package execution", "inherited POM license resolution", "SPDX inference", "installed/shipping artifact membership", "license approval", "vulnerability clearance", "asset-rights approval"],
            "license_approval": False, "input_bindings": dict(sorted(read.inputs.items())),
            "membership_bindings": dict(sorted(read.memberships.items())),
            "explicit_roots": {"dart": sorted(str(p.resolve()) for p in dart_roots or []), "maven": sorted(str(p.resolve()) for p in maven_roots or [])},
            "summary": {"package_declarations": len(results), "statuses": dict(sorted(counts.items()))},
            "packages": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--dart-config", type=Path)
    parser.add_argument("--dart-root", type=Path, action="append", default=[])
    parser.add_argument("--maven-root", type=Path, action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = build(args.inventory.absolute(), args.repo.resolve(), args.dart_config, args.dart_root, args.maven_root)
    body = json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    if args.check:
        if not args.output.is_file() or args.output.read_text() != body:
            raise ValueError("Cached license witnesses do not reproduce")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8") as stream:
            stream.write(body)
    print(json.dumps(result["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
