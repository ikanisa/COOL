#!/usr/bin/env python3
"""Run selected actual maintained consumers, never a real provider target."""
from pathlib import Path
import json
import sys
import time
import unittest

ROOT = Path(sys.argv[1]).resolve()
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts/tests"))
import supabase_delivery_contract_test as delivery

NAMES = (
    "test_all_thirteen_deploy_with_manifest_auth_modes_and_strict_readiness",
    "test_wrong_cli_pin_stops_before_any_project_operation",
    "test_missing_and_swapped_companion_are_refused_before_project_calls",
    "test_unapproved_companion_override_is_refused",
    "test_companion_drift_after_preflight_stops_before_first_write",
    "test_wrong_approval_hash_blocks_before_any_remote_call",
    "test_wrong_target_environment_and_url_are_refused",
    "test_wrong_source_approval_binding_is_refused",
    "test_dirty_candidate_and_unlisted_candidate_source_are_refused",
    "test_stale_worktree_helper_and_added_backend_source_are_refused",
    "test_missing_transitive_module_is_refused_before_project_calls",
    "test_frozen_closure_failure_and_wrong_deno_pin_have_no_remote_effect",
    "test_mid_run_worktree_drift_stops_before_first_write",
    "test_mid_run_execution_drift_and_unlisted_runtime_metadata_stop_writes",
    "test_staging_edge_scope_executes_export_without_production_acceptance",
    "test_legacy_edge_only_approval_succeeds_without_postgres_configuration",
    "test_legacy_edge_only_shape_still_refuses_changed_target_before_requests",
    "test_database_approval_without_postgres_binding_refuses_before_requests",
    "test_wrong_postgres_manifest_hash_and_override_refuse_before_requests",
    "test_postgres_client_byte_drift_refuses_before_requests",
    "test_incompatible_server_is_observed_by_read_only_query_before_any_write",
    "test_postgres_manifest_drift_after_dry_run_stops_first_write",
    "test_postgres_client_drift_after_dry_run_stops_first_write",
    "test_server_drift_after_dry_run_stops_first_write",
    "test_server_read_precedes_every_release_mutation_and_management_migration",
    "test_main_binary_drift_after_dry_run_stops_first_write",
    "test_make_tool_defaults_use_path_and_keep_explicit_overrides",
)


class ReceiptResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.receipts = []

    def startTest(self, test):
        self.started = time.monotonic()
        super().startTest(test)

    def record(self, test, outcome):
        evidence = {}
        for key in ("MOCK_CALLS", "MOCK_EVENTS", "MOCK_PROBES", "MOCK_CWD"):
            path = Path(getattr(test, "env", {}).get(key, "/nonexistent-private-proof"))
            evidence[key] = [json.loads(row) for row in path.read_text().splitlines()] if path.is_file() else []
        receipt_path = Path(getattr(test, "env", {}).get("COLLECT_BACKEND_RECEIPT", "/nonexistent-private-proof"))
        evidence["controller_receipt"] = json.loads(receipt_path.read_text()) if receipt_path.is_file() else None
        evidence_dir = OUT / "case-evidence"
        evidence_dir.mkdir(exist_ok=True)
        (evidence_dir / (test._testMethodName + ".json")).write_text(json.dumps(evidence, indent=2) + "\n")
        self.receipts.append({"test": test.id(), "outcome": outcome,
                              "elapsed_seconds": round(time.monotonic() - self.started, 3),
                              "evidence": "case-evidence/" + test._testMethodName + ".json"})
        (OUT / "consumer-case-results.json").write_text(json.dumps(self.receipts, indent=2) + "\n")

    def addSuccess(self, test):
        self.record(test, "pass")
        super().addSuccess(test)

    def addFailure(self, test, err):
        self.record(test, "failure")
        super().addFailure(test, err)

    def addError(self, test, err):
        self.record(test, "error")
        super().addError(test, err)


if __name__ == "__main__":
    suite = unittest.TestSuite(delivery.SupabaseDeliveryContractTest(name) for name in NAMES)
    result = unittest.TextTestRunner(verbosity=2, resultclass=ReceiptResult).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
