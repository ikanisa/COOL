#!/usr/bin/env python3
"""Export a deterministic CycloneDX 1.6 source/lock SBOM from verified inventory.

It cannot assert signed-artifact contents, a complete native resolved graph,
current vulnerability clearance or license approval. Unknowns remain explicit.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prop(name: str, value) -> dict:
    return {"name": "collect:" + name, "value": value if isinstance(value, str) else json.dumps(value, sort_keys=True, separators=(",", ":"))}


def component_hash(value: str | None) -> list[dict]:
    if not value:
        return []
    if re.fullmatch(r"[0-9a-f]{64}", value):
        return [{"alg": "SHA-256", "content": value}]
    match = re.fullmatch(r"sha(256|384|512)-([A-Za-z0-9+/=]+)", value)
    if match:
        raw = base64.b64decode(match[2], validate=True)
        if len(raw) * 8 != int(match[1]):
            raise ValueError("Invalid lock hash length")
        return [{"alg": "SHA-" + match[1], "content": raw.hex()}]
    # Git revisions and nonstandard integrity strings are provenance properties,
    # never mislabeled as cryptographic package digests.
    return []


def build(inventory_path: Path) -> dict:
    inventory = json.loads(inventory_path.read_text())
    for relative, expected in inventory["source_sha256"].items():
        path = (ROOT / relative).resolve()
        if not path.is_relative_to(ROOT) or digest(path) != expected:
            raise ValueError("Inventory source drift: " + relative)
    # Hashing previously listed files alone cannot detect a new fork source.
    # Recheck the complete recorded local source set, preserving the same
    # generated/cache exclusions as the candidate inventory collector.
    for fork in inventory.get("checks", {}).get("dart", {}).get("local_forks", {}).values():
        relative = fork["path"]
        if (not isinstance(relative, str) or Path(relative).is_absolute() or ".." in Path(relative).parts
                or Path(relative).as_posix() != relative or relative == "." or "\\" in relative
                or any(ord(char) < 32 for char in relative)):
            raise ValueError("Inventory local fork drift: " + str(relative))
        directory = ROOT / relative
        if (not directory.is_dir() or directory.is_symlink() or not directory.resolve().is_relative_to(ROOT)
                or any(parent.is_symlink() for parent in (directory, *directory.parents) if parent.is_relative_to(ROOT))):
            raise ValueError("Inventory local fork drift: " + relative)
        excluded = {".git", ".gradle", ".dart_tool", "build", "__pycache__"}
        paths = [path for path in directory.rglob("*")
                 if not any(part in excluded for part in path.relative_to(directory).parts)]
        if any(path.is_symlink() or not path.resolve().is_relative_to(directory.resolve()) for path in paths):
            raise ValueError("Inventory local fork drift: " + relative)
        files = sorted(path for path in paths if path.is_file())
        manifest = "".join(f"{path.relative_to(ROOT).as_posix()} {digest(path)}\n" for path in files)
        if len(files) != fork["tree_file_count"] or hashlib.sha256(manifest.encode("utf-8")).hexdigest() != fork["tree_sha256"]:
            raise ValueError("Inventory local fork drift: " + relative)
    for asset in inventory["assets"]:
        path = (ROOT / asset["path"]).resolve()
        if not path.is_relative_to(ROOT) or digest(path) != asset["sha256"]:
            raise ValueError("Inventory asset drift: " + asset["path"])
    grouped = {}
    for package in inventory["packages"]:
        identity = json.dumps({k: package.get(k) for k in ["ecosystem", "name", "version", "integrity", "origin", "qualifier"]}, sort_keys=True)
        grouped.setdefault(identity, []).append(package)
    components = []
    for identity, rows in sorted(grouped.items()):
        row = rows[0]
        component = {"type": "container" if row["ecosystem"] == "oci" else "library", "bom-ref": "package:" + hashlib.sha256(identity.encode()).hexdigest(),
                     "name": row["name"], "group": row["ecosystem"],
                     "properties": [prop("evidence", sorted({r["evidence"] for r in rows})),
                                    prop("relationship", sorted({r["relationship"] for r in rows})),
                                    prop("license_evidence", sorted({r["license_evidence"] for r in rows})),
                                    prop("license_approval", False)]}
        for key in ["origin", "qualifier", "license_assertion"]:
            values = sorted({r[key] for r in rows if r.get(key)})
            if values:
                component["properties"].append(prop(key, values))
        for key in ["local_tree_sha256", "local_tree_file_count", "local_provenance"]:
            if row.get(key) is not None:
                component["properties"].append(prop(key, row[key]))
        if row.get("version"):
            component["version"] = row["version"]
        if row.get("integrity"):
            component["properties"].append(prop("lock_integrity", row["integrity"]))
        hashes = component_hash(row.get("integrity"))
        if hashes:
            component["hashes"] = hashes
        components.append(component)
    for asset in sorted(inventory["assets"], key=lambda row: row["path"]):
        components.append({"type": "file", "bom-ref": "asset:" + asset["path"], "name": asset["path"],
                           "hashes": [{"alg": "SHA-256", "content": asset["sha256"]}],
                           "properties": [prop("declaration", asset["declared_in"]),
                                          prop("bytes", asset["bytes"]), prop("license_evidence", asset["license_evidence"])]})
    return {"$schema": "https://cyclonedx.org/schema/bom-1.6.schema.json", "bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
            "metadata": {"component": {"type": "application", "bom-ref": "application:collect-source", "name": "Collect",
                                       "version": inventory["checks"]["dart"]["pubspec_version"]},
                         "properties": [prop("scope", "Source declarations and local lock inventory; signed-artifact SBOM not verified."),
                                        prop("inventory_sha256", digest(inventory_path)),
                                        prop("generator_sha256", digest(Path(__file__))),
                                        prop("source_sha256", inventory["source_sha256"]),
                                        prop("coverage_included", inventory["coverage"]["included"]),
                                        prop("coverage_excluded", inventory["coverage"]["excluded"]),
                                        prop("vulnerability_clearance", "not evaluated"),
                                        prop("license_approval", False)]},
            "components": components}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    document = json.dumps(build(args.inventory), sort_keys=True, indent=2, ensure_ascii=False) + "\n"
    if args.check:
        if not args.output.is_file() or args.output.read_text() != document:
            print("Source SBOM differs from verified inputs.")
            return 1
        print("Source SBOM reproduces verified inventory.")
    else:
        if args.output.exists():
            raise FileExistsError("Use a fresh output; preserve earlier evidence.")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(document)
        print("Wrote CycloneDX source SBOM.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
