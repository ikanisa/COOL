import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

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

    def test_repository_unconfirmed_maven_is_excluded(self):
        sbom = {"bomFormat": "CycloneDX", "components": [{"purl": "pkg:maven/androidx.test/core@1.0", "group": "androidx.test", "name": "core", "version": "1.0"}]}
        pub = {"packages": {"public": {"source": "hosted", "description": {"name": "public", "url": "https://pub.dev"}, "version": "1.2.3"}}}
        rows, skipped = osv.packages(sbom, pub, {"lockfileVersion": 3, "packages": {}})
        self.assertEqual([r["package"]["ecosystem"] for r in rows], ["Pub"])
        self.assertIn("repository origin", skipped[0]["reason"])

    def test_npm_sources_are_deduplicated_but_scope_and_flags_retained(self):
        def lock(flag):
            return {"lockfileVersion": 3, "packages": {"": {"devDependencies": {"example": "1.0.0"}}, "node_modules/example": {"version": "1.0.0", "resolved": "https://registry.npmjs.org/example/-/example-1.0.0.tgz", **flag}}}
        rows, _ = osv.packages(None, {"packages": {}}, [("one", lock({"dev": True})), ("two", lock({"optional": True}))])
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(rows[0]["scopes"]), 2)
        self.assertIn("devDependencies: dev", rows[0]["scopes"][0])
        self.assertIn("optional", rows[0]["scopes"][1])
        altered = lock({}); altered["packages"]["node_modules/example"]["resolved"] = "https://registry.npmjs.org/other/-/other-1.0.0.tgz"
        with self.assertRaisesRegex(ValueError, "tarball identity"):
            osv.packages(None, {"packages": {}}, [("one", altered)])

    def test_ruby_public_source_and_checksum_section(self):
        ruby = "GEM\n  remote: https://rubygems.org/\n  specs:\n    example (1.0.0)\n    other (2.0.0)\n\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n  example (= 1.0.0)\n\nCHECKSUMS\n  example (1.0.0) sha256=abc\n\nBUNDLED WITH\n   2.7.2\n"
        rows, _ = osv.packages(None, {"packages": {}}, [], ruby)
        self.assertEqual([r["scopes"][0] for r in rows], ["Gemfile.lock: direct", "Gemfile.lock: transitive"])
        for invalid in [ruby.replace("https://rubygems.org/", "https://private.example/"), ruby.replace("PLATFORMS\n", "GIT\n\nPLATFORMS\n"), ruby.replace("    other (2.0.0)", "    bad malformed")]:
            with self.assertRaises(ValueError):
                osv.packages(None, {"packages": {}}, [], invalid)

    def test_redirect_refused_before_follow_and_record_id_is_bound(self):
        with self.assertRaisesRegex(ValueError, "redirects"):
            osv.RefuseRedirect().redirect_request(None, None, 307, "redirect", {}, "https://other.example/")
        with patch.object(osv, "read_osv", return_value=({"id": "different"}, b"{}")):
            with self.assertRaisesRegex(ValueError, "identity mismatch"):
                osv.fetch_record("GHSA-example")
        with self.assertRaisesRegex(ValueError, "identifier"):
            osv.fetch_record("../private")

    def test_duplicate_json_and_expired_deadline_fail_closed(self):
        with self.assertRaisesRegex(ValueError, "Duplicate JSON"):
            osv.unique_json(b'{"results":[],"results":[]}')
        with self.assertRaisesRegex(ValueError, "Duplicate YAML"):
            osv.unique_yaml(b'packages: {}\npackages: {}\n')
        with tempfile.TemporaryDirectory() as path:
            with self.assertRaisesRegex(ValueError, "time budget"):
                osv.scan([{"package": {"ecosystem": "Pub", "name": "x"}, "version": "1"}], Path(path), lambda _: self.fail("no request allowed"), deadline=0)

    def test_detail_deduplicates_and_detects_modified_drift(self):
        findings = [[{"id": "GHSA-one", "modified": "2026-01-01T00:00:00Z"}], [{"id": "GHSA-one", "modified": "2026-01-01T00:00:00Z"}]]
        calls = []
        def fetch(identifier):
            calls.append(identifier)
            record = {"id": identifier, "modified": "2026-01-01T00:00:00Z"}
            return record, json.dumps(record).encode()
        with tempfile.TemporaryDirectory() as path:
            details = osv.details(findings, Path(path), float("inf"), fetch)
            self.assertEqual(calls, ["GHSA-one"])
            self.assertEqual(len(details), 1)
        with tempfile.TemporaryDirectory() as path:
            with self.assertRaisesRegex(ValueError, "changed"):
                osv.details(findings, Path(path), float("inf"), lambda _: ({"id": "GHSA-one", "modified": "2026-01-02T00:00:00Z"}, b'{}'))
            self.assertTrue((Path(path) / "record-GHSA-one.json").exists())

    def test_reviewed_payload_must_match_exact_order_and_public_fields(self):
        inventory = [{"package": {"ecosystem": "Pub", "name": "x"}, "version": "1", "scopes": ["local only"]}]
        osv.verify_reviewed(inventory, b'{"queries":[{"package":{"ecosystem":"Pub","name":"x"},"version":"1"}]}')
        with self.assertRaisesRegex(ValueError, "reviewed payload"):
            osv.verify_reviewed(inventory, b'{"queries":[{"package":{"ecosystem":"Pub","name":"x"},"version":"2"}]}')
        with self.assertRaisesRegex(ValueError, "reviewed payload"):
            osv.verify_reviewed(inventory, b'{"queries":[{"package":{"ecosystem":"Pub","name":"x"},"version":"1","scopes":["local only"]}]}')

    def test_shared_response_budget_covers_both_query_and_detail(self):
        budget = [osv.MAX_TOTAL_RESPONSE_BYTES - 2]
        osv.charge_response(b"ab", budget)
        with self.assertRaisesRegex(ValueError, "Total advisory response budget"):
            osv.charge_response(b"c", budget)

    def test_nonadjacent_token_cycles_and_repeated_ids_fail_closed(self):
        inventory = [{"package": {"ecosystem": "Pub", "name": "x"}, "version": "1"}]
        replies = iter([{"next_page_token": "a"}, {"next_page_token": "b"}, {"next_page_token": "a"}])
        with tempfile.TemporaryDirectory() as path:
            with self.assertRaisesRegex(ValueError, "repeated pagination"):
                osv.scan(inventory, Path(path), lambda _: {"results": [next(replies)]})
        replies = iter([{"vulns": [{"id": "GHSA-one"}], "next_page_token": "a"}, {"vulns": [{"id": "GHSA-one"}]}])
        with tempfile.TemporaryDirectory() as path:
            with self.assertRaisesRegex(ValueError, "Repeated advisory"):
                osv.scan(inventory, Path(path), lambda _: {"results": [next(replies)]})

    def test_tenth_page_may_complete_but_eleventh_is_refused(self):
        inventory = [{"package": {"ecosystem": "Pub", "name": "x"}, "version": "1"}]
        def run(complete):
            count = 0
            def query(_):
                nonlocal count
                count += 1
                return {"results": [{} if complete and count == 10 else {"next_page_token": str(count)}]}
            with tempfile.TemporaryDirectory() as path:
                return osv.scan(inventory, Path(path), query)
        self.assertEqual(run(True), [[]])
        with self.assertRaisesRegex(ValueError, "pagination did not complete"):
            run(False)

    def test_modified_timestamp_precision_and_observable_drift(self):
        comparison = osv.compare_modified("2026-10-27T19:15:22.407771Z", "2026-10-27T19:15:22.407771210Z")
        self.assertEqual(comparison["shared_fractional_digits"], 6)
        self.assertFalse(comparison["finer_precision_or_unchanged_record_proven"])
        self.assertTrue(osv.compare_modified("2026-10-27T19:15:22.407771Z", "2026-10-27T19:15:22.407771999Z")["consistent_to_common_precision"])
        for invalid in ["2026-02-30T19:15:22Z", "2026-10-27T19:15:22+00:00", "2026-10-27T19:15:22.1234567890Z"]:
            with self.assertRaisesRegex(ValueError, "Invalid advisory modification timestamp"):
                osv.compare_modified(invalid, "2026-10-27T19:15:22Z")
        for changed in ["2026-10-27T19:15:22.407772Z", "2026-10-27T19:15:23.407771Z"]:
            with self.assertRaisesRegex(ValueError, "changed"):
                osv.compare_modified("2026-10-27T19:15:22.407771Z", changed)


if __name__ == "__main__":
    unittest.main()
