#!/usr/bin/env python3
"""Offline iOS source/signing/artifact contract fixtures; no Apple effects."""
from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ios_guard", ROOT / "scripts/qa/ios_delivery_guard.py")
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


PUBLIC_CONFIG = {"SUPABASE_URL": "https://rrlduytparvsjfmegalh.supabase.co",
                 "SUPABASE_API_URL": "https://platform-admin.collect.ikanisa.com",
                 "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_syntheticPublicKey1234",
                 "AUTH_CAPTCHA_SITE_KEY": "1x00000000000000000000AA"}


class DeliveryTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="collect-ios-delivery-test-")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.repo, self.candidate, self.work = (self.base / name for name in ("repo", "pristine", "work"))
        self.repo.mkdir()
        self.sdk = self.base / "sdk"
        (self.sdk / "bin/cache").mkdir(parents=True)
        (self.sdk / "bin/flutter").write_text("synthetic launcher")
        (self.sdk / "bin/cache/flutter.version.json").write_text(json.dumps({"frameworkVersion": "3.44.4", "frameworkRevision": "synthetic", "dartSdkVersion": "3.12.2"}))
        for name in guard.source_export.REQUIRED:
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("synthetic source")
        (self.repo / ".fvmrc").write_text('{"flutter":"3.44.4"}')
        (self.repo / "pubspec.yaml").write_text("name: collect\nversion: 1.0.8+65\n")
        for name in ("scripts/qa/ios_delivery_guard.py", "scripts/qa/collect_release_candidate.py", "scripts/qa/native_build_config.py", "fastlane/Fastfile"):
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, path)
        for name in ("fastlane/metadata/en-GB/review_notes.txt", "fastlane/metadata/en-GB/release_notes.txt", "fastlane/app_privacy_details.json"):
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("synthetic metadata")
        for cohort in ("iphone65", "ipadPro129"):
            for index in range(5):
                path = self.repo / f"fastlane/screenshots/en-GB/{cohort}-{index}.png"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("synthetic screenshot; not image acceptance")
        subprocess.run(["git", "init", "-q"], cwd=self.repo, check=True)
        subprocess.run(["git", "add", "."], cwd=self.repo, check=True)
        subprocess.run(["git", "-c", "user.email=synthetic@example.invalid", "-c", "user.name=Fixture", "commit", "-qm", "fixture"], cwd=self.repo, check=True)
        self.commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.repo, text=True).strip()
        self.export = guard.source_export.export_candidate(self.repo, self.candidate, self.sdk)
        shutil.copytree(self.candidate, self.work)
        self.approval_path = self.base / "approval.json"
        self.ipa, self.inspection_path = self.base / "Collect.ipa", self.base / "inspection.json"
        now = datetime.now(timezone.utc)
        with patch.dict(os.environ, PUBLIC_CONFIG, clear=True):
            public_configuration_sha256 = guard.runtime_configuration_sha256(self.work)
        self.record = {"schema_version": 1, "kind": "collect_ios_delivery_approval", "decision": "approved",
                       "operation": "signed_candidate", "environment": "collect-ios-signing", "target": dict(guard.TARGET),
                       "source_commit": self.commit, "source_manifest_sha256": self.export["source_manifest_sha256"],
                       "version": "1.0.8", "build_number": "65", "reviewer": "SYNTHETIC fixture", "review_record": "fixture only",
                       "approved_at_utc": (now - timedelta(minutes=1)).isoformat(), "expires_at_utc": (now + timedelta(hours=1)).isoformat(),
                       "artifact": None, "runtime_configuration_sha256": public_configuration_sha256}
        self.env = {**PUBLIC_CONFIG, "COLLECT_IOS_EXPECTED_REF": "refs/heads/main", "COLLECT_IOS_EXPECTED_COMMIT": self.commit,
                    "COLLECT_IOS_SOURCE_SHA256": self.export["source_manifest_sha256"], "COLLECT_IOS_OPERATION": "signed_candidate",
                    "COLLECT_IOS_CANDIDATE": str(self.candidate), "COLLECT_IOS_WORKDIR": str(self.work),
                    "COLLECT_IOS_APPROVAL_FILE": str(self.approval_path), "COLLECT_IOS_IPA": str(self.ipa),
                    "COLLECT_IOS_INSPECTION": str(self.inspection_path), "RUNNER_TEMP": str(self.base),
                    "COLLECT_API_URL": guard.TARGET["api_url"], "ADMIN_APP_URL": guard.TARGET["admin_url"],
                    "APPLE_CERTIFICATE_BASE64": "c3ludGhldGljLW5vdC1hLWNlcnRpZmljYXRl", "APPLE_CERTIFICATE_PASSWORD": "synthetic-password",
                    "APPLE_PROVISIONING_PROFILE_BASE64": "c3ludGhldGljLW5vdC1hLXByb2ZpbGU=", "KEYCHAIN_PASSWORD": "synthetic-keychain-password"}
        self.policy = {"name": "collect-ios-signing", "can_admins_bypass": False,
                       "protection_rules": [{"type": "required_reviewers", "prevent_self_review": True,
                                             "reviewers": [{"type": "User", "reviewer": {"id": 42}}]}],
                       "deployment_branch_policy": {"protected_branches": False, "custom_branch_policies": True}}
        self.branches = {"total_count": 1, "branch_policies": [{"name": "main", "type": "branch"}]}
        self.write_policy()
        mock_bin = self.base / "mock-bin"
        mock_bin.mkdir()
        fake_gh = mock_bin / "gh"
        fake_gh.write_text("#!" + sys.executable + "\nimport json, pathlib, sys\n"
                           "endpoint=sys.argv[-1]\n"
                           "assert endpoint.startswith('repos/ikanisa/COOL/environments/')\n"
                           "base=pathlib.Path(__file__).resolve().parents[1]\n"
                           "filename='branches.json' if 'deployment-branch-policies' in endpoint else 'policy.json'\n"
                           "value=json.loads((base/filename).read_text())\n"
                           "if filename=='policy.json': value['name']=endpoint.split('/')[-1]\n"
                           "print(json.dumps(value))\n")
        fake_gh.chmod(0o755)
        self.env["PATH"] = str(mock_bin) + os.pathsep + os.environ.get("PATH", "")
        self.environment = patch.dict(os.environ, self.env)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.write_approval()
        self.effects = []
        self.entitlements = {"application-identifier": guard.TARGET["team_id"] + "." + guard.TARGET["bundle_id"],
                             "com.apple.developer.team-identifier": guard.TARGET["team_id"], "aps-environment": "production",
                             "get-task-allow": False, "com.apple.developer.associated-domains": ["applinks:collect.ikanisa.com"]}
        self.profile = {"UUID": "SYNTHETIC-12345678", "TeamIdentifier": [guard.TARGET["team_id"]],
                        "ExpirationDate": (now + timedelta(days=30)).replace(tzinfo=None), "Entitlements": dict(self.entitlements)}

    def write_approval(self):
        data = (json.dumps(self.record, sort_keys=True) + "\n").encode()
        self.approval_path.write_bytes(data)
        os.environ["COLLECT_IOS_APPROVAL_SHA256"] = guard.digest(data)

    def write_policy(self):
        (self.base / "policy.json").write_text(json.dumps(self.policy))
        (self.base / "branches.json").write_text(json.dumps(self.branches))

    def fake_tool(self, command, **kwargs):
        self.effects.append(command)
        output, error = b"", b""
        if command[0] == "gh":
            output = json.dumps(self.branches if "deployment-branch-policies" in command[-1] else
                                {**self.policy, "name": command[-1].split("/")[-1]}).encode()
        if command[0] == "/usr/bin/security":
            if command[1] == "cms":
                output = plistlib.dumps(self.profile)
            elif command[1:4] == ["list-keychains", "-d", "user"] and "-s" not in command:
                output = b'"/synthetic/login.keychain-db"\n'
            elif command[1] == "create-keychain":
                Path(command[-1]).write_text("synthetic keychain")
            elif command[1] == "delete-keychain":
                Path(command[-1]).unlink(missing_ok=True)
        if command[0] == "/usr/bin/codesign" and "--display" in command:
            output = plistlib.dumps(self.entitlements) if "--entitlements" in command else b"Authority=Apple Distribution: SYNTHETIC\nAuthority=Apple Root CA\n"
        if kwargs.get("text"):
            output, error = output.decode(), error.decode()
        return subprocess.CompletedProcess(command, 0, output, error)

    def make_ipa(self, info=None, extra=None):
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.writestr("Payload/Collect.app/Info.plist", plistlib.dumps(info or {"CFBundleIdentifier": guard.TARGET["bundle_id"], "CFBundleShortVersionString": "1.0.8", "CFBundleVersion": "65", "CollectAPNSEnvironment": "production"}))
            archive.writestr("Payload/Collect.app/embedded.mobileprovision", b"synthetic profile payload")
            archive.writestr("Payload/Collect.app/PrivacyInfo.xcprivacy", plistlib.dumps({"NSPrivacyTracking": False, "NSPrivacyAccessedAPITypes": []}))
            archive.writestr("Payload/Collect.app/Frameworks/Synthetic.framework/PrivacyInfo.xcprivacy", plistlib.dumps({"NSPrivacyTracking": False}))
            if extra:
                archive.writestr(*extra)

    def approve_artifact(self):
        self.make_ipa()
        with patch.object(guard, "run_command", side_effect=self.fake_tool):
            inspection = guard.inspect_ipa(self.ipa, self.record)
        self.effects.clear()
        data = (json.dumps(inspection, sort_keys=True, indent=2) + "\n").encode()
        self.inspection_path.write_bytes(data)
        self.record.update(operation="testflight_internal", environment="collect-ios-testflight", artifact={"ipa_sha256": guard.digest(self.ipa.read_bytes()), "inspection_sha256": guard.digest(data)})
        self.write_approval()
        return inspection

    def assert_import_denied_without_effect(self, code):
        with patch.object(guard, "run_command", side_effect=self.fake_tool):
            with self.assertRaisesRegex((guard.GuardError, guard.source_export.ReleaseError), code):
                guard.import_signing()
        self.assertEqual(self.effects, [])
        self.assertFalse(guard.signing_paths().exists())

    def test_normal_mock_signing_and_cleanup_restore_keychain_and_remove_profile(self):
        with patch.object(guard, "run_command", side_effect=self.fake_tool), patch.object(Path, "home", return_value=self.base / "home"):
            self.assertEqual(guard.import_signing()["status"], "imported_scoped_signing_material")
            self.assertTrue(any(command[1] == "import" for command in self.effects))
            self.assertEqual(guard.cleanup_signing()["status"], "cleaned")
        self.assertFalse(guard.signing_paths().exists())
        self.assertFalse(list((self.base / "home").rglob("*.mobileprovision")))

    def test_signing_denies_missing_approval_before_any_keychain_effect(self):
        self.approval_path.unlink()
        self.assert_import_denied_without_effect("IOS_FILE_MISSING")

    def test_wrong_ref_commit_repository_and_runtime_target_precede_effects(self):
        cases = [("COLLECT_IOS_EXPECTED_REF", "refs/heads/feature", "REF_OR_COMMIT"),
                 ("COLLECT_IOS_EXPECTED_COMMIT", "0" * 40, "APPROVAL_SOURCE"),
                 ("GITHUB_REPOSITORY", "attacker/COOL", "REPOSITORY"),
                 ("GITHUB_SHA", "0" * 40, "WORKFLOW_COMMIT"),
                 ("COLLECT_API_URL", "https://wrong.invalid", "PUBLIC_BUILD_CONFIGURATION_WRONG"),
                 ("APP_PUBLIC_URL", "https://wrong.invalid", "PUBLIC_BUILD_CONFIGURATION_WRONG"),
                 ("ADMIN_APP_URL", "https://wrong.invalid", "PUBLIC_BUILD_CONFIGURATION_WRONG")]
        for key, value, code in cases:
            with self.subTest(key=key), patch.dict(os.environ, {key: value}):
                self.assert_import_denied_without_effect(code)

    def test_wrong_approval_digest_precedes_effects(self):
        self.approval_path.write_text("changed")
        self.assert_import_denied_without_effect("APPROVAL_CHANGED")

    def test_stale_future_overlong_wrong_scope_target_and_future_artifact_precede_effects(self):
        original = dict(self.record)
        now = datetime.now(timezone.utc)
        cases = [(dict(expires_at_utc=(now - timedelta(seconds=1)).isoformat()), "STALE"),
                 (dict(approved_at_utc=(now + timedelta(seconds=30)).isoformat()), "STALE"),
                 (dict(expires_at_utc=(now + timedelta(days=8)).isoformat()), "STALE"),
                 (dict(operation="testflight_internal"), "SCOPE_WRONG"),
                 (dict(environment="collect-ios-metadata"), "SCOPE_WRONG"),
                 (dict(target={**guard.TARGET, "bundle_id": "wrong.app"}), "TARGET_WRONG"),
                 (dict(reviewer=""), "REVIEW_RECORD"), (dict(artifact={"ipa_sha256": "0" * 64}), "FUTURE_ARTIFACT")]
        for changes, code in cases:
            with self.subTest(changes=changes):
                self.record = {**original, **changes}
                self.write_approval()
                self.assert_import_denied_without_effect(code)

    def test_changed_pristine_source_fails_before_signing(self):
        (self.candidate / "lib/main.dart").write_text("changed")
        self.assert_import_denied_without_effect("CANDIDATE_CHANGED")

    def test_incomplete_or_unlisted_candidate_manifest_cannot_import(self):
        path = self.candidate / guard.source_export.MANIFEST
        original = path.read_bytes()
        manifest = json.loads(original)
        manifest["source_files"].pop("lib/main.dart")
        manifest["file_count"] -= 1
        manifest["source_manifest_sha256"] = guard.source_export.sha(guard.source_export.canonical(manifest["source_files"]))
        path.write_text(json.dumps(manifest))
        self.assert_import_denied_without_effect("CANDIDATE_MANIFEST_INVALID")
        path.write_bytes(original)
        (self.candidate / "unlisted.txt").write_text("unreviewed extra source")
        self.assert_import_denied_without_effect("CANDIDATE_CHANGED")

    def test_missing_public_build_configuration_cannot_import(self):
        with patch.dict(os.environ, {"SUPABASE_PUBLISHABLE_KEY": ""}):
            self.assert_import_denied_without_effect("PUBLIC_BUILD_CONFIGURATION_WRONG")

    def test_changed_working_source_and_added_source_fail_before_signing(self):
        path = self.work / "lib/main.dart"
        original = path.read_bytes()
        path.write_text("changed")
        self.assert_import_denied_without_effect("WORKING_SOURCE_CHANGED")
        path.write_bytes(original)
        (self.work / "lib/added.dart").write_text("new unreviewed source")
        self.assert_import_denied_without_effect("WORKING_SOURCE_CHANGED")

    def test_generated_build_outputs_do_not_hide_changes_to_reviewed_source(self):
        (self.work / "build").mkdir()
        (self.work / "build/generated.txt").write_text("generated")
        (self.work / "ios/Flutter").mkdir()
        (self.work / "ios/Flutter/Generated.xcconfig").write_text("generated dependency configuration")
        self.assertEqual(guard.check()["operation"], "signed_candidate")
        (self.work / "pubspec.lock").write_text("unreviewed lock change")
        self.assert_import_denied_without_effect("WORKING_SOURCE_CHANGED")

    def test_non_atomic_candidate_is_not_accepted_for_signing(self):
        path = self.candidate / guard.source_export.MANIFEST
        value = json.loads(path.read_text())
        value.update(retain_source_drift=True, capture_classification="unapproved_non_atomic_implementation_checkpoint")
        path.write_text(json.dumps(value))
        self.assert_import_denied_without_effect("NON_ATOMIC")

    def test_profile_for_wrong_team_and_development_distribution_cannot_import(self):
        for mutation in (dict(TeamIdentifier=["OTHER"]), dict(ProvisionedDevices=["device"]), dict(ExpirationDate=datetime(2000, 1, 1))):
            with self.subTest(mutation=mutation), patch.object(guard, "run_command", side_effect=self.fake_tool), patch.object(Path, "home", return_value=self.base / "home"):
                old = dict(self.profile)
                self.profile.update(mutation)
                with self.assertRaises(guard.GuardError):
                    guard.import_signing()
                self.profile = old
                self.assertFalse(any(command[1] == "import" for command in self.effects))
                self.assertFalse(guard.signing_paths().exists())
                self.effects.clear()

    def test_failed_import_cleans_material_and_reports_failure_without_retry(self):
        def failed_tool(command, **kwargs):
            if command[1] == "import":
                self.effects.append(command)
                raise guard.GuardError("SYNTHETIC_IMPORT_FAILED")
            return self.fake_tool(command, **kwargs)
        with patch.object(guard, "run_command", side_effect=failed_tool), patch.object(Path, "home", return_value=self.base / "home"):
            with self.assertRaisesRegex(guard.GuardError, "SYNTHETIC_IMPORT_FAILED"):
                guard.import_signing()
        self.assertEqual(sum(command[1] == "import" for command in self.effects), 1)
        self.assertFalse(guard.signing_paths().exists())
        self.assertFalse(list((self.base / "home").rglob("*.mobileprovision")))

    def test_normal_internal_mock_artifact_check_inventory_and_upload_boundary(self):
        inspection = self.approve_artifact()
        with patch.object(guard, "run_command", side_effect=self.fake_tool):
            record = guard.check("testflight_internal")
            guard.verify_environment("testflight_internal")
            self.effects.append(["SYNTHETIC_UPLOAD", record["artifact"]["ipa_sha256"]])
        self.assertEqual(self.effects[-1][0], "SYNTHETIC_UPLOAD")
        self.assertEqual(len(inspection["privacy_manifests"]), 2)
        self.assertEqual(inspection["entitlements"]["aps-environment"], "production")
        self.assertEqual(inspection["runtime_apns_environment"], "production")

    def test_changed_missing_artifact_and_changed_inspection_block_before_upload(self):
        self.approve_artifact()
        original = self.ipa.read_bytes()
        for content in (b"changed", None):
            with self.subTest(content=content), patch.object(guard, "run_command", side_effect=self.fake_tool):
                if content is None:
                    self.ipa.unlink()
                else:
                    self.ipa.write_bytes(content)
                with self.assertRaises(guard.GuardError):
                    guard.check("testflight_internal")
                self.assertEqual(self.effects, [])
                self.ipa.write_bytes(original)
        self.inspection_path.write_text("changed")
        with self.assertRaisesRegex(guard.GuardError, "ARTIFACT_NOT_APPROVED"):
            guard.check("testflight_internal")

    def test_wrong_signed_identity_and_entitlements_fail_inspection(self):
        self.make_ipa(info={"CFBundleIdentifier": "wrong.app", "CFBundleShortVersionString": "1.0.8", "CFBundleVersion": "65"})
        with patch.object(guard, "run_command", side_effect=self.fake_tool):
            with self.assertRaisesRegex(guard.GuardError, "IDENTITY_WRONG"):
                guard.inspect_ipa(self.ipa, self.record)
        self.assertEqual(self.effects, [])
        self.make_ipa()
        self.entitlements["aps-environment"] = "development"
        with patch.object(guard, "run_command", side_effect=self.fake_tool):
            with self.assertRaisesRegex(guard.GuardError, "ENTITLEMENTS_WRONG"):
                guard.inspect_ipa(self.ipa, self.record)

    def test_traversal_and_unsigned_ipa_do_not_pass_inspection(self):
        self.make_ipa(extra=("../escape", "bad"))
        with self.assertRaisesRegex(guard.GuardError, "IPA_PATH_INVALID"):
            guard.inspect_ipa(self.ipa, self.record)
        self.assertEqual(self.effects, [])
        self.make_ipa()
        with patch.object(guard, "run_command", side_effect=guard.GuardError("UNSIGNED_FIXTURE")):
            with self.assertRaisesRegex(guard.GuardError, "UNSIGNED_FIXTURE"):
                guard.inspect_ipa(self.ipa, self.record)

    def test_missing_unexpanded_and_invalid_runtime_apns_markers_fail_signed_inspection(self):
        identity = {"CFBundleIdentifier": guard.TARGET["bundle_id"], "CFBundleShortVersionString": "1.0.8", "CFBundleVersion": "65"}
        variants = [identity, *({**identity, "CollectAPNSEnvironment": marker} for marker in
                               ("development", "$(APS_ENVIRONMENT)", "", " production ", False, ["production"], {"environment": "production"}))]
        for info in variants:
            with self.subTest(info=info), patch.object(guard, "run_command", side_effect=self.fake_tool):
                self.make_ipa(info=info)
                with self.assertRaisesRegex(guard.GuardError, "IOS_RUNTIME_APNS_ENVIRONMENT_WRONG"):
                    guard.inspect_ipa(self.ipa, self.record)
        self.assertFalse(any(command[0] not in ("/usr/bin/codesign", "/usr/bin/security") for command in self.effects))
        self.assertFalse(any(command[0] == "/usr/bin/security" for command in self.effects))

    def test_changed_runtime_apns_marker_cannot_reuse_approved_inspection(self):
        inspection = self.approve_artifact()
        self.make_ipa(info={"CFBundleIdentifier": guard.TARGET["bundle_id"], "CFBundleShortVersionString": "1.0.8",
                            "CFBundleVersion": "65", "CollectAPNSEnvironment": "development"})
        # Even refreshed artifact metadata cannot substitute an old production
        # readback for reinspection of the bytes being uploaded.
        self.record["artifact"]["ipa_sha256"] = guard.digest(self.ipa.read_bytes())
        self.write_approval()
        self.effects.clear()
        with patch.object(guard, "run_command", side_effect=self.fake_tool):
            with self.assertRaisesRegex(guard.GuardError, "IOS_RUNTIME_APNS_ENVIRONMENT_WRONG"):
                guard.check("testflight_internal")
        self.assertEqual(inspection["runtime_apns_environment"], "production")
        self.assertTrue(all(command[0] == "/usr/bin/codesign" for command in self.effects))

    def test_adhoc_and_development_authority_cannot_pass_signed_inspection(self):
        self.make_ipa()
        for authority in (b"Signature=adhoc\n", b"Authority=Apple Development: SYNTHETIC\n"):
            def fake_signer(command, **kwargs):
                if command[0] == "/usr/bin/codesign" and "--verbose=4" in command:
                    return subprocess.CompletedProcess(command, 0, b"", authority)
                return self.fake_tool(command, **kwargs)
            with self.subTest(authority=authority), patch.object(guard, "run_command", side_effect=fake_signer):
                with self.assertRaisesRegex(guard.GuardError, "DISTRIBUTION_SIGNER"):
                    guard.inspect_ipa(self.ipa, self.record)
        self.assertTrue(any("-R" in command and "anchor apple generic" in " ".join(command) for command in self.effects))

    def test_all_effect_scopes_are_distinct_and_public_binary_release_is_unavailable(self):
        for operation in guard.ENVIRONMENTS:
            with self.subTest(operation=operation):
                self.record.update(operation=operation, environment=guard.ENVIRONMENTS[operation],
                                   artifact={"ipa_sha256": "0" * 64, "inspection_sha256": "1" * 64} if operation == "testflight_internal" else None)
                self.write_approval()
                self.assertEqual(guard.approval(operation)["operation"], operation)
                other = "metadata" if operation != "metadata" else "signed_candidate"
                with self.assertRaisesRegex(guard.GuardError, "SCOPE_WRONG"):
                    guard.approval(other)
        with self.assertRaisesRegex(guard.GuardError, "UNSUPPORTED"):
            guard.approval("public_release")

    def run_lane(self, lane):
        output = self.base / "lane-effects.json"
        result = subprocess.run(["ruby", str(ROOT / "scripts/tests/ios_fastlane_offline_harness.rb"),
                                 str(self.work / "fastlane/Fastfile"), lane, str(output)],
                                cwd=self.work / "fastlane", capture_output=True, text=True)
        return result, json.loads(output.read_text())

    def test_environment_readback_rejects_unprotected_self_review_bypass_or_wrong_branches(self):
        original = json.loads(json.dumps(self.policy))
        variants = [{**original, "can_admins_bypass": True},
                    {key: value for key, value in original.items() if key != "can_admins_bypass"},
                    {**original, "protection_rules": []},
                    {**original, "protection_rules": [{"type": "required_reviewers", "prevent_self_review": False, "reviewers": [42]}]},
                    {**original, "deployment_branch_policy": None}]
        for policy in variants:
            with self.subTest(policy=policy), patch.object(guard, "run_command", side_effect=self.fake_tool):
                self.policy = policy
                with self.assertRaisesRegex(guard.GuardError, "ENVIRONMENT"):
                    guard.verify_environment("signed_candidate")
                self.assertFalse(any(command[0] != "gh" for command in self.effects))
                self.effects.clear()
        self.policy = original
        for branches in ({"total_count": 0, "branch_policies": []},
                         {"total_count": 1, "branch_policies": [{"name": "main", "type": "tag"}]},
                         {"total_count": 1, "branch_policies": [{"name": "*", "type": "branch"}]}):
            with self.subTest(branches=branches), patch.object(guard, "run_command", side_effect=self.fake_tool):
                self.branches = branches
                with self.assertRaisesRegex(guard.GuardError, "MAIN_ONLY"):
                    guard.verify_environment("signed_candidate")

    def test_actual_lane_denies_unprotected_environment_before_api_key_or_upload(self):
        self.record.update(operation="metadata", environment="collect-ios-metadata")
        self.write_approval()
        self.policy["can_admins_bypass"] = True
        self.write_policy()
        result, effects = self.run_lane("upload_metadata_screenshots")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(effects["effects"], [])
        self.assertIn("ENVIRONMENT_BYPASS", effects["reason"])

    def test_actual_fastlane_lanes_deny_missing_approval_before_api_key_or_upload(self):
        self.approval_path.unlink()
        for lane in ("upload_metadata_screenshots", "upload_existing_app_store_screenshots", "upload_review_build", "upload_app_privacy_details", "build_review_ipa"):
            with self.subTest(lane=lane):
                result, effects = self.run_lane(lane)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(effects["effects"], [])
                self.assertIn("IOS_FILE_MISSING", effects["reason"])

    def test_actual_metadata_lane_uses_approved_source_and_cannot_submit_public_release(self):
        self.record.update(operation="metadata", environment="collect-ios-metadata")
        self.write_approval()
        os.environ.update(ASC_KEY_ID="synthetic-key", ASC_ISSUER_ID="synthetic-issuer", ASC_PRIVATE_KEY="synthetic-not-private-key",
                          COLLECT_REVIEW_PHONE="synthetic-phone", COLLECT_REVIEW_OTP="synthetic-otp")
        self.addCleanup(lambda: [os.environ.pop(name, None) for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY", "COLLECT_REVIEW_PHONE", "COLLECT_REVIEW_OTP")])
        result, effects = self.run_lane("upload_metadata_screenshots")
        self.assertEqual(result.returncode, 0, effects)
        self.assertEqual(effects["effects"][-1], ["mock_metadata_upload"])
        self.assertEqual(sum(row[0] == "mock_api_key" for row in effects["effects"]), 1)
        (self.work / "fastlane/metadata/en-GB/review_notes.txt").write_text("changed unreviewed metadata")
        result, effects = self.run_lane("upload_metadata_screenshots")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(effects["effects"], [])
        self.assertIn("IOS_WORKING_SOURCE_CHANGED", effects["reason"])

    def test_prepare_rejects_wrong_commit_dirty_checkout_and_source_hash(self):
        destination, work = self.base / "export2", self.base / "work2"
        with patch.dict(os.environ, {"COLLECT_IOS_EXPECTED_COMMIT": "0" * 40}):
            with self.assertRaisesRegex(guard.GuardError, "COMMIT_WRONG"):
                guard.prepare(self.repo, destination, work, self.sdk)
        (self.repo / "lib/main.dart").write_text("changed")
        with self.assertRaisesRegex(guard.GuardError, "CHECKOUT_DIRTY"):
            guard.prepare(self.repo, destination, work, self.sdk)
        self.assertFalse(destination.exists())

    def test_normal_unsigned_prepare_needs_no_approval_and_copies_exact_source(self):
        os.environ["COLLECT_IOS_OPERATION"] = "unsigned_candidate"
        self.approval_path.unlink()
        destination, work = self.base / "export2", self.base / "work2"
        result = guard.prepare(self.repo, destination, work, self.sdk)
        self.assertEqual(result["status"], "pass")
        self.assertEqual((work / "lib/main.dart").read_bytes(), (self.repo / "lib/main.dart").read_bytes())
        self.assertEqual(self.effects, [])
        with patch.dict(os.environ, {"COLLECT_IOS_SOURCE_SHA256": "0" * 64}):
            with self.assertRaisesRegex(guard.GuardError, "REVIEWED_SOURCE_WRONG"):
                guard.prepare(self.repo, self.base / "export3", self.base / "work3", self.sdk)


if __name__ == "__main__":
    unittest.main(verbosity=2)
