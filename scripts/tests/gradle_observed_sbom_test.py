#!/usr/bin/env python3
"""Reject missing artifact integrity and graph edges outside observed identity scope."""
import copy
import hashlib
import importlib.util
import json
import os
import stat
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("gradle_sbom", Path(__file__).resolve().parents[1] / "supply_chain/gradle_observed_sbom.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ObservedGradleSbomTest(unittest.TestCase):
    def graphs(self):
        app = {"kind": "project", "path": ":app"}
        lib = {"kind": "module", "group": "synthetic", "name": "library", "version": "1.0"}
        return [{"configuration": config, "components": [app, lib], "edges": [{"from": app, "to": lib, "constraint": False}, {"from": lib, "to": lib, "constraint": True}],
                 "artifacts": [{"component": lib, "file": "library.aar", "exists": True, "bytes": 1, "sha256": "a" * 64}]}
                for config in ["productionReleaseRuntimeClasspath", "productionReleaseCompileClasspath"]]

    def test_duplicate_occurrences_fold_hashes_and_keep_constraint_scope_distinct(self):
        bom, inventory = module.build(self.graphs(), {})
        self.assertEqual(len(bom["components"]), 2)
        self.assertEqual(inventory["external_artifact_occurrences"], 2)
        self.assertEqual(len(inventory["constraints"]), 2)
        self.assertEqual(len(next(c for c in bom["components"] if c.get("purl"))["hashes"]), 1)

    def test_missing_hash_bytes_unknown_edge_and_duplicate_node_rejected(self):
        for mutation in ["hash", "bytes", "edge", "duplicate", "scope"]:
            graphs = copy.deepcopy(self.graphs())
            if mutation == "hash": graphs[0]["artifacts"][0]["sha256"] = "not a hash"
            if mutation == "bytes": graphs[0]["artifacts"][0]["exists"] = False
            if mutation == "edge": graphs[0]["edges"][0]["to"] = {"kind": "module", "group": "synthetic", "name": "outside-graph", "version": "2.0"}
            if mutation == "duplicate": graphs[0]["components"].append(graphs[0]["components"][0])
            if mutation == "scope": graphs[0]["configuration"] = "devDebugRuntimeClasspath"
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                module.build(graphs, {})

    def test_exact_gateway_pair_keeps_flavor_and_lock_scope_explicit(self):
        graphs = self.graphs()
        for graph in graphs:
            graph['configuration'] = graph['configuration'].replace('production', 'internal_gateway')
        bom, inventory = module.build(graphs, {}, 'internal_gateway')
        self.assertEqual('observed_android_gateway_graph_inventory', inventory['kind'])
        self.assertEqual('internal_gateway', inventory['flavor'])
        self.assertIn('does not establish', inventory['scope'])
        self.assertIn({'name': 'collect:android-flavor', 'value': 'internal_gateway'}, bom['metadata']['properties'])
        with self.assertRaises(ValueError):
            module.build(graphs, {})

    def test_mixed_duplicate_extra_and_unknown_flavor_graphs_are_refused(self):
        for mutation in ['mixed', 'duplicate', 'extra', 'unknown_flavor']:
            graphs = copy.deepcopy(self.graphs())
            flavor = 'production'
            if mutation == 'mixed':
                graphs[0]['configuration'] = 'internal_gatewayReleaseRuntimeClasspath'
            if mutation == 'duplicate':
                graphs[1]['configuration'] = graphs[0]['configuration']
            if mutation == 'extra':
                graphs.append(copy.deepcopy(graphs[0]))
            if mutation == 'unknown_flavor':
                flavor = 'dev'
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                module.build(graphs, {}, flavor)

    def write_graphs(self, root, flavor="production"):
        paths = [root / "runtime.json", root / "nested" / "compile.json"]
        paths[1].parent.mkdir(exist_ok=True)
        for path, graph in zip(paths, self.graphs()):
            graph["configuration"] = graph["configuration"].replace("production", flavor)
            path.write_text(json.dumps(graph, sort_keys=True) + "\n")
        return paths

    def cli(self, paths, output_root, evidence_root=None, flavor="production", check=False):
        argv = [sys.executable, "-I", "-B", str(Path(module.__file__)),
                "--runtime-graph", str(paths[0]), "--compile-graph", str(paths[1]),
                "--output", str(output_root / "bom.json"), "--inventory", str(output_root / "inventory.json"),
                "--flavor", flavor]
        if evidence_root is not None:
            argv += ["--graph-evidence-root", str(evidence_root)]
        if check:
            argv.append("--check")
        return subprocess.run(argv, cwd=module.ROOT, capture_output=True, text=True, timeout=10)

    def test_default_cli_keeps_exact_build_bytes_repository_keys_and_no_root_provenance(self):
        with tempfile.TemporaryDirectory(prefix=".sbom-default-test-", dir=module.ROOT) as directory:
            root = Path(directory).resolve()
            for flavor in module.FLAVOR_CONFIGURATIONS:
                with self.subTest(flavor=flavor):
                    paths = self.write_graphs(root, flavor)
                    evidence = {p.relative_to(module.ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
                    expected = module.build([json.loads(p.read_bytes()) for p in paths], evidence, flavor)
                    for graph_paths in [paths, [p.relative_to(module.ROOT) for p in paths]]:
                        result = self.cli(graph_paths, root, flavor=flavor)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        for path, data in zip([root / "bom.json", root / "inventory.json"], expected):
                            self.assertEqual(path.read_bytes(), (json.dumps(data, sort_keys=True, indent=2) + "\n").encode())
                        self.assertNotIn("graph_evidence_root", expected[1])
                        self.assertFalse(any(p["name"] == "collect:graph-evidence-root" for p in expected[0]["metadata"]["properties"]))
                    result = self.cli(paths, root, flavor=flavor, check=True)
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_external_root_cli_generates_truthful_keys_and_reproduces_exact_bytes_for_both_flavors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            self.assertFalse(root.is_relative_to(module.ROOT))
            for flavor in module.FLAVOR_CONFIGURATIONS:
                with self.subTest(flavor=flavor):
                    paths = self.write_graphs(root, flavor)
                    result = self.cli(paths, root, evidence_root=root, flavor=flavor)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    evidence = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
                    bom = json.loads((root / "bom.json").read_bytes())
                    inventory = json.loads((root / "inventory.json").read_bytes())
                    self.assertEqual(inventory["evidence_sha256"], evidence)
                    self.assertEqual(inventory["graph_evidence_root"], str(root))
                    self.assertEqual(inventory["evidence_path_basis"], "relative_to_declared_physical_root")
                    properties = {p["name"]: p["value"] for p in bom["metadata"]["properties"]}
                    self.assertEqual(json.loads(properties["collect:evidence-sha256"]), evidence)
                    self.assertEqual(properties["collect:graph-evidence-root"], str(root))
                    self.assertEqual(properties["collect:evidence-path-basis"], inventory["evidence_path_basis"])
                    before = [(root / name).read_bytes() for name in ["bom.json", "inventory.json"]]
                    result = self.cli(paths, root, evidence_root=root, flavor=flavor, check=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(before, [(root / name).read_bytes() for name in ["bom.json", "inventory.json"]])

    def test_external_graphs_still_require_explicit_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            result = self.cli(self.write_graphs(root), root)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / "bom.json").exists())
            self.assertFalse((root / "inventory.json").exists())

    def test_explicit_root_refuses_missing_relative_file_symlink_and_lexical_aliases(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            paths = self.write_graphs(root)
            alias = root / "alias"
            alias.symlink_to(root, target_is_directory=True)
            invalid = ["relative-root", root / "missing", paths[0], alias,
                       str(root) + "/.", str(root) + "/nested/..", str(root) + "/"]
            for candidate in invalid:
                with self.subTest(root=str(candidate)):
                    result = self.cli(paths, root, evidence_root=candidate)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse((root / "bom.json").exists())
                    self.assertFalse((root / "inventory.json").exists())

    def test_explicit_graphs_refuse_escape_traversal_relative_duplicate_and_aliases(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            root = base / "root"
            root.mkdir()
            paths = self.write_graphs(root)
            outside = base / "outside.json"
            outside.write_bytes(paths[0].read_bytes())
            alias = root / "alias.json"
            alias.symlink_to(paths[0])
            parent_alias = root / "alias-directory"
            parent_alias.symlink_to(paths[1].parent, target_is_directory=True)
            invalid = [[outside, paths[1]], [paths[0], paths[0]],
                       [str(root) + "/nested/../runtime.json", paths[1]],
                       ["runtime.json", paths[1]], [alias, paths[1]],
                       [paths[0], parent_alias / paths[1].name], [paths[0], root]]
            for pair in invalid:
                with self.subTest(graphs=[str(p) for p in pair]):
                    result = self.cli(pair, root, evidence_root=root)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse((root / "bom.json").exists())
                    self.assertFalse((root / "inventory.json").exists())

    def test_explicit_graphs_refuse_hard_link_alias_and_fifo_without_blocking(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            paths = self.write_graphs(root)
            hard_link = root / "hard-link.json"
            os.link(paths[0], hard_link)
            result = self.cli([paths[0], hard_link], root, evidence_root=root)
            self.assertNotEqual(result.returncode, 0)
            hard_link.unlink()
            fifo = root / "fifo.json"
            os.mkfifo(fifo)
            result = self.cli([paths[0], fifo], root, evidence_root=root)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / "bom.json").exists())
            self.assertFalse((root / "inventory.json").exists())

    def test_explicit_graph_changed_during_descriptor_read_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            paths = self.write_graphs(root)
            original_read = os.read
            changed = False

            def change_during_read(fd, count):
                nonlocal changed
                data = original_read(fd, count)
                if not changed:
                    changed = True
                    paths[0].write_bytes(paths[0].read_bytes() + b" ")
                return data

            with patch.object(module.os, "read", side_effect=change_during_read):
                with self.assertRaisesRegex(ValueError, "changed during read"):
                    module.read_rooted_graph_evidence([str(p) for p in paths], str(root))
            self.assertTrue(changed)

    def test_explicit_check_rejects_changed_root_provenance_without_overwriting(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            paths = self.write_graphs(root)
            self.assertEqual(self.cli(paths, root, evidence_root=root).returncode, 0)
            originals = {name: (root / name).read_bytes() for name in ["bom.json", "inventory.json"]}
            for name in originals:
                with self.subTest(document=name):
                    document = json.loads(originals[name])
                    if name == "inventory.json":
                        document["graph_evidence_root"] = str(root / "fabricated")
                    else:
                        next(p for p in document["metadata"]["properties"] if p["name"] == "collect:graph-evidence-root")["value"] = str(root / "fabricated")
                    changed = (json.dumps(document, sort_keys=True, indent=2) + "\n").encode()
                    (root / name).write_bytes(changed)
                    result = self.cli(paths, root, evidence_root=root, check=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("reproduction differs", result.stderr)
                    self.assertEqual((root / name).read_bytes(), changed)
                    (root / name).write_bytes(originals[name])

    def test_explicit_root_bom_passes_retained_offline_cyclonedx_schema(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            result = self.cli(self.write_graphs(root), root, evidence_root=root)
            self.assertEqual(result.returncode, 0, result.stderr)
            validator = module.ROOT / "scripts/supply_chain/validate_source_sbom.py"
            result = subprocess.run([sys.executable, "-I", "-B", str(validator), str(root / "bom.json")],
                                    cwd=module.ROOT, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            validation = json.loads(result.stdout)
            self.assertEqual(validation["status"], "pass")
            self.assertEqual(validation["network_fetches"], 0)
            self.assertTrue(validation["schema_conformance_only"])


class CachedObservedLicenseTest(unittest.TestCase):
    """Synthetic pinned-file joins exercise refusal; they are not licence approvals."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.declaration = self.repo / "gradle.lockfile"
        self.declaration.write_text("synthetic:library:1.0\n")
        self.graphs = ObservedGradleSbomTest().graphs()
        self.graph_paths = [self.root / "runtime.json", self.root / "compile.json"]
        for path, graph in zip(self.graph_paths, self.graphs):
            path.write_text(json.dumps(graph))
        self.evidence = {path.name: self.pin(path)["sha256"] for path in self.graph_paths}
        self.bom, self.inventory = module.build(self.graphs, self.evidence)
        self.baseline = self.root / "baseline.json"
        self.baseline.write_text(json.dumps(self.bom, indent=2) + "\n")
        self.artifact = self.root / "synthetic.aab"
        self.artifact.write_bytes(b"INERT ARTIFACT HASH FIXTURE, NOT A BUILD")
        self.pom = self.root / "library.pom"
        self.pom.write_text("<project>INERT CACHED METADATA FIXTURE</project>")
        self.witness_path = self.root / "witnesses.json"
        self.join_path = self.root / "join.json"
        self.binding_path = self.root / "binding.json"
        self.witness = {"kind": "local_cached_license_witness_companion", "license_approval": False,
                        "input_bindings": {str(self.declaration): self.pin(self.declaration), str(self.pom): self.pin(self.pom)},
                        "packages": [{"identity": {"ecosystem": "maven", "name": "synthetic:library", "version": "1.0", "evidence": "gradle.lockfile", "qualifier": "runtime"},
                                      "status": "pom_license_metadata", "license_approval": False,
                                      "artifact_license_contents_verified": False,
                                      "poms": [{"path": str(self.pom), "declared_licenses": [{"name": "Publisher fixture words", "url": "https://example.invalid/terms", "distribution": "repo", "comments": ""}]}]}]}
        self.join = {"kind": "exact_coordinate_join_only", "installed_final_R8_membership_or_licence_approval": False,
                     "observed_sbom": {"path": str(self.baseline), **self.pin(self.baseline)},
                     "rows": [{"purl": "pkg:maven/synthetic/library@1.0", "name": "synthetic:library", "version": "1.0",
                               "witness_statuses": ["pom_license_metadata"], "declaration_count": 1,
                               "declaration_evidence": ["gradle.lockfile"], "license_approval": False,
                               "artifact_licence_contents_verified": False}],
                     "observed_maven_coordinates": 1, "status_counts": {"pom_license_metadata": 1}}
        self.binding = {"AAB": {"path": str(self.artifact), **self.pin(self.artifact)}, "SBOM": self.pin(self.baseline),
                        "graph_inputs": {str(path): self.pin(path) for path in self.graph_paths},
                        "actual_build_and_selected_graphs_same_source_epoch": True,
                        "selected_graph_is_final_R8_contents_or_licence_advisory_store_acceptance": False}
        self.refresh()

    @staticmethod
    def pin(path):
        return {"bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

    def refresh(self):
        self.witness_path.write_text(json.dumps(self.witness))
        self.join["declared_witnesses"] = {"path": str(self.witness_path), **self.pin(self.witness_path)}
        self.join_path.write_text(json.dumps(self.join))
        self.binding_path.write_text(json.dumps(self.binding))

    def annotate(self):
        return module.cached_license_annotations(
            copy.deepcopy(self.bom), copy.deepcopy(self.inventory), self.graph_paths,
            witnesses_path=self.witness_path, witnesses_sha256=self.pin(self.witness_path)["sha256"],
            coordinate_join_path=self.join_path, coordinate_join_sha256=self.pin(self.join_path)["sha256"],
            artifact_binding_path=self.binding_path, artifact_binding_sha256=self.pin(self.binding_path)["sha256"],
            declarations_root=self.repo)

    def test_exact_pinned_metadata_adds_witnesses_without_spdx_or_approval(self):
        bom, inventory = self.annotate()
        component = next(c for c in bom["components"] if c.get("purl"))
        props = {p["name"]: p["value"] for p in component["properties"]}
        self.assertEqual(props["collect:license-evidence"], "cached_pom_license_metadata")
        self.assertIn("Publisher fixture words", props["collect:license-pom-witnesses"])
        self.assertNotIn("licenses", component)
        proof = inventory["cached_license_evidence"]
        self.assertEqual(proof["artifact"], self.binding["AAB"])
        self.assertEqual(proof["declarations"], {"gradle.lockfile": self.pin(self.declaration)})
        self.assertFalse(proof["license_approval"])
        self.assertFalse(proof["SPDX_inferred"])
        self.assertFalse(proof["artifact_license_contents_verified"])
        self.assertFalse(proof["final_R8_membership"])
        self.assertNotIn("cached_license_evidence", self.inventory)

    def test_missing_direct_pom_metadata_remains_unknown(self):
        self.witness["packages"][0]["status"] = "pom_license_metadata_missing"
        self.witness["packages"][0]["poms"][0]["declared_licenses"] = []
        self.join["rows"][0]["witness_statuses"] = ["pom_license_metadata_missing"]
        self.join["status_counts"] = {"pom_license_metadata_missing": 1}
        self.refresh()
        bom, inventory = self.annotate()
        props = {p["name"]: p["value"] for c in bom["components"] if c.get("purl") for p in c["properties"]}
        self.assertEqual(props["collect:license-evidence"], "unknown")
        self.assertEqual(props["collect:license-witness-status"], "pom_license_metadata_missing")

    def test_unknown_duplicate_and_changed_join_coordinates_are_refused(self):
        original = copy.deepcopy(self.join)
        for mutation in ["unknown", "duplicate", "version", "declaration"]:
            self.join = copy.deepcopy(original)
            if mutation == "unknown": self.join["rows"][0]["purl"] = "pkg:maven/synthetic/unknown@1.0"
            if mutation == "duplicate": self.join["rows"].append(copy.deepcopy(self.join["rows"][0]))
            if mutation == "version": self.join["rows"][0]["version"] = "2.0"
            if mutation == "declaration": self.join["rows"][0]["declaration_evidence"] = ["other.lock"]
            self.refresh()
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): self.annotate()

    def test_unknown_conflicting_and_duplicate_witnesses_are_refused(self):
        original = copy.deepcopy(self.witness)
        for mutation in ["unknown_status", "duplicate", "approval", "publisher_conflict"]:
            self.witness = copy.deepcopy(original)
            row = self.witness["packages"][0]
            if mutation == "unknown_status": row["status"] = "unknown"
            if mutation == "duplicate": self.witness["packages"].append(copy.deepcopy(row))
            if mutation == "approval": row["license_approval"] = True
            if mutation == "publisher_conflict":
                second = self.root / "other.pom"; second.write_text("other inert metadata")
                self.witness["input_bindings"][str(second)] = self.pin(second)
                other = copy.deepcopy(row["poms"][0]); other["path"] = str(second)
                other["declared_licenses"][0]["name"] = "Different publisher words"; row["poms"].append(other)
            self.refresh()
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): self.annotate()

    def test_changed_artifact_graph_and_declaration_bytes_are_refused(self):
        for path in [self.artifact, self.graph_paths[0], self.declaration]:
            before = path.read_bytes(); path.write_bytes(before + b"changed")
            with self.subTest(path=path.name), self.assertRaises(ValueError): self.annotate()
            path.write_bytes(before)

    def test_changed_expected_witness_pin_and_baseline_are_refused(self):
        with self.assertRaisesRegex(ValueError, "hash/identity"):
            module.cached_license_annotations(self.bom, self.inventory, self.graph_paths,
                witnesses_path=self.witness_path, witnesses_sha256="0" * 64,
                coordinate_join_path=self.join_path, coordinate_join_sha256=self.pin(self.join_path)["sha256"],
                artifact_binding_path=self.binding_path, artifact_binding_sha256=self.pin(self.binding_path)["sha256"],
                declarations_root=self.repo)
        changed = copy.deepcopy(self.bom); changed["components"][0]["name"] = "changed"
        with self.assertRaisesRegex(ValueError, "baseline SBOM"):
            with patch.object(self, "bom", changed): self.annotate()

    def test_optional_cli_refuses_incomplete_mode_and_existing_additive_outputs(self):
        argv = ["exporter", "--runtime-graph", str(self.graph_paths[0]), "--compile-graph", str(self.graph_paths[1]),
                "--graph-evidence-root", str(self.root), "--output", str(self.root / "new-bom.json"),
                "--inventory", str(self.root / "new-inventory.json"), "--license-witnesses", str(self.witness_path)]
        with patch.object(sys, "argv", argv), self.assertRaisesRegex(ValueError, "all three pinned inputs"):
            module.main()
        argv += ["--license-witnesses-sha256", self.pin(self.witness_path)["sha256"],
                 "--license-coordinate-join", str(self.join_path), "--license-coordinate-join-sha256", self.pin(self.join_path)["sha256"],
                 "--artifact-graph-binding", str(self.binding_path), "--artifact-graph-binding-sha256", self.pin(self.binding_path)["sha256"],
                 "--license-declarations-root", str(self.repo)]
        with patch.object(sys, "argv", argv): module.main()
        body = (self.root / "new-bom.json").read_bytes()
        with patch.object(sys, "argv", argv), self.assertRaisesRegex(ValueError, "fresh additive"):
            module.main()
        self.assertEqual(body, (self.root / "new-bom.json").read_bytes())
        with patch.object(sys, "argv", argv + ["--check"]): module.main()

    def test_pinned_reader_refuses_fifo_before_blocking_read(self):
        fifo = self.root / "inert.fifo"
        os.mkfifo(fifo)
        script = ("import hashlib,importlib.util,sys;"
                  "s=importlib.util.spec_from_file_location('fifo_reader',sys.argv[1]);"
                  "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
                  "m.read_pinned_file(sys.argv[2],{'bytes':0,'sha256':hashlib.sha256(b'').hexdigest()})")
        # A broken blocking-open regression fails within two seconds instead of
        # hanging the suite. The child imports this Python module only.
        result = subprocess.run([sys.executable, "-I", "-B", "-c", script, str(Path(module.__file__)), str(fifo)],
                                capture_output=True, text=True, timeout=2)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cached evidence size/type mismatch", result.stderr)
        self.assertTrue(stat.S_ISFIFO(fifo.lstat().st_mode))


if __name__ == "__main__":
    unittest.main()
