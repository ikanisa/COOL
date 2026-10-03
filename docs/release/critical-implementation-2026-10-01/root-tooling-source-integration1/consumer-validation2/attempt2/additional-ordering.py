#!/usr/bin/env python3
"""Actual maintained controller/readiness with only synthetic transports."""
from pathlib import Path
import json
import subprocess
import sys
import unittest

ROOT = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(ROOT / "scripts/tests"))
import supabase_delivery_contract_test as delivery

SERVER_QUERY = "select current_setting('server_version_num')::integer as server_version_num;"


class AdditionalOrdering(delivery.SupabaseDeliveryContractTest):
    def test_full_staging_migrations_and_thirteen_functions_use_reviewed_export(self):
        self.reviewed_fixture(["migrations", "retired_functions", "edge_functions"], "staging")
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.receipt()
        self.assertEqual(receipt["status"], "delivered_and_read_back")
        self.assertEqual(receipt["target"]["environment"], "staging")
        self.assertTrue(receipt["readback"]["migrations"]["matches_candidate"])
        self.assertEqual(receipt["readback"]["postgresql"]["server_version_num"], 170006)
        self.assertFalse(receipt["production_release_accepted"])
        self.assertFalse(receipt["human_identity_authenticated"])
        deployments = [args for args in self.calls() if args[:2] == ["functions", "deploy"]]
        self.assertEqual(len(deployments), 13)
        self.assertEqual(self.calls().count(["db", "push", "--skip-vault"]), 1)
        traces = [json.loads(row) for row in Path(self.env["MOCK_CWD"]).read_text().splitlines()]
        self.assertTrue(all(t["cwd"] != str(self.root) and t["link"] == delivery.REF for t in traces))
        self.assertFalse((self.root / "readiness-strict.txt").exists())

    def test_management_fallback_checks_exact_version_before_each_sql_write(self):
        self.pending_history(2)
        self.env["MOCK_CONNECTIVITY_FAILURE"] = "1"
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = [json.loads(row) for row in Path(self.env["MOCK_EVENTS"]).read_text().splitlines()]
        previous_query = None
        writes = 0
        for event in events:
            if event["kind"] != "query":
                continue
            query = event["query"]
            if "insert into supabase_migrations.schema_migrations" in query:
                self.assertEqual(previous_query, SERVER_QUERY)
                writes += 1
            previous_query = query
        self.assertEqual(writes, 2)
        self.assertEqual(self.receipt()["readback"]["postgresql"]["server_version_num"], 170006)
        self.assertEqual(self.receipt()["automatic_retries"], 0)

    def readiness(self, version, wrong_manifest_project=False):
        source = (ROOT / "scripts/supabase_production_readiness.sh").read_text().rsplit('main "$@"', 1)[0]
        target = self.root / "scripts/readiness-functions.sh"
        self.executable(target, source)
        if wrong_manifest_project:
            manifest = json.loads(self.pg_manifest_path.read_text())
            manifest["targets"][0]["project_ref"] = "z" * 20
            manifest["targets"][0]["host"] = "db." + "z" * 20 + ".supabase.co"
            self.pg_manifest_path.write_bytes(self.candidate.canonical(manifest))
            self.env["COLLECT_POSTGRES_ADMISSION_SHA256"] = self.candidate.sha(self.pg_manifest_path.read_bytes())
        query_log = self.base / "readiness-query.json"
        command = '. "$1"; db_query() { printf "%s" "$1" > "$MOCK_READINESS_QUERY"; printf "%s\\n" "$MOCK_READINESS_VERSION"; }; main'
        env = dict(self.env, MOCK_READINESS_QUERY=str(query_log), MOCK_READINESS_VERSION=version)
        result = subprocess.run(["bash", "-c", command, "bash", str(target)], env=env,
                                capture_output=True, text=True, timeout=30)
        return result, query_log

    def test_readiness_unknown_manifest_project_refuses_before_first_query(self):
        result, query_log = self.readiness("170006", wrong_manifest_project=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(query_log.exists())
        self.assertEqual(self.calls(), [])

    def test_readiness_incompatible_server_stops_after_exact_read_before_later_requests(self):
        result, query_log = self.readiness("150012")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(query_log.read_text(), SERVER_QUERY)
        self.assertEqual(self.calls(), [])
        self.assertIn("PostgreSQL admission or server matrix refused", result.stderr)


if __name__ == "__main__":
    suite = unittest.TestSuite(AdditionalOrdering(name) for name in (
        "test_full_staging_migrations_and_thirteen_functions_use_reviewed_export",
        "test_management_fallback_checks_exact_version_before_each_sql_write",
        "test_readiness_unknown_manifest_project_refuses_before_first_query",
        "test_readiness_incompatible_server_stops_after_exact_read_before_later_requests",
    ))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
