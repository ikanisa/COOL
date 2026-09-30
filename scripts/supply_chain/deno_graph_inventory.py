#!/usr/bin/env python3
"""Export an observed Deno compiler closure; never claims lock-enforced execution.

Checks remote cached bytes against independently generated lock hashes and
retains current local source hashes. Npm integrity is declared lock evidence;
archive contents, advisories, licenses and deployment remain unverified.
"""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import unquote, urlparse

from source_sbom import component_hash, prop

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(graph_path, lock_path):
    graph = json.loads(graph_path.read_text())
    lock = json.loads(lock_path.read_text())
    modules = {row["specifier"]: row for row in graph["modules"]}
    if len(modules) != len(graph["modules"]):
        raise ValueError("Duplicate Deno compiler module")
    redirects = graph.get("redirects", {})

    def resolve(specifier):
        seen = set()
        while specifier in redirects:
            if specifier in seen:
                raise ValueError("Deno redirect cycle")
            seen.add(specifier)
            specifier = redirects[specifier]
        if specifier not in modules:
            raise ValueError("Unresolved Deno compiler edge: " + specifier)
        return specifier

    components, dependencies, source_hashes, remote_count, unlocked_remote_count = [], [], {}, 0, 0
    for specifier, row in sorted(modules.items()):
        if row.get("error"):
            raise ValueError("Deno compiler module error")
        component = {"type": "file" if row["kind"] == "esm" else "library", "bom-ref": specifier,
                     "name": specifier, "properties": [prop("compiler_module_kind", row["kind"]),
                                                         prop("license_approval", False)]}
        if row.get("local"):
            path = Path(row["local"])
            raw = path.read_bytes()
            # Deno2.5.6 appends HTTP cache metadata after the compiler-reported
            # module bytes. Hash the actual module body, retain the full cache
            # container hash separately, and never hash headers as source code.
            body = raw
            if specifier.startswith("https://"):
                size = row.get("size")
                if not isinstance(size, int) or not 0 < size <= len(raw):
                    raise ValueError("Invalid Deno cached module body size")
                body = raw[:size]
                component["properties"].append(prop("cached_container_sha256", sha(path)))
            actual = hashlib.sha256(body).hexdigest()
            component["hashes"] = [{"alg": "SHA-256", "content": actual}]
            if specifier.startswith("https://"):
                expected = lock.get("remote", {}).get(specifier)
                if expected and expected != actual:
                    raise ValueError("Deno remote cached bytes differ from lock: " + specifier)
                if expected:
                    remote_count += 1
                else:
                    unlocked_remote_count += 1
                    component["properties"].append(prop("observed_lock_hash", "not present; compiler-observed cached module only"))
            elif specifier.startswith("file://"):
                original = Path(unquote(urlparse(specifier).path)).resolve()
                if original != path.resolve() or not original.is_relative_to(ROOT):
                    raise ValueError("Deno local compiler source outside checkout")
                source_hashes[original.relative_to(ROOT).as_posix()] = actual
            else:
                raise ValueError("Unsupported local Deno compiler specifier")
        elif row["kind"] not in ["npm", "node"]:
            raise ValueError("Deno module is missing retained bytes")
        edges = {resolve(dep[role]["specifier"]) for dep in row.get("dependencies", [])
                 for role in ["code", "type"] if dep.get(role, {}).get("specifier")}
        if row.get("npmPackage"):
            edges.add("npm-package:" + row["npmPackage"])
        dependencies.append({"ref": specifier, "dependsOn": sorted(edges)})
        components.append(component)
    for identity, row in sorted(graph.get("npmPackages", {}).items()):
        entry = lock.get("npm", {}).get(identity)
        if not entry or not entry.get("integrity"):
            raise ValueError("Deno npm module absent from observed lock: " + identity)
        ref = "npm-package:" + identity
        components.append({"type": "library", "bom-ref": ref, "name": row["name"], "version": row["version"],
                           "hashes": component_hash(entry["integrity"]),
                           "properties": [prop("integrity_scope", "Observed npm lock integrity; archive bytes not independently retained"),
                                          prop("license_approval", False)]})
        dependencies.append({"ref": ref, "dependsOn": ["npm-package:" + name for name in sorted(row.get("dependencies", []))]})
    known_refs = {row["bom-ref"] for row in components}
    if any(edge not in known_refs for row in dependencies for edge in row["dependsOn"]):
        raise ValueError("Deno npm dependency edge is incomplete")
    indices = sorted(path for path in source_hashes if path.startswith("supabase/functions/") and path.endswith("/index.ts"))
    actual_indices = sorted(path.relative_to(ROOT).as_posix() for path in (ROOT / "supabase/functions").rglob("index.ts"))
    if indices != actual_indices:
        raise ValueError("Deno observed graph omits a declared Edge entrypoint")
    report = {"status": "pass", "scope": "Observed static compiler closure for all declared Edge entrypoints plus actual HTTP harness; no lock-enforced execution claim",
              "graph_sha256": sha(graph_path), "lock_sha256": sha(lock_path), "compiler_module_count": len(modules),
              "npm_package_count": len(graph.get("npmPackages", {})), "remote_cache_files_hash_verified": remote_count,
              "additional_cached_modules_without_observed_lock_hash": unlocked_remote_count,
              "source_sha256": source_hashes, "edge_entrypoints": indices, "lock_enforced_execution": False,
              "unknowns": ["Dynamic conditional import paths not present in compiler graph", "Independent npm archive bytes", "Current advisory/license/hosted acceptance"]}
    document = {"$schema": "https://cyclonedx.org/schema/bom-1.6.schema.json", "bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
                "metadata": {"component": {"type": "application", "name": "Collect Edge observed compiler closure"},
                             "properties": [prop("graph_sha256", sha(graph_path)), prop("lock_sha256", sha(lock_path)),
                                            prop("lock_enforced_execution", False), prop("source_sha256", source_hashes),
                                            prop("scope", report["scope"]), prop("unknowns", report["unknowns"])]},
                "components": components, "dependencies": dependencies}
    return report, document


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["graph", "lock", "output", "sbom-output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    report, document = build(args.graph, args.lock)
    for path, data in [(args.output, report), (args.sbom_output, document)]:
        if path.exists():
            raise FileExistsError("Fresh output required; preserve prior evidence")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: report[key] for key in ["status", "compiler_module_count", "npm_package_count", "remote_cache_files_hash_verified"]}))


if __name__ == "__main__":
    main()
