#!/usr/bin/env python3
"""Fail-closed acceptance tests for the root local database evidence recorder.

These tests never connect to a database. They exercise corruption of command
status, fingerprints and allowed change scopes before a PASS can be recorded.
"""
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "offline_recorder", Path(__file__).with_name("local_offline_verification.py")
)
RECORDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RECORDER)


class EvidenceAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        (self.output / "stdout").write_text("synthetic test output\n")
        (self.output / "stderr").write_text("")
        RECORDER.save(self.output / "checkpoint.json", {"sql_return_code": 0})
        self.before = {
            "tables": {
                "public.payment_events": {"rows": 2, "sha256": "a" * 64},
                "collect_hybrid.roster_resource_policy": {"rows": 1, "sha256": "b" * 64},
                "supabase_migrations.schema_migrations": {"rows": 146, "sha256": "c" * 64},
            },
            "controls_sha256": "d" * 64,
            "cron_jobs": [{"id": 1, "metadata_sha256": "e" * 64}],
            "cron_history": {"rows": 0, "sha256": "f" * 64},
        }

    def run_finish(self, after, *, unchanged=True, allowed=()):
        with contextlib.redirect_stdout(io.StringIO()):
            RECORDER.finish(self.output, self.before, after, unchanged=unchanged,
                            expected_changed_tables=allowed)

    def assert_rejected(self, after, *, unchanged=True, allowed=()):
        with self.assertRaises(RuntimeError):
            self.run_finish(after, unchanged=unchanged, allowed=allowed)
        result = json.loads((self.output / "result.json").read_text())
        self.assertEqual(result["status"], "fail")
        self.assertTrue(result["failures"])

    def test_exact_restoration_is_accepted(self):
        self.run_finish(copy.deepcopy(self.before))
        self.assertEqual(json.loads((self.output / "result.json").read_text())["status"], "pass")

    def test_missing_command_status_cannot_be_promoted_to_pass(self):
        RECORDER.save(self.output / "checkpoint.json", {})
        self.assert_rejected(copy.deepcopy(self.before))

    def test_failed_command_cannot_be_promoted_even_when_rows_restore(self):
        RECORDER.save(self.output / "checkpoint.json", {"sql_return_code": 1})
        self.assert_rejected(copy.deepcopy(self.before))

    def test_equal_row_counts_with_changed_content_are_rejected(self):
        after = copy.deepcopy(self.before)
        after["tables"]["public.payment_events"]["sha256"] = "0" * 64
        self.assert_rejected(after)

    def test_catalog_or_scheduler_drift_invalidates_rollback(self):
        for key in ("controls_sha256", "cron_jobs", "cron_history"):
            with self.subTest(key=key):
                after = copy.deepcopy(self.before)
                after[key] = "changed"
                self.assert_rejected(after)

    def test_unrelated_change_is_rejected_during_expected_mutation(self):
        after = copy.deepcopy(self.before)
        after["tables"]["public.payment_events"]["sha256"] = "0" * 64
        self.assert_rejected(after, unchanged=False,
                             allowed=("collect_hybrid.roster_resource_policy",))

    def test_only_declared_table_changes_are_allowed_for_mutation(self):
        after = copy.deepcopy(self.before)
        after["tables"]["collect_hybrid.roster_resource_policy"]["sha256"] = "0" * 64
        self.run_finish(after, unchanged=False,
                        allowed=("collect_hybrid.roster_resource_policy",))
        result = json.loads((self.output / "result.json").read_text())
        self.assertFalse(result["unchanged"])
        self.assertTrue(result["unaffected_tables_preserved"])
        self.assertEqual(result["status"], "pass")

    def test_missing_original_table_is_rejected(self):
        after = copy.deepcopy(self.before)
        del after["tables"]["public.payment_events"]
        self.assert_rejected(after, unchanged=False)


if __name__ == "__main__":
    unittest.main()
