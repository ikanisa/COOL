#!/usr/bin/env python3
"""CycloneDX inventory of observed locked Android graphs and external artifact bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]


def identity(record):
    if record.get("kind") == "module":
        return "pkg:maven/" + quote(record["group"], safe=".") + "/" + quote(record["name"], safe="") + "@" + quote(record["version"], safe="")
    if record.get("kind") == "project":
        return "collect:local-gradle-project:" + quote(record["path"], safe="")
    raise ValueError("Unknown observed Gradle component identity")


def build(graphs, evidence):
    if {g.get("configuration") for g in graphs} != {"productionReleaseRuntimeClasspath", "productionReleaseCompileClasspath"}:
        raise ValueError("Both exact production graphs are required")
    components, hashes, dependencies, constraints, artifacts = {}, {}, {}, [], []
    for graph in graphs:
        ids = [identity(c) for c in graph["components"]]
        if len(ids) != len(set(ids)):
            raise ValueError("Duplicate graph component")
        known = set(ids)
        for c in graph["components"]:
            ref = identity(c)
            if c["kind"] == "module":
                components[ref] = {"type": "library", "bom-ref": ref, "group": c["group"], "name": c["name"], "version": c["version"], "purl": ref}
            else:
                components[ref] = {"type": "application" if c["path"] == ":app" else "library", "bom-ref": ref, "name": c["path"],
                                   "properties": [{"name": "collect:artifact-scope", "value": "Local project dependency identity only; no project artifact hash or installed plugin source attestation"}]}
            dependencies.setdefault(ref, set())
        for edge in graph["edges"]:
            source, target = identity(edge["from"]), identity(edge["to"])
            if source not in known or target not in known or not isinstance(edge["constraint"], bool):
                raise ValueError("Unbound or malformed observed graph edge")
            if edge["constraint"]:
                constraints.append({"configuration": graph["configuration"], "from": source, "to": target})
            else:
                dependencies[source].add(target)
        for artifact in graph["artifacts"]:
            ref = identity(artifact["component"])
            if ref not in known or artifact["component"]["kind"] != "module" or artifact.get("exists") is not True or not re.fullmatch(r"[a-f0-9]{64}", artifact.get("sha256", "")) or not isinstance(artifact.get("bytes"), int) or artifact["bytes"] <= 0:
                raise ValueError("Unverified observed external artifact")
            hashes.setdefault(ref, set()).add(artifact["sha256"])
            artifacts.append({"configuration": graph["configuration"], **artifact})
    for ref, component in components.items():
        if ref in hashes:
            component["hashes"] = [{"alg": "SHA-256", "content": h} for h in sorted(hashes[ref])]
        if component.get("purl"):
            component["properties"] = [{"name": "collect:license-evidence", "value": "unknown"},
                                       {"name": "collect:artifact-scope", "value": "Observed external AAR/JAR bytes" if ref in hashes else "Selected metadata/platform module; no AAR/JAR bytes reported"}]
    inventory = {"kind": "observed_locked_android_graph_inventory", "scope": "Selected compile/runtime graphs and external artifacts; no signed APK/AAB contents, license approval, advisory or device acceptance",
                 "evidence_sha256": evidence, "components": len(components), "external_artifact_occurrences": len(artifacts),
                 "constraints": constraints, "artifacts": artifacts}
    bom = {"bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
           "metadata": {"properties": [{"name": "collect:scope", "value": inventory["scope"]},
                                        {"name": "collect:evidence-sha256", "value": json.dumps(evidence, sort_keys=True, separators=(",", ":"))},
                                        {"name": "collect:constraint-edges", "value": str(len(constraints))}]},
           "components": [components[ref] for ref in sorted(components)],
           "dependencies": [{"ref": ref, "dependsOn": sorted(dependencies[ref])} for ref in sorted(dependencies)]}
    return bom, inventory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-graph", type=Path, required=True)
    parser.add_argument("--compile-graph", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    paths = [args.runtime_graph, args.compile_graph]
    evidence = {p.resolve().relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    bom, inventory = build([json.loads(p.read_text()) for p in paths], evidence)
    for path, data in [(args.output, bom), (args.inventory, inventory)]:
        text = json.dumps(data, sort_keys=True, indent=2) + "\n"
        if args.check:
            if path.read_text() != text:
                raise ValueError("Observed Android inventory reproduction differs: " + str(path))
        else:
            path.write_text(text)
    print(json.dumps({"components": inventory["components"], "external_artifact_occurrences": inventory["external_artifact_occurrences"]}))


if __name__ == "__main__":
    main()
