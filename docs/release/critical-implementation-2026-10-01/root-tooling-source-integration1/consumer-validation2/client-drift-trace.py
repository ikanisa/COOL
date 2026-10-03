#!/usr/bin/env python3
"""Repair one missing retained trace, using the unchanged maintained case."""
from pathlib import Path
import json
import sys
import unittest

ROOT = Path(sys.argv[1]).resolve()
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts/tests"))
import supabase_delivery_contract_test as delivery

SERVER_QUERY = "select current_setting('server_version_num')::integer as server_version_num;"


class ClientDriftTrace(delivery.SupabaseDeliveryContractTest):
    def run_deploy(self):
        self.actual_result = super().run_deploy()
        return self.actual_result

    def test_actual_client_drift_after_observed_dry_run_blocks_first_write(self):
        # Execute the original maintained method with all its assertions.
        super().test_postgres_client_drift_after_dry_run_stops_first_write()
        calls = self.calls()
        events_path = Path(self.env["MOCK_EVENTS"])
        events = [json.loads(row) for row in events_path.read_text().splitlines()] if events_path.exists() else []
        receipt = self.receipt()
        # Capture inside the test body, before registered fixture cleanup.
        (OUT / "client-drift-observed-trace.json").write_text(json.dumps({
            "exit_code": self.actual_result.returncode,
            "stderr": self.actual_result.stderr,
            "calls": calls, "events": events, "controller_receipt": receipt,
            "capture_position": "inside test body, before unittest cleanups",
            "synthetic_target_and_approval_only": True,
        }, indent=2) + "\n")
        self.assertIn(["db", "push", "--dry-run", "--skip-vault"], calls)
        self.assertTrue(any(e == {"kind": "query", "query": SERVER_QUERY} for e in events))
        self.assertIn("PG_CLIENT_CHANGED_AFTER_ADMISSION", self.actual_result.stderr)
        self.assertFalse(any(c[:2] in (["functions", "deploy"], ["functions", "delete"])
                             or c[:2] == ["db", "push"] and "--dry-run" not in c for c in calls))
        self.assertEqual(receipt["automatic_retries"], 0)
        self.assertFalse(receipt["production_release_accepted"])


if __name__ == "__main__":
    suite = unittest.TestSuite([ClientDriftTrace("test_actual_client_drift_after_observed_dry_run_blocks_first_write")])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
