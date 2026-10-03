#!/usr/bin/env python3
"""Affected actual management consumer and transaction-boundary refusals."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv[1]).resolve()
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts/tests"))
import supabase_delivery_contract_test as delivery

SERVER_QUERY = "select current_setting('server_version_num')::integer as server_version_num;"


class ActualManagementConsumer(delivery.SupabaseDeliveryContractTest):
    def run_deploy(self):
        result = super().run_deploy()
        path = Path(self.env["MOCK_EVENTS"])
        events = [json.loads(row) for row in path.read_text().splitlines()] if path.exists() else []
        receipt_path = Path(self.env["COLLECT_BACKEND_RECEIPT"])
        receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
        (OUT / "actual-management.trace.json").write_text(json.dumps({
            "exit_code": result.returncode, "calls": self.calls(), "events": events,
            "controller_receipt": receipt, "stdout": result.stdout, "stderr": result.stderr,
            "capture_position": "inside run_deploy before the test returns and cleanup"}, indent=2) + "\n")
        return result

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
        # The complete original failed method above is unchanged. Add exact
        # current-chain readback assertions without relaxing that method.
        expected_versions = [p.name.split("_", 1)[0] for p in sorted((self.root / "supabase/migrations").glob("*.sql"))]
        receipt = self.receipt()
        self.assertEqual(len(expected_versions), 209)
        self.assertEqual(expected_versions[-2:], ["20261002080000", "20261002090000"])
        self.assertTrue(receipt["readback"]["migrations"]["matches_candidate"])
        self.assertEqual(receipt["readback"]["migrations"]["versions"], expected_versions)
        self.assertFalse(receipt["production_release_accepted"])
        self.assertFalse(receipt["human_identity_authenticated"])
        second_write = [e["query"] for e in events if "insert into supabase_migrations.schema_migrations" in e.get("query", "")][-1]
        self.assertIn("-- Specific governed controls", second_write)


class TransactionBoundaryRefusal(unittest.TestCase):
    def refuse_extra_boundary(self, boundary):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp).resolve()
            migrations = base / "migrations"
            migrations.mkdir()
            migration = migrations / "20990101000000_private_extra_boundary.sql"
            migration.write_text("-- preserved private comment\nbegin;\nselect 1;\n" + boundary + ";\nselect 2;\ncommit;\n")
            calls = base / "calls.jsonl"
            writes = base / "writes.sql"
            command = '''. "$1"
supabase_management_query() {
  printf '%s\n' "$1" >> "$PRIVATE_QUERY_LOG"
  if [[ "$1" != 'select version, name from supabase_migrations.schema_migrations order by version;' ]]; then
    printf '%s\n' "$1" >> "$PRIVATE_WRITE_LOG"
  fi
  printf '[]\n'
}
supabase_management_query_rows() { printf '1\n'; }
supabase_management_apply_pending_migrations "$2"
'''
            env = dict(os.environ, PRIVATE_QUERY_LOG=str(calls), PRIVATE_WRITE_LOG=str(writes))
            result = subprocess.run(["/bin/bash", "-c", command, "bash", str(ROOT / "scripts/supabase_cli_helpers.sh"), str(migrations)],
                                    env=env, capture_output=True, text=True, timeout=30)
            queries = calls.read_text().splitlines() if calls.exists() else []
            (OUT / ("extra-" + boundary.lower() + ".trace.json")).write_text(json.dumps({
                "exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr,
                "query_calls": queries, "write_observed": writes.exists(),
                "source": "actual maintained helper; only query transports overridden locally",
                "capture_position": "inside the test body before TemporaryDirectory exits",
            }, indent=2) + "\n")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Migration still contains a transaction terminator after normalization", result.stderr)
            self.assertEqual(queries, ["select version, name from supabase_migrations.schema_migrations order by version;"])
            self.assertFalse(writes.exists())

    def test_extra_begin_refuses_before_any_write(self):
        self.refuse_extra_boundary("begin")

    def test_extra_commit_refuses_before_any_write(self):
        self.refuse_extra_boundary("commit")


if __name__ == "__main__":
    suite = unittest.TestSuite([
        ActualManagementConsumer("test_management_fallback_checks_exact_version_before_each_sql_write"),
        TransactionBoundaryRefusal("test_extra_begin_refuses_before_any_write"),
        TransactionBoundaryRefusal("test_extra_commit_refuses_before_any_write"),
    ])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
