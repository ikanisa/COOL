#!/usr/bin/env python3
"""Conservative source reachability; never deletes files or approves a release.

Every quoted URI in multiline/conditional Dart import/export/part directives is
retained, including comments (false positives preserve rather than delete code).
Runtime entrypoints, test/tool roots, catalog-generated paths and implicit SDK
font use are separate. A result with unknown dynamic asset references requires
review; absence of a literal alone never authorizes deletion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
DIRECTIVE = re.compile(r"(?ms)^\s*(?:import|export|part)\s+(?!of\b)(.*?);")
URI = re.compile(r"['\"]([^'\"\n]+)['\"]")
RUNTIME_ROOTS = ["lib/main.dart", "lib/main_admin.dart", "lib/main_public.dart",
                 "lib/main_gateway.dart"]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect(root: Path) -> dict:
    root = root.resolve()
    sources = {p.relative_to(root).as_posix(): p for scope in ["lib", "test", "integration_test", "tool"]
               for p in (root / scope).rglob("*.dart") if p.is_file()}
    graph, packages, missing = {}, {}, []
    texts = {name: path.read_text(encoding="utf-8") for name, path in sources.items()}
    for name, path in sources.items():
        graph[name] = set()
        for directive in DIRECTIVE.finditer(texts[name]):
            for uri in URI.findall(directive.group(1)):
                if uri.startswith("dart:"):
                    continue
                if uri.startswith("package:") and not uri.startswith("package:collect_app/"):
                    packages.setdefault(uri[8:].split("/")[0], set()).add(name)
                    continue
                target = root / "lib" / uri[len("package:collect_app/"):] if uri.startswith("package:collect_app/") else path.parent / uri
                try:
                    relative = target.resolve().relative_to(root).as_posix()
                except ValueError:
                    missing.append({"source": name, "uri": uri, "reason": "outside_checkout"})
                    continue
                if relative in sources:
                    graph[name].add(relative)
                else:
                    missing.append({"source": name, "uri": uri, "reason": "missing_local_source"})
    def reachable(roots):
        seen, pending = set(), list(roots)
        while pending:
            name = pending.pop()
            if name in seen:
                continue
            seen.add(name)
            pending.extend(graph.get(name, []))
        return seen
    missing_runtime_roots = [name for name in RUNTIME_ROOTS if name not in sources]
    runtime = reachable(name for name in RUNTIME_ROOTS if name in sources)
    evidence_roots = [name for name in sources if not name.startswith("lib/")]
    evidence = reachable(evidence_roots)
    manifest = yaml.safe_load((root / "pubspec.yaml").read_text())
    bundled = {}
    for entry in manifest["flutter"].get("assets", []):
        value = entry["path"] if isinstance(entry, dict) else entry
        path = root / value
        paths = sorted(p for p in path.rglob("*") if p.is_file()) if path.is_dir() else [path]
        for asset in paths:
            bundled.setdefault(asset.relative_to(root).as_posix(), []).append(value)
    for family in manifest["flutter"].get("fonts", []):
        for font in family["fonts"]:
            bundled.setdefault(font["asset"], []).append("font:" + family["family"])
    for license_path in manifest["flutter"].get("licenses", []):
        bundled.setdefault(license_path, []).append("license")
    catalog_path = "assets/group_covers/rwanda/catalog.v1.json"
    catalog = json.loads((root / catalog_path).read_text())
    catalog_assets = {a["planned_files"][role]: a["id"] for a in catalog["assets"] for role in ["cover", "thumbnail"]}
    assets = []
    for path, declarations in sorted(bundled.items()):
        literal_sources = [name for name in sorted(runtime) if path in texts[name]]
        roles = []
        if literal_sources:
            roles.append("runtime_literal")
        if path in catalog_assets and "lib/shared/models/collect_group_cover.dart" in runtime:
            roles.append("runtime_catalog_allowlist")
        if any(d.startswith("font:") for d in declarations):
            roles.append("shared_font_declaration")
        if "license" in declarations:
            roles.append("font_license_declaration")
        target = root / path
        assets.append({"path": path, "declarations": declarations, "exists": target.is_file(),
                       "sha256": sha(target) if target.is_file() else None,
                       "bytes": target.stat().st_size if target.is_file() else None,
                       "reachability": roles or ["unresolved_requires_review"],
                       "literal_sources": literal_sources,
                       "catalog_id": catalog_assets.get(path)})
    direct = {**manifest.get("dependencies", {}), **manifest.get("dev_dependencies", {})}
    implicit = {"cupertino_icons": "Bundled font consumed by Flutter CupertinoIcons controls in reachable router/UI.",
                "flutter_lints": "analysis_options.yaml includes package:flutter_lints/flutter.yaml."}
    dependencies = [{"name": name,
                     "runtime_importers": sorted(packages.get(name, set()) & runtime),
                     "evidence_importers": sorted(packages.get(name, set()) & evidence),
                     "implicit_use": implicit.get(name),
                     "removal_authorized": False} for name in sorted(direct)]
    runtime_files = {name for name in sources if name.startswith("lib/")}
    hashes = {name: sha(path) for name, path in sorted(sources.items())}
    for name in ["pubspec.yaml", "pubspec.lock", "analysis_options.yaml", catalog_path,
                 "scripts/qa/runtime_reachability.py"]:
        hashes[name] = sha(root / name)
    return {"schema_version": 1, "status": "fail" if missing or missing_runtime_roots or any(not a["exists"] for a in assets) else "audited",
            "scope": "Conservative declared runtime source/asset/dependency reachability; no deletion authorization or dynamic execution proof.",
            "runtime_roots": RUNTIME_ROOTS, "runtime_source_count": len(runtime_files),
            "missing_runtime_roots": missing_runtime_roots,
            "reachable_runtime_source_count": len(runtime & runtime_files),
            "runtime_unreachable": [{"path": name, "evidence_reachable": name in evidence,
                                     "sha256": hashes[name]} for name in sorted(runtime_files - runtime)],
            "missing_local_directives": missing,
            "assets": assets, "unresolved_bundled_assets": [a["path"] for a in assets if "unresolved_requires_review" in a["reachability"]],
            "dependencies": dependencies, "source_sha256": hashes,
            "limitations": ["Native asset catalogs, external URLs and dynamically constructed assets outside the group allowlist need separate inspection.",
                            "Historical source originals and reports are preserved; they are not unused runtime payload.",
                            "Every evidence Dart file is a root conservatively; helper-file reachability is not a claim that every test executed."]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    document = json.dumps(collect(ROOT), indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    if args.check:
        if not args.output.is_file() or args.output.read_text() != document:
            print("Reachability evidence differs from current inputs.")
            return 1
        print("Reachability evidence matches current inputs.")
    else:
        if args.output.exists():
            raise FileExistsError("Use a fresh output; preserve earlier evidence.")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(document)
        print("Wrote conservative reachability evidence.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
