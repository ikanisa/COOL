#!/usr/bin/env python3
"""Verify workflow callers retain the source/effect separation; not hosted CI."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile
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

    def test_unsigned_and_signed_builds_share_required_public_supabase_profile(self):
        public = self.workflow["env"]
        self.assertEqual(public["COLLECT_BACKEND"], "supabase")
        self.assertEqual(public["SUPABASE_URL"], "https://rrlduytparvsjfmegalh.supabase.co")
        self.assertEqual(public["SUPABASE_API_URL"], "https://platform-admin.collect.ikanisa.com")
        for name in ("COLLECT_DEPLOYMENT_PROFILE", "COLLECT_DEPLOYMENT_PROFILE_SHA256", "COLLECT_SMS_AUTH_ENABLED"):
            self.assertNotIn(name, public)
        mappings = {"COLLECT_DEPLOYMENT_PROFILE": "COLLECT_DEPLOYMENT_PROFILE",
                    "COLLECT_DEPLOYMENT_PROFILE_SHA256": "COLLECT_DEPLOYMENT_PROFILE_SHA256",
                    "COLLECT_SMS_AUTH_ENABLED": "COLLECT_SMS_AUTH_ENABLED", "SUPABASE_URL": "COLLECT_SUPABASE_URL",
                    "SUPABASE_API_URL": "COLLECT_SUPABASE_API_URL", "SUPABASE_ADMIN_API_URL": "COLLECT_SUPABASE_ADMIN_API_URL",
                    "SUPABASE_PUBLISHABLE_KEY": "COLLECT_SUPABASE_PUBLISHABLE_KEY",
                    "AUTH_CAPTCHA_SITE_KEY": "COLLECT_AUTH_CAPTCHA_SITE_KEY",
                    "APP_PUBLIC_URL": "COLLECT_APP_PUBLIC_URL", "ADMIN_APP_URL": "COLLECT_ADMIN_APP_URL"}
        selects = [next(step for step in job["steps"] if step.get("name") == "Select reviewed candidate public configuration")
                   for job in (self.verify, self.delivery)]
        self.assertEqual(selects[0]["if"], "${{ inputs.operation == 'unsigned_candidate' || inputs.operation == 'signed_candidate' }}")
        self.assertEqual(selects[1]["if"], "${{ inputs.operation == 'signed_candidate' }}")
        self.assertEqual(selects[0]["run"], selects[1]["run"])
        for select in selects:
            for name, variable in mappings.items():
                self.assertEqual(select["env"][name], "${{ vars." + variable + " }}")
            self.assertEqual(select["run"], 'python3 -B scripts/qa/ios_delivery_guard.py stage-candidate-config --source "$GITHUB_WORKSPACE"')
        self.assertIn("vars.COLLECT_SUPABASE_PUBLISHABLE_KEY", public["SUPABASE_PUBLISHABLE_KEY"])
        self.assertIn("vars.COLLECT_AUTH_CAPTCHA_SITE_KEY", public["AUTH_CAPTCHA_SITE_KEY"])
        self.assertEqual(public["AUTH_CAPTCHA_ENABLED"], "true")
        self.assertNotIn("secrets.", str(public))
        for job in (self.verify, self.delivery):
            for step in job["steps"]:
                self.assertNotIn("COLLECT_API_URL", step.get("env", {}))
        unsigned = next(step["run"] for step in self.verify["steps"]
                        if "flutter build ios" in step.get("run", ""))
        prepare_index = next(index for index, step in enumerate(self.verify["steps"])
                             if "ios_delivery_guard.py prepare" in step.get("run", ""))
        build_index = next(index for index, step in enumerate(self.verify["steps"])
                           if "flutter build ios" in step.get("run", ""))
        self.assertLess(prepare_index, build_index)
        self.assertLess(unsigned.index("native_build_config.py"), unsigned.index("flutter pub get"))
        self.assertIn('--dart-define-from-file "$PUBLIC_DEFINES"', unsigned)
        self.assertIn("--no-codesign", unsigned)
        fastfile = (ROOT / "fastlane/Fastfile").read_text()
        self.assertIn("review_defines = collect_native_public_defines", fastfile)
        self.assertIn("scripts/qa/native_build_config.py", fastfile)
        self.assertNotIn("Cloudflare production API", fastfile)

    def test_non_build_readiness_uses_real_generic_configuration_without_empty_candidate_flags(self):
        public = self.workflow["env"]
        environment = {name: public[name] for name in ("COLLECT_BACKEND", "SUPABASE_URL", "SUPABASE_API_URL",
                       "SUPABASE_ADMIN_API_URL", "AUTH_CAPTCHA_ENABLED", "AUTH_CAPTCHA_PROVIDER", "APP_PUBLIC_URL", "ADMIN_APP_URL")}
        environment.update(PATH=os.defpath, SUPABASE_PUBLISHABLE_KEY="sb_publishable_syntheticPublicKey1234",
                           AUTH_CAPTCHA_SITE_KEY="synthetic_public_site_key", GOOGLE_AUTH_ENABLED="false")
        readiness = (ROOT / "scripts/ios_app_store_readiness_gate.sh").read_text()
        anchor = "python3 -B - <<'PY' || fail 'The iOS public Supabase configuration or APNs production profile is invalid.'\n"
        self.assertEqual(readiness.count(anchor), 1)
        body = readiness.split(anchor, 1)[1].split("\nPY\n", 1)[0]
        fastfile = (ROOT / "fastlane/Fastfile").read_text()
        for lane in ("upload_metadata_screenshots", "upload_existing_app_store_screenshots", "upload_review_build"):
            self.assertIn("ios_app_store_readiness_gate.sh", fastfile.split("lane :" + lane, 1)[1].split("\n  end", 1)[0])
        for operation in ("metadata", "screenshots", "testflight_internal", "privacy_public"):
            with self.subTest(operation=operation):
                result = subprocess.run([sys.executable, "-B", "-c", body], cwd=ROOT, env=environment,
                                        capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
        for key in ("COLLECT_DEPLOYMENT_PROFILE", "COLLECT_DEPLOYMENT_PROFILE_SHA256", "COLLECT_SMS_AUTH_ENABLED"):
            with self.subTest(empty=key):
                result = subprocess.run([sys.executable, "-B", "-c", body], cwd=ROOT, env={**environment, key: ""},
                                        capture_output=True, text=True, timeout=20)
                self.assertNotEqual(result.returncode, 0)

    def candidate_public_values(self):
        public = self.workflow["env"]
        profile = {"format": "collect.deployment.v1", "id": "synthetic-selfhost", "mode": "self_hosted",
                   "environment": "production", "supabase_origin": "https://supabase.collect.example",
                   "member_api_origin": public["SUPABASE_API_URL"], "admin_origin": public["SUPABASE_ADMIN_API_URL"],
                   "public_origin": public["APP_PUBLIC_URL"], "google_callback_origin": public["ADMIN_APP_URL"]}
        raw = json.dumps(profile, sort_keys=True, separators=(",", ":"))
        return {"COLLECT_DEPLOYMENT_PROFILE": raw, "COLLECT_DEPLOYMENT_PROFILE_SHA256": hashlib.sha256(raw.encode()).hexdigest(),
                "COLLECT_SMS_AUTH_ENABLED": "true", "SUPABASE_URL": profile["supabase_origin"],
                "SUPABASE_API_URL": profile["member_api_origin"], "SUPABASE_ADMIN_API_URL": profile["admin_origin"],
                "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_syntheticPublicKey1234", "AUTH_CAPTCHA_SITE_KEY": "synthetic_public_site_key",
                "GOOGLE_AUTH_ENABLED": "false", "APP_PUBLIC_URL": profile["public_origin"], "ADMIN_APP_URL": profile["admin_origin"]}

    def test_candidate_steps_validate_and_export_exact_public_values_before_use(self):
        values = self.candidate_public_values()
        for job in (self.verify, self.delivery):
            select = next(step for step in job["steps"] if step.get("name") == "Select reviewed candidate public configuration")
            prepare = next(i for i, step in enumerate(job["steps"]) if "ios_delivery_guard.py prepare" in step.get("run", ""))
            self.assertLess(job["steps"].index(select), prepare)
            with tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary) / "github-env"
                output.write_text("EXISTING=one\n")
                base = {"PATH": str(Path(sys.executable).parent) + os.pathsep + os.defpath,
                        "GITHUB_WORKSPACE": str(ROOT), "GITHUB_ENV": str(output), "RUNNER_TEMP": temporary,
                        "COLLECT_BACKEND": "supabase", "AUTH_CAPTCHA_ENABLED": "true", "AUTH_CAPTCHA_PROVIDER": "turnstile"}
                result = subprocess.run(["/bin/bash", "-e", "-c", select["run"]], cwd=ROOT, env={**base, **values},
                                        capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
                rows = output.read_text().splitlines()
                self.assertEqual(rows[0], "EXISTING=one")
                self.assertEqual(len(rows) - 1, len(values))
                self.assertEqual(dict(row.split("=", 1) for row in rows[1:]), values)
                for changed in ({"COLLECT_DEPLOYMENT_PROFILE": ""},
                                {"COLLECT_DEPLOYMENT_PROFILE_SHA256": "0" * 64},
                                {"COLLECT_SMS_AUTH_ENABLED": "false"},
                                {"APP_PUBLIC_URL": "https://wrong.collect.example"},
                                {"SUPABASE_PUBLISHABLE_KEY": "synthetic\nINJECT=one"}):
                    with self.subTest(changed=list(changed)):
                        output.write_text("EXISTING=one\n")
                        result = subprocess.run(["/bin/bash", "-e", "-c", select["run"]], cwd=ROOT,
                                                env={**base, **values, **changed},
                                                capture_output=True, text=True, timeout=20)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(output.read_text(), "EXISTING=one\n")

    def test_candidate_export_refuses_missing_linked_or_outside_runner_files(self):
        values = self.candidate_public_values()
        select = next(step for step in self.verify["steps"] if step.get("name") == "Select reviewed candidate public configuration")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runner = root / "runner"; runner.mkdir()
            outside = root / "outside"; outside.write_text("EXISTING=one\n")
            link = runner / "link"; link.symlink_to(outside)
            base = {"PATH": str(Path(sys.executable).parent) + os.pathsep + os.defpath,
                    "GITHUB_WORKSPACE": str(ROOT), "RUNNER_TEMP": str(runner), "COLLECT_BACKEND": "supabase",
                    "AUTH_CAPTCHA_ENABLED": "true", "AUTH_CAPTCHA_PROVIDER": "turnstile"}
            for path in (outside, link, runner / "missing"):
                with self.subTest(path=path.name):
                    result = subprocess.run(["/bin/bash", "-e", "-c", select["run"]], cwd=ROOT,
                                            env={**base, **values, "GITHUB_ENV": str(path)},
                                            capture_output=True, text=True, timeout=20)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(outside.read_text(), "EXISTING=one\n")
            self.assertFalse((runner / "missing").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
