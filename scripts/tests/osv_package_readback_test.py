import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("osv_readback", Path(__file__).resolve().parents[1] / "supply_chain/osv_package_readback.py")
osv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(osv)


class ReadbackTest(unittest.TestCase):
    def test_private_local_sdk_and_root_project_identities_are_never_queried(self):
        sbom = {"bomFormat": "CycloneDX", "components": [{"bom-ref": "private-local-project"}]}
        pub = {"packages": {
            "public": {"source": "hosted", "description": {"name": "public", "url": "https://pub.dev"}, "version": "1.2.3"},
            "private": {"source": "hosted", "description": {"name": "private", "url": "https://private.example.test"}, "version": "1.0.0"},
            "sdk": {"source": "sdk", "version": "0.0.0"},
        }}
        npm = {"lockfileVersion": 3, "packages": {"": {"name": "private-root"}, "node_modules/private": {"resolved": "file:private", "version": "1.0.0"}}}
        rows, skipped = osv.packages(sbom, pub, npm)
        self.assertEqual([r["package"]["name"] for r in rows], ["public"])
        self.assertEqual(len(skipped), 4)
        self.assertNotIn("private", json.dumps({"queries": [{k: r[k] for k in ["package", "version"]} for r in rows]}))

    def test_changed_pub_identity_and_control_characters_fail_closed(self):
        sbom = {"bomFormat": "CycloneDX", "components": []}
        npm = {"lockfileVersion": 3, "packages": {}}
        for description in [{"name": "other", "url": "https://pub.dev"}, {"name": "bad\nname", "url": "https://pub.dev"}]:
            name = "public" if description["name"] == "other" else description["name"]
            with self.assertRaises(ValueError):
                osv.packages(sbom, {"packages": {name: {"source": "hosted", "description": description, "version": "1.0.0"}}}, npm)

    def test_partial_cardinality_cannot_become_a_completed_readback(self):
        with tempfile.TemporaryDirectory() as path:
            with self.assertRaisesRegex(ValueError, "cardinality"):
                osv.scan([{"package": {"ecosystem": "Pub", "name": "sample"}, "version": "1.0.0"}], Path(path), lambda _: {"results": []})

    def test_pagination_requeries_only_the_incomplete_package_and_preserves_prior_matches(self):
        calls = []
        def query(payload):
            calls.append(payload)
            return {"results": [{"vulns": [{"id": "GHSA-first"}], "next_page_token": "next"}, {}]} if len(calls) == 1 else {"results": [{"vulns": [{"id": "GHSA-second"}]}]}
        inventory = [{"package": {"ecosystem": "Pub", "name": name}, "version": "1.0.0"} for name in ["a", "b"]]
        with tempfile.TemporaryDirectory() as path:
            result = osv.scan(inventory, Path(path), query)
        self.assertEqual([[v["id"] for v in matches] for matches in result], [["GHSA-first", "GHSA-second"], []])
        self.assertEqual(len(calls[1]["queries"]), 1)
        self.assertEqual(calls[1]["queries"][0]["package"]["name"], "a")

    def test_repeated_tokens_and_malformed_identifiers_never_clear_the_query(self):
        inventory = [{"package": {"ecosystem": "Pub", "name": "a"}, "version": "1.0.0"}]
        for reply in [{"next_page_token": "repeat"}, {"vulns": [{"id": "bad/path"}]}, {"vulns": "wrong"}]:
            with tempfile.TemporaryDirectory() as path, self.assertRaises(ValueError):
                osv.scan(inventory, Path(path), lambda _: {"results": [reply]})

    def test_queries_are_bounded_and_do_not_send_local_scope_annotations(self):
        inventory = [{"package": {"ecosystem": "Pub", "name": f"a{i}"}, "version": "1.0.0", "scopes": ["private-path-must-stay-local"]} for i in range(201)]
        calls = []
        def query(payload):
            calls.append(payload)
            self.assertNotIn("private-path", json.dumps(payload))
            return {"results": [{} for _ in payload["queries"]]}
        with tempfile.TemporaryDirectory() as path:
            result = osv.scan(inventory, Path(path), query)
        self.assertEqual([len(c["queries"]) for c in calls], [100, 100, 1])
        self.assertEqual(len(result), 201)


if __name__ == "__main__":
    unittest.main()
