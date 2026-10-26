#!/usr/bin/env python3
"""CycloneDX inventory of exact observed Android flavor graphs and artifact bytes."""
import argparse
from collections import Counter, defaultdict
from contextlib import ExitStack
import hashlib
import json
import os
from pathlib import Path
import re
import stat
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]
FLAVOR_CONFIGURATIONS = {
    "production": {"productionReleaseRuntimeClasspath", "productionReleaseCompileClasspath"},
    "internal_gateway": {"internal_gatewayReleaseRuntimeClasspath", "internal_gatewayReleaseCompileClasspath"},
}


def identity(record):
    if record.get("kind") == "module":
        return "pkg:maven/" + quote(record["group"], safe=".") + "/" + quote(record["name"], safe="") + "@" + quote(record["version"], safe="")
    if record.get("kind") == "project":
        return "collect:local-gradle-project:" + quote(record["path"], safe="")
    raise ValueError("Unknown observed Gradle component identity")


def build(graphs, evidence, flavor="production"):
    expected = FLAVOR_CONFIGURATIONS.get(flavor)
    if expected is None or len(graphs) != 2 or {g.get("configuration") for g in graphs} != expected:
        raise ValueError("Both exact graphs for the declared Android flavor are required")
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
    scope = "Selected compile/runtime graphs and external artifacts; no signed APK/AAB contents, license approval, advisory or device acceptance"
    if flavor == "internal_gateway":
        scope += "; Gateway graph observation does not establish the separately reviewed production dependency lock"
    inventory = {"kind": "observed_locked_android_graph_inventory" if flavor == "production" else "observed_android_gateway_graph_inventory", "scope": scope,
                 "flavor": flavor, "configurations": sorted(expected),
                 "evidence_sha256": evidence, "components": len(components), "external_artifact_occurrences": len(artifacts),
                 "constraints": constraints, "artifacts": artifacts}
    bom = {"bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
           "metadata": {"properties": [{"name": "collect:scope", "value": inventory["scope"]},
                                        {"name": "collect:evidence-sha256", "value": json.dumps(evidence, sort_keys=True, separators=(",", ":"))},
                                        {"name": "collect:android-flavor", "value": flavor},
                                        {"name": "collect:constraint-edges", "value": str(len(constraints))}]},
           "components": [components[ref] for ref in sorted(components)],
           "dependencies": [{"ref": ref, "dependsOn": sorted(dependencies[ref])} for ref in sorted(dependencies)]}
    return bom, inventory


def canonical_existing_path(raw):
    path = Path(raw)
    if not path.is_absolute() or raw != path.as_posix() or path.resolve(strict=True) != path:
        raise ValueError("Graph evidence paths must be absolute, canonical and existing: " + raw)
    return path


def read_rooted_graph_evidence(raw_paths, raw_root):
    """Read each plain graph once through directories anchored to its physical root."""
    root = canonical_existing_path(raw_root)
    root_stat = root.lstat()
    if not stat.S_ISDIR(root_stat.st_mode):
        raise ValueError("Graph evidence root must be a physical directory")
    paths = [canonical_existing_path(raw) for raw in raw_paths]
    relative = [path.relative_to(root) for path in paths]
    keys = [path.as_posix() for path in relative]
    if len(set(keys)) != len(keys):
        raise ValueError("Duplicate graph evidence key")
    graphs, evidence, identities = [], {}, set()

    def identity(info):
        return info.st_dev, info.st_ino

    def snapshot(info):
        return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink,
                info.st_size, info.st_mtime_ns, info.st_ctime_ns)

    with ExitStack() as descriptors:
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        root_fd = os.open(root.anchor, flags)
        descriptors.callback(os.close, root_fd)
        for part in root.parts[1:]:
            root_fd = os.open(part, flags, dir_fd=root_fd)
            descriptors.callback(os.close, root_fd)
        if identity(os.fstat(root_fd)) != identity(root_stat):
            raise ValueError("Graph evidence root changed before admission")
        for path, child, key in zip(paths, relative, keys):
            parent_fd = root_fd
            for part in child.parts[:-1]:
                parent_fd = os.open(part, flags, dir_fd=parent_fd)
                descriptors.callback(os.close, parent_fd)
            fd = os.open(child.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK,
                         dir_fd=parent_fd)
            descriptors.callback(os.close, fd)
            before = os.fstat(fd)
            if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
                raise ValueError("Graph evidence must be a plain file without aliases")
            if identity(before) in identities:
                raise ValueError("Distinct graph evidence files are required")
            identities.add(identity(before))
            chunks = []
            while chunk := os.read(fd, 1024 * 1024):
                chunks.append(chunk)
            raw = b"".join(chunks)
            if (len(raw) != before.st_size or snapshot(os.fstat(fd)) != snapshot(before)
                    or snapshot(path.lstat()) != snapshot(before) or path.resolve(strict=True) != path):
                raise ValueError("Graph evidence changed during read")
            evidence[key] = hashlib.sha256(raw).hexdigest()
            graphs.append(json.loads(raw))
        if identity(root.lstat()) != identity(root_stat) or root.resolve(strict=True) != root:
            raise ValueError("Graph evidence root changed during read")
    return graphs, evidence, root


def checked_pin(value):
    if (not isinstance(value, dict) or type(value.get("bytes")) is not int
            or value["bytes"] < 0 or not re.fullmatch(r"[a-f0-9]{64}", value.get("sha256", ""))):
        raise ValueError("Malformed cached evidence pin")
    return {key: value[key] for key in ("bytes", "sha256")}


def read_pinned_file(raw_path, expected, maximum=4 * 1024**2):
    """Hash a bounded regular input without executing its contents."""
    expected = checked_pin(expected)
    path = canonical_existing_path(str(raw_path))
    with ExitStack() as descriptors:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC)
        descriptors.callback(os.close, fd)
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_size != expected["bytes"] or before.st_size > maximum:
            raise ValueError("Cached evidence size/type mismatch: " + str(path))
        digest, chunks, count = hashlib.sha256(), [], 0
        with os.fdopen(fd, "rb", closefd=False) as stream:
            while chunk := stream.read(1024**2):
                count += len(chunk)
                if count > maximum or count > expected["bytes"]:
                    raise ValueError("Cached evidence grew: " + str(path))
                digest.update(chunk)
                if maximum <= 4 * 1024**2:
                    chunks.append(chunk)
        after = os.fstat(fd)
    fields = ("st_dev", "st_ino", "st_mode", "st_nlink", "st_size", "st_mtime_ns", "st_ctime_ns")
    snapshot = lambda info: tuple(getattr(info, name) for name in fields)
    if (snapshot(before) != snapshot(after) or snapshot(after) != snapshot(path.lstat())
            or count != expected["bytes"] or digest.hexdigest() != expected["sha256"]
            or path.resolve(strict=True) != path):
        raise ValueError("Cached evidence hash/identity changed: " + str(path))
    return b"".join(chunks)


def cached_license_annotations(bom, inventory, graph_paths, *, witnesses_path, witnesses_sha256,
                               coordinate_join_path, coordinate_join_sha256,
                               artifact_binding_path, artifact_binding_sha256, declarations_root):
    """Optional publisher-metadata annotations; never SPDX or redistribution approval."""
    def load(path, digest):
        if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise ValueError("An explicit full cached evidence SHA256 is required")
        path = canonical_existing_path(str(path))
        bound = {"bytes": path.stat().st_size, "sha256": digest}
        return json.loads(read_pinned_file(path, bound)), bound

    witnesses, witness_pin = load(witnesses_path, witnesses_sha256)
    joined, join_pin = load(coordinate_join_path, coordinate_join_sha256)
    binding, binding_pin = load(artifact_binding_path, artifact_binding_sha256)
    if (witnesses.get("kind") != "local_cached_license_witness_companion"
            or witnesses.get("license_approval") is not False
            or joined.get("kind") != "exact_coordinate_join_only"
            or joined.get("installed_final_R8_membership_or_licence_approval") is not False
            or binding.get("actual_build_and_selected_graphs_same_source_epoch") is not True
            or binding.get("selected_graph_is_final_R8_contents_or_licence_advisory_store_acceptance") is not False):
        raise ValueError("Cached evidence scope or approval mismatch")
    if (checked_pin(joined["declared_witnesses"]) != witness_pin
            or joined["declared_witnesses"]["path"] != str(witnesses_path)
            or checked_pin(joined["observed_sbom"]) != checked_pin(binding["SBOM"])):
        raise ValueError("Cached witness/SBOM binding mismatch")
    baseline = json.loads(read_pinned_file(joined["observed_sbom"]["path"], binding["SBOM"]))
    if baseline != bom:
        raise ValueError("Cached licence coordinates do not bind the generated baseline SBOM")
    paths = {str(path) for path in graph_paths}
    if set(binding["graph_inputs"]) != paths:
        raise ValueError("Artifact graph coordinate/path set mismatch")
    for path in paths:
        read_pinned_file(path, binding["graph_inputs"][path])
    artifact = binding["AAB"]
    read_pinned_file(artifact["path"], artifact, maximum=1024**3)
    components = {component["purl"]: component for component in bom["components"] if component.get("purl")}
    join_rows = joined["rows"]
    if (not isinstance(join_rows, list) or len(join_rows) != len(components)
            or len({row["purl"] for row in join_rows}) != len(join_rows)
            or {row["purl"] for row in join_rows} != set(components)):
        raise ValueError("Duplicate, unknown or changed cached licence coordinates")
    packages = witnesses["packages"]
    if not isinstance(packages, list) or len(packages) > 10000:
        raise ValueError("Invalid cached declaration count")
    rows, declarations, identities = defaultdict(list), {}, set()
    for row in packages:
        item = row["identity"]
        if item["ecosystem"] != "maven":
            continue
        exact = json.dumps(item, sort_keys=True)
        if exact in identities:
            raise ValueError("Duplicate cached Maven declaration identity")
        identities.add(exact)
        rows[(item["name"], item["version"])].append(row)
    root = canonical_existing_path(str(declarations_root))
    statuses, annotations = Counter(), {}
    for joined_row in join_rows:
        purl = joined_row["purl"]
        component = components[purl]
        key = (component["group"] + ":" + component["name"], component["version"])
        selected = rows[key]
        status = sorted({row["status"] for row in selected})
        if len(status) != 1 or status[0] not in {"pom_license_metadata", "pom_license_metadata_missing"}:
            raise ValueError("Unknown, missing or conflicting cached licence witness status")
        evidence = sorted({row["identity"]["evidence"] for row in selected})
        expected_row = {"purl": purl, "name": key[0], "version": key[1], "witness_statuses": status,
                        "declaration_count": len(selected), "declaration_evidence": evidence,
                        "license_approval": False, "artifact_licence_contents_verified": False}
        if joined_row != expected_row:
            raise ValueError("Cached exact coordinate/declaration/status mismatch")
        for name in evidence:
            relative = Path(name)
            if relative.is_absolute() or ".." in relative.parts or relative.as_posix() != name:
                raise ValueError("Cached declaration escapes its explicit root")
            path = root / relative
            expected = checked_pin(witnesses["input_bindings"][str(path)])
            if name not in declarations:
                read_pinned_file(path, expected)
                declarations[name] = expected
        poms = {}
        for row in selected:
            if row.get("license_approval") is not False or row.get("artifact_license_contents_verified") is not False or not row.get("poms"):
                raise ValueError("Cached POM witness scope mismatch")
            for pom in row["poms"]:
                proof = {"path": pom["path"], **checked_pin(witnesses["input_bindings"][pom["path"]]),
                         "declared_licenses": pom["declared_licenses"]}
                if (not isinstance(proof["declared_licenses"], list)
                        or bool(proof["declared_licenses"]) != (status[0] == "pom_license_metadata")
                        or any(not isinstance(item, dict) or not item.get("name")
                               or set(item) != {"name", "url", "distribution", "comments"}
                               or any(not isinstance(value, str) for value in item.values())
                               for item in proof["declared_licenses"])):
                    raise ValueError("Cached publisher licence metadata mismatch")
                if pom["path"] in poms and poms[pom["path"]] != proof:
                    raise ValueError("Conflicting cached POM witnesses")
                poms[pom["path"]] = proof
        if len({json.dumps(pom["declared_licenses"], sort_keys=True) for pom in poms.values()}) != 1:
            raise ValueError("Conflicting cached publisher licence declarations")
        statuses[status[0]] += 1
        annotations[purl] = (status[0], [poms[path] for path in sorted(poms)])
    if joined.get("observed_maven_coordinates") != len(components) or joined.get("status_counts") != dict(statuses):
        raise ValueError("Cached coordinate/status totals mismatch")
    proof = {"kind": "exact_cached_publisher_metadata_only", "artifact": artifact,
             "baseline_sbom": checked_pin(binding["SBOM"]), "artifact_graph_binding": binding_pin,
             "witnesses": witness_pin, "coordinate_join": join_pin,
             "declarations": dict(sorted(declarations.items())), "statuses": dict(sorted(statuses.items())),
             "license_approval": False, "artifact_license_contents_verified": False,
             "SPDX_inferred": False, "final_R8_membership": False}
    for purl, (status, poms) in annotations.items():
        properties = components[purl]["properties"]
        license_property = next(p for p in properties if p["name"] == "collect:license-evidence")
        if license_property["value"] != "unknown":
            raise ValueError("Baseline already contains licence annotations")
        if status == "pom_license_metadata":
            license_property["value"] = "cached_pom_license_metadata"
        properties.extend([{"name": "collect:license-witness-status", "value": status},
                           {"name": "collect:license-pom-witnesses", "value": json.dumps(poms, sort_keys=True, separators=(",", ":"))}])
    bom["metadata"]["properties"].append({"name": "collect:cached-license-evidence", "value": json.dumps(proof, sort_keys=True, separators=(",", ":"))})
    inventory["cached_license_evidence"] = proof
    return bom, inventory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-graph", required=True)
    parser.add_argument("--compile-graph", required=True)
    parser.add_argument("--graph-evidence-root", help="Explicit physical root for absolute canonical graph paths; defaults to the repository root")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--flavor", choices=sorted(FLAVOR_CONFIGURATIONS), default="production")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--license-witnesses", type=Path)
    parser.add_argument("--license-witnesses-sha256")
    parser.add_argument("--license-coordinate-join", type=Path)
    parser.add_argument("--license-coordinate-join-sha256")
    parser.add_argument("--artifact-graph-binding", type=Path)
    parser.add_argument("--artifact-graph-binding-sha256")
    parser.add_argument("--license-declarations-root", type=Path)
    args = parser.parse_args()
    optional = [args.license_witnesses, args.license_witnesses_sha256, args.license_coordinate_join,
                args.license_coordinate_join_sha256, args.artifact_graph_binding, args.artifact_graph_binding_sha256]
    license_mode = any(value is not None for value in optional) or args.license_declarations_root is not None
    if license_mode and (not all(value is not None for value in optional) or args.graph_evidence_root is None):
        raise ValueError("Cached licence mode requires all three pinned inputs and an explicit graph evidence root")
    if license_mode and not args.check and (args.output.exists() or args.inventory.exists()):
        raise ValueError("Cached licence annotations require fresh additive output paths")
    paths = [Path(args.runtime_graph), Path(args.compile_graph)]
    if args.graph_evidence_root is None:
        evidence = {p.resolve().relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        bom, inventory = build([json.loads(p.read_text()) for p in paths], evidence, args.flavor)
    else:
        graphs, evidence, root = read_rooted_graph_evidence(
            [args.runtime_graph, args.compile_graph], args.graph_evidence_root)
        bom, inventory = build(graphs, evidence, args.flavor)
        if license_mode:
            bom, inventory = cached_license_annotations(
                bom, inventory, paths, witnesses_path=args.license_witnesses,
                witnesses_sha256=args.license_witnesses_sha256,
                coordinate_join_path=args.license_coordinate_join,
                coordinate_join_sha256=args.license_coordinate_join_sha256,
                artifact_binding_path=args.artifact_graph_binding,
                artifact_binding_sha256=args.artifact_graph_binding_sha256,
                declarations_root=args.license_declarations_root or ROOT)
        inventory.update(graph_evidence_root=str(root), evidence_path_basis="relative_to_declared_physical_root")
        bom["metadata"]["properties"].extend([
            {"name": "collect:graph-evidence-root", "value": str(root)},
            {"name": "collect:evidence-path-basis", "value": inventory["evidence_path_basis"]},
        ])
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
