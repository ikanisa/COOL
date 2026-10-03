#!/usr/bin/env python3
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("collect_ci_policy", ROOT / "scripts/qa/collect_ci_policy.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class CollectCiPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflows = {p.name: policy.read_workflow(p) for p in (ROOT / ".github/workflows").glob("*.yml")}

    def setUp(self):
        self.workflows = copy.deepcopy(self.__class__.workflows)

    def codes(self):
        return {f["code"] for f in policy.validate_workflows(self.workflows)}

    def checkout(self):
        return self.workflows["ci.yml"]["jobs"]["repo-hygiene"]["steps"][0]

    def test_current_declared_boundary_is_valid(self):
        self.assertEqual(policy.validate_workflows(self.workflows), [])

    def test_missing_and_enabled_persisted_credentials_fail(self):
        for value in [None, True, "false", "${{ inputs.persist }}"]:
            with self.subTest(value=value):
                self.checkout()["with"]["persist-credentials"] = value
                self.assertIn("CI_CHECKOUT_CREDENTIAL_PERSISTENCE_FORBIDDEN", self.codes())

    def test_mutable_action_tag_fails(self):
        self.checkout()["uses"] = "actions/checkout@v4"
        self.assertIn("CI_ACTION_COMMIT_PIN_REQUIRED", self.codes())

    def test_privileged_pull_request_trigger_fails(self):
        self.workflows["ci.yml"].setdefault("true", {})["pull_request_target"] = None
        self.assertIn("CI_PRIVILEGED_PR_TRIGGER_FORBIDDEN", self.codes())

    def test_default_token_write_fails(self):
        self.workflows["ci.yml"]["permissions"]["contents"] = "write"
        self.assertIn("CI_DEFAULT_CONTENTS_READ_REQUIRED", self.codes())

    def test_missing_or_invalid_deadline_fails(self):
        for value in [None, True, 0, 61, "15"]:
            self.workflows["ci.yml"]["jobs"]["repo-hygiene"]["timeout-minutes"] = value
            self.assertIn("CI_JOB_DEADLINE_REQUIRED", self.codes())

    def test_codeql_bridge_and_lock_must_cover_both_events(self):
        events = self.workflows["codeql.yml"].get("true", self.workflows["codeql.yml"].get("on"))
        for event in ["push", "pull_request"]:
            for required in ["tools/collect-notification-mcp/**", "tools/collect-notification-mcp/pnpm-lock.yaml"]:
                original = list(events[event]["paths"])
                events[event]["paths"].remove(required)
                self.assertIn("CI_CODEQL_BRIDGE_AND_LOCK_TRIGGER_REQUIRED", self.codes())
                events[event]["paths"] = original

    def test_mcp_unfrozen_or_missing_checks_fail(self):
        lane = self.workflows["ci.yml"]["jobs"]["notification-operator"]
        lane["steps"] = [s for s in lane["steps"] if s.get("run") != "pnpm install --frozen-lockfile --ignore-scripts"]
        self.assertIn("CI_BRIDGE_FROZEN_CHECK_AND_TEST_REQUIRED", self.codes())

    def test_node_and_package_manager_pins_fail_when_changed(self):
        steps = self.workflows["ci.yml"]["jobs"]["notification-operator"]["steps"]
        next(s for s in steps if str(s.get("uses", "")).startswith("actions/setup-node@"))["with"]["node-version"] = "24"
        next(s for s in steps if s.get("run") == "npm install --global pnpm@10.33.2 --ignore-scripts")["run"] = "npm install --global pnpm"
        self.assertIn("CI_BRIDGE_NODE_PIN_REQUIRED", self.codes())
        self.assertIn("CI_BRIDGE_PACKAGE_MANAGER_PIN_REQUIRED", self.codes())

    def test_safe_parser_rejects_aliases_and_malformed_yaml_without_echo(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "workflow.yml"
            for contents in ["x: &s secret\ny: *s\n", "SECRET_CREDENTIAL: [\n"]:
                path.write_text(contents)
                with self.assertRaisesRegex(policy.PolicyInputError, "^CI_POLICY_YAML_INVALID$"):
                    policy.read_workflow(path)

    def test_missing_parser_and_symlink_fail_closed(self):
        with patch.object(policy.shutil, "which", return_value=None):
            with self.assertRaisesRegex(policy.PolicyInputError, "CI_POLICY_RUBY_REQUIRED"):
                policy.read_workflow(ROOT / ".github/workflows/ci.yml")
        with tempfile.TemporaryDirectory() as folder:
            link = Path(folder) / "workflow.yml"
            link.symlink_to(ROOT / ".github/workflows/ci.yml")
            with self.assertRaisesRegex(policy.PolicyInputError, "CI_POLICY_WORKFLOW_INPUT_INVALID"):
                policy.read_workflow(link)

    def test_local_pass_cannot_attest_hosted_security_or_mutation(self):
        report = policy.inspect(ROOT)
        self.assertEqual(report["status"], "pass")
        self.assertIs(report["hosted_enforcement_verified"], False)
        self.assertIs(report["security_scan_execution_verified"], False)
        self.assertIs(report["remote_settings_changed"], False)


if __name__ == "__main__":
    unittest.main()
