#!/usr/bin/env python3
"""Verify workflow callers retain the source/effect separation; not hosted CI."""
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]


class WorkflowTest(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.load((ROOT / ".github/workflows/ios-app-store.yml").read_text(), Loader=yaml.BaseLoader)
        self.verify = self.workflow["jobs"]["verify-source"]
        self.delivery = self.workflow["jobs"]["scoped-delivery"]

    def test_credential_free_verification_precedes_protected_effect_job(self):
        self.assertNotIn("secrets.", str(self.verify))
        self.assertEqual(self.delivery["needs"], "verify-source")
        self.assertIn("!= 'unsigned_candidate'", self.delivery["if"])
        for environment in ("collect-ios-signing", "collect-ios-testflight", "collect-ios-metadata", "collect-ios-privacy"):
            self.assertIn(environment, self.delivery["environment"])
        verification = "\n".join(step.get("run", "") for step in self.verify["steps"])
        self.assertIn('test "$GITHUB_REF" = refs/heads/main', verification)
        self.assertIn('test "$GITHUB_SHA" = "$COLLECT_IOS_EXPECTED_COMMIT"', verification)
        self.assertIn("verify-environment", verification)

    def test_source_and_live_policy_preflights_precede_every_secret_step(self):
        steps = self.delivery["steps"]
        prepare = next(index for index, step in enumerate(steps) if "ios_delivery_guard.py prepare" in step.get("run", ""))
        policy = next(index for index, step in enumerate(steps) if "verify-environment" in step.get("run", ""))
        for index, step in enumerate(steps):
            if "secrets." in str(step):
                self.assertGreater(index, prepare)
                self.assertGreater(index, policy)
        certificate = next(step for step in steps if "APPLE_CERTIFICATE_BASE64" in step.get("env", {}))
        self.assertIn("== 'signed_candidate'", certificate["if"])
        self.assertIn("import-signing", certificate["run"])
        cleanup = next(step for step in steps if "cleanup-signing" in step.get("run", ""))
        self.assertIn("always()", cleanup["if"])

    def test_external_record_cannot_mutate_reviewed_source_or_trigger_shell_expansion(self):
        inputs = self.workflow["on"]["workflow_dispatch"]["inputs"]
        self.assertIn("approval_record", inputs)
        self.assertNotIn("approval_file", inputs)
        for job in (self.verify, self.delivery):
            capture = next(step for step in job["steps"] if "REVIEWED_APPROVAL_RECORD" in step.get("env", {}))
            self.assertIn('os.environ["REVIEWED_APPROVAL_RECORD"].encode', capture["run"])
            self.assertNotIn("${{ inputs.", capture["run"])
            self.assertIn("$RUNNER_TEMP/ios-approval.json", capture["run"])
        self.assertNotIn("runner.", str(self.workflow["env"]))

    def test_signed_candidate_and_approved_upload_are_different_operations(self):
        choices = self.workflow["on"]["workflow_dispatch"]["inputs"]["operation"]["options"]
        self.assertEqual(set(choices), {"unsigned_candidate", "signed_candidate", "testflight_internal", "metadata", "screenshots", "privacy_public"})
        self.assertNotIn("public_release", choices)
        steps = self.delivery["steps"]
        candidate = next(step for step in steps if step.get("uses", "").startswith("actions/upload-artifact@"))
        self.assertIn("success()", candidate["if"])
        self.assertIn("== 'signed_candidate'", candidate["if"])
        retrieve = next(step for step in steps if "gh run download" in step.get("run", ""))
        self.assertIn("== 'testflight_internal'", retrieve["if"])
        self.assertIn("run['head_sha']", retrieve["run"])
        self.assertIn("check --operation testflight_internal", retrieve["run"])
        upload = next(step for step in steps if step.get("run") == "bundle exec fastlane ios upload_review_build")
        self.assertIn("== 'testflight_internal'", upload["if"])
        self.assertNotIn("COLLECT_REVIEW_OTP", upload["env"])
        self.assertFalse(any("APPLE_CERTIFICATE" in str(step.get("env", {})) and "testflight" in step.get("if", "") for step in steps))

    def test_resolution_and_build_preserve_lock_enforcement(self):
        fastfile = (ROOT / "fastlane/Fastfile").read_text()
        self.assertNotIn('flutter pub get")', fastfile)
        self.assertIn("flutter pub get --enforce-lockfile", fastfile)
        self.assertIn('"--no-pub"', fastfile)
        for job in (self.verify, self.delivery):
            for step in job["steps"]:
                for line in step.get("run", "").splitlines():
                    if "flutter pub get" in line:
                        self.assertIn("--enforce-lockfile", line)


if __name__ == "__main__":
    unittest.main(verbosity=2)
