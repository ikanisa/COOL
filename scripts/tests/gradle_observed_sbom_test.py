#!/usr/bin/env python3
"""Reject missing artifact integrity and graph edges outside observed identity scope."""
import copy
import importlib.util
from pathlib import Path
import unittest

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


if __name__ == "__main__":
    unittest.main()
