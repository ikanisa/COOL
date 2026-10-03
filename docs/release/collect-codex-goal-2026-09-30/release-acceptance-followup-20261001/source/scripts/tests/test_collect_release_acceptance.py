#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("collect_release_acceptance", ROOT / "scripts/qa/collect_release_acceptance.py")
acceptance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acceptance)


class ReleaseAcceptanceTest(unittest.TestCase):
    def inputs(self):
        return ({"tasks": [{"id": f"C{i:02}", "task": "synthetic scope", "closure": "actual proof", "status": "in_progress", "master_ids": ["G01"]} for i in range(1, 37)]},
                {"items": [{"id": "G01", "open": True}, {"id": "F01", "open": False}]},
                {"collect_notification_health": "OPERATOR_SESSION_REAUTHENTICATION_REQUIRED", "get_collect_health": "COLLECT_CURRENT_USER_SESSION_REQUIRED"})

    def test_authorization_cannot_create_identity_or_delivery_proof(self):
        result = acceptance.acceptance_state(preparation_authorized=True, proof_verified=False)
        self.assertEqual(result["acceptance"], "open")
        self.assertIs(result["authorization_substitutes_for_identity_device_delivery_or_security_proof"], False)

    def test_authorization_never_closes_master_or_feature_gates(self):
        progress, master, observed = self.inputs()
        report = acceptance.assemble(progress, master, observed, True)
        self.assertEqual(report["original_master_open_ids"], ["G01"])
        self.assertEqual(report["open_task_acceptance_count"], 36)
        self.assertIs(report["feature_and_master_counts_are_additive"], False)
        self.assertEqual(report["release_decision"], "NO_GO")
        self.assertTrue(all(r["preparation_authorized"] and r["acceptance"] == "open" for r in report["tasks"]))

    def test_missing_duplicate_or_new_feature_id_fails(self):
        progress, master, observed = self.inputs()
        for changed in [progress["tasks"][:-1], [*progress["tasks"], progress["tasks"][0]], [*progress["tasks"][:-1], {**progress["tasks"][-1], "id": "C37"}]]:
            with self.assertRaisesRegex(ValueError, "ACCEPTANCE_TASK_INVENTORY_INVALID"):
                acceptance.assemble({"tasks": changed}, master, observed, True)

    def test_unknown_master_binding_fails(self):
        progress, master, observed = self.inputs()
        progress["tasks"][0]["master_ids"] = ["G999"]
        with self.assertRaisesRegex(ValueError, "ACCEPTANCE_MASTER_BINDING_INVALID"):
            acceptance.assemble(progress, master, observed, True)

    def test_raw_error_or_unaudited_success_cannot_become_proof(self):
        progress, master, observed = self.inputs()
        for invalid in ["SECRET_TOKEN +250788123456", "OK", "COLLECT_AUTHORIZATION_REQUIRED"]:
            observed["get_collect_health"] = invalid
            with self.assertRaisesRegex(ValueError, "ACCEPTANCE_OBSERVATION_INVALID"):
                acceptance.assemble(progress, master, observed, True)

    def test_missing_observation_fails(self):
        progress, master, observed = self.inputs()
        observed.pop("get_collect_health")
        with self.assertRaisesRegex(ValueError, "ACCEPTANCE_OBSERVATION_INVALID"):
            acceptance.assemble(progress, master, observed, False)


if __name__ == "__main__":
    unittest.main()
