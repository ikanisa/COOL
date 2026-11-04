#!/usr/bin/env python3
"""Offline candidate boundary tests. No SDK, signing key or provider is used."""
from datetime import datetime, timedelta, timezone
import base64
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import signal
import sys
import time
import shlex
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("android_candidate", ROOT / "scripts/qa/android_signed_candidate.py")
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)

SDK_XML = b'''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" android:compileSdkVersion="36">
  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36" />
  <application />
</manifest>'''


class CandidateBoundaryTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.root = self.base / "repo"
        (self.root / "android/app").mkdir(parents=True)
        self.bundletool = self.base / "synthetic-bundletool.jar"
        self.bundletool.write_bytes(b"SYNTHETIC NOT BUNDLETOOL")
        pin = patch.object(guard, "BUNDLETOOL_SHA256", guard.sha(self.bundletool.read_bytes()))
        pin.start()
        self.addCleanup(pin.stop)
        java_bin = self.base / "bin"
        java_bin.mkdir()
        (java_bin / "java").write_text("#!/bin/sh\nexit 99\n")
        (java_bin / "java").chmod(0o700)
        (self.root / "pubspec.yaml").write_text("name: collect_app\nversion: 1.0.8+65\n")
        (self.root / "pubspec.lock").write_text("packages: {}\n")
        (self.root / "lib").mkdir()
        (self.root / "lib/main.dart").write_text("void main() {}\n")
        (self.root / "lib/other.dart").write_text("const syntheticValue = true;\n")
        self.commit = "a" * 40
        self.pin = "B" * 64
        provider = json.dumps({"client": [{"client_info": {"android_client_info": {"package_name": guard.PACKAGE}}}]})
        self.env = {"GITHUB_WORKSPACE": str(self.root), "RUNNER_TEMP": str(self.base),
                    "PATH": str(java_bin) + os.pathsep + os.defpath, "COLLECT_BUNDLETOOL_JAR": str(self.bundletool),
                    "GITHUB_REPOSITORY": "ikanisa/COOL", "GITHUB_REF": "refs/heads/main", "GITHUB_SHA": self.commit,
                    "COLLECT_ANDROID_EXPECTED_COMMIT": self.commit, "COLLECT_ANDROID_SOURCE_SHA256": "c" * 64,
                    "COLLECT_ANDROID_APPROVED_UPLOAD_CERT_SHA256": self.pin,
                    "PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER": "123456789012", "COLLECT_ANDROID_GOOGLE_SERVICES_JSON": provider,
                    "SUPABASE_URL": guard.native_build_config.PROJECT, "SUPABASE_API_URL": guard.native_build_config.ADMIN,
                    "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_syntheticPublicKey1234",
                    "AUTH_CAPTCHA_SITE_KEY": "synthetic_public_site_key", "FLUTTER_ROOT": str(self.base / "unused-sdk"),
                    "KEYSTORE_BASE64": base64.b64encode(b"SYNTHETIC NOT A KEYSTORE").decode(),
                    "KEY_ALIAS": "synthetic-alias", "KEY_PASSWORD": "synthetic-password", "STORE_PASSWORD": "synthetic-password"}
        self.profile = guard.source_bound_public_configuration(self.root, self.env)
        now = datetime.now(timezone.utc)
        self.record = {"schema_version": 1, "kind": "collect_android_candidate_approval", "decision": "approved",
                       "operation": "signed_candidate", "environment": guard.ENVIRONMENT, "application_id": guard.PACKAGE,
                       "source_commit": self.commit, "source_manifest_sha256": "c" * 64,
                       "public_runtime_config_sha256": guard.sha(guard.canonical(self.profile)),
                       "google_services_sha256": guard.sha(provider.encode()), "play_integrity_cloud_project_number": "123456789012",
                       "upload_certificate_sha256": self.pin, "version": "1.0.8", "build_number": "65", "artifact": None,
                       "reviewer": "SYNTHETIC fixture", "review_record": "Fixture only, no human approval",
                       "approved_at_utc": (now - timedelta(minutes=1)).isoformat(),
                       "expires_at_utc": (now + timedelta(hours=1)).isoformat()}
        self.environment = patch.dict(os.environ, self.env, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.write_approval()
        self.policy = {"name": guard.ENVIRONMENT, "can_admins_bypass": False,
                       "protection_rules": [{"type": "required_reviewers", "prevent_self_review": True,
                                             "reviewers": [{"type": "User", "reviewer": {"id": 42}}]}],
                       "deployment_branch_policy": {"protected_branches": False, "custom_branch_policies": True}}
        self.branches = {"total_count": 1, "branch_policies": [{"id": 99, "name": "main", "type": "branch"}]}

    def write_approval(self):
        raw = json.dumps(self.record)
        os.environ["REVIEWED_ANDROID_APPROVAL_RECORD"] = raw
        os.environ["COLLECT_ANDROID_APPROVAL_SHA256"] = guard.sha(raw.encode())

    def git_command(self, args, **_):
        self.assertEqual(args, ["git", "rev-parse", "HEAD"])
        return (self.commit + "\n").encode()

    def policy_command(self, args, **_):
        return json.dumps(self.branches if "deployment-branch-policies" in args[-1] else self.policy).encode()

    def test_exact_source_public_profile_and_upload_pin_are_required_before_effects(self):
        with patch.object(guard, "command", side_effect=self.git_command):
            observed, _, _ = guard.configuration_and_approval(self.root)
            self.assertEqual(observed["upload_certificate_sha256"], self.pin)
            for key, value in (("COLLECT_ANDROID_APPROVED_UPLOAD_CERT_SHA256", ""), ("GITHUB_REF", "refs/heads/other"),
                               ("SUPABASE_URL", "https://other.supabase.co"), ("AUTH_CAPTCHA_ENABLED", "false"),
                               ("GOOGLE_AUTH_ENABLED", "yes"), ("PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER", "")):
                with self.subTest(key=key), patch.dict(os.environ, {key: value}):
                    with self.assertRaises((guard.Blocked, ValueError)):
                        guard.configuration_and_approval(self.root)

    def test_wrong_scope_or_changed_config_and_future_artifact_are_not_approved(self):
        with patch.object(guard, "command", side_effect=self.git_command):
            for key, value in (("operation", "play_publication"), ("source_commit", "d" * 40),
                               ("upload_certificate_sha256", "E" * 64), ("public_runtime_config_sha256", "f" * 64),
                               ("google_services_sha256", "e" * 64), ("play_integrity_cloud_project_number", "2"),
                               ("expires_at_utc", (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()),
                               ("artifact", {"future_aab_sha256": "0" * 64})):
                original = self.record[key]
                self.record[key] = value
                self.write_approval()
                with self.subTest(key=key), self.assertRaises(guard.Blocked):
                    guard.configuration_and_approval(self.root)
                self.record[key] = original
            self.write_approval()
            with patch.dict(os.environ, {"REVIEWED_ANDROID_APPROVAL_RECORD": "{}"}):
                with self.assertRaises(guard.Blocked):
                    guard.configuration_and_approval(self.root)

    def assert_real_builder_binding_matches_approval(self, environment, approved):
        """Run the actual diagnostic bind CLI on an isolated synthetic tree."""
        builder_env = {**environment, "COLLECT_BUILD_SOURCE_ID": approved["COLLECT_BUILD_SOURCE_ID"]}
        builder_profile = guard.native_build_config.configuration(builder_env, "android", self.root / "pubspec.yaml")
        defines = self.base / "synthetic-builder-defines.json"
        manifest = self.base / "synthetic-diagnostic-manifest.json"
        defines.write_text(json.dumps(builder_profile))
        result = subprocess.run(
            [sys.executable, "-B", str(ROOT / "scripts/qa/client_diagnostic_identity.py"), "bind",
             "--root", str(self.root), "--surface", "member", "--defines", str(defines),
             "--manifest", str(manifest)],
            env={"PATH": os.defpath, "PYTHONDONTWRITEBYTECODE": "1"},
            capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        actual = json.loads(defines.read_text())
        self.assertEqual(actual, approved)
        self.assertEqual(json.loads(manifest.read_text())["source_revision"], approved["COLLECT_BUILD_SOURCE_ID"])
        self.assertEqual(guard.sha(guard.canonical(actual)), self.record["public_runtime_config_sha256"])
        # Match the store wrapper's manifest serialization, not a second copy of
        # the guard's Python hash calculation.
        ruby = subprocess.run(
            ["ruby", "-rjson", "-rdigest", "-e",
             'values = JSON.parse(File.read(ARGV.fetch(0))); '
             'puts Digest::SHA256.hexdigest(JSON.generate(values.sort.to_h))', str(defines)],
            env={"PATH": os.defpath}, capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(ruby.returncode, 0, ruby.stderr)
        self.assertEqual(ruby.stdout.strip(), self.record["public_runtime_config_sha256"])

    def test_approved_hash_matches_the_actual_diagnostic_bind_for_managed_profile(self):
        with patch.object(guard, "command", side_effect=self.git_command):
            _, approved, _ = guard.configuration_and_approval(self.root)
        self.assert_real_builder_binding_matches_approval(self.env, approved)

    def test_approved_hash_matches_the_actual_diagnostic_bind_for_self_hosted_profile(self):
        deployment = {"format": "collect.deployment.v1", "id": "synthetic-selfhost",
                      "mode": "self_hosted", "environment": "production",
                      "supabase_origin": "https://supabase.collect.example",
                      "member_api_origin": "https://api.collect.example",
                      "admin_origin": "https://admin.collect.example",
                      "public_origin": "https://collect.example",
                      "google_callback_origin": "https://admin.collect.example"}
        raw = json.dumps(deployment, sort_keys=True, separators=(",", ":"))
        values = {"COLLECT_DEPLOYMENT_PROFILE": raw, "COLLECT_DEPLOYMENT_PROFILE_SHA256": guard.sha(raw.encode()),
                  "SUPABASE_URL": deployment["supabase_origin"], "SUPABASE_API_URL": deployment["member_api_origin"],
                  "COLLECT_SMS_AUTH_ENABLED": "true"}
        self.record["public_runtime_config_sha256"] = guard.sha(guard.canonical(
            guard.source_bound_public_configuration(self.root, {**self.env, **values})))
        self.write_approval()
        with patch.dict(os.environ, values), patch.object(guard, "command", side_effect=self.git_command):
            _, approved, _ = guard.configuration_and_approval(self.root)
            with patch.dict(os.environ, {"COLLECT_SMS_AUTH_ENABLED": "false"}):
                with self.assertRaisesRegex(guard.Blocked, "ANDROID_APPROVAL_SCOPE_OR_INPUT_WRONG"):
                    guard.configuration_and_approval(self.root)
        self.assertEqual(approved["COLLECT_SMS_AUTH_ENABLED"], "true")
        self.assert_real_builder_binding_matches_approval({**self.env, **values}, approved)

    def test_source_or_sms_flag_change_invalidates_approval(self):
        with patch.object(guard, "command", side_effect=self.git_command):
            source = self.root / "lib/other.dart"
            original = source.read_text()
            source.write_text(original + "// changed synthetic source\n")
            try:
                with self.assertRaisesRegex(guard.Blocked, "ANDROID_APPROVAL_SCOPE_OR_INPUT_WRONG"):
                    guard.configuration_and_approval(self.root)
            finally:
                source.write_text(original)
            with patch.dict(os.environ, {"COLLECT_SMS_AUTH_ENABLED": "true"}):
                with self.assertRaisesRegex(guard.Blocked, "ANDROID_APPROVAL_SCOPE_OR_INPUT_WRONG"):
                    guard.configuration_and_approval(self.root)
            _, approved, _ = guard.configuration_and_approval(self.root)
        self.assertEqual(approved, self.profile)

    def test_supplied_diagnostic_id_must_match_before_approval(self):
        expected = self.profile["COLLECT_BUILD_SOURCE_ID"]
        wrong = "0" * 64 if expected != "0" * 64 else "1" * 64
        with patch.object(guard, "command", side_effect=self.git_command), \
                patch.object(guard, "run_builder") as builder:
            with patch.dict(os.environ, {"COLLECT_BUILD_SOURCE_ID": wrong}):
                with self.assertRaisesRegex(guard.Blocked, "ANDROID_DIAGNOSTIC_SOURCE_WRONG"):
                    guard.build()
            with patch.dict(os.environ, {"COLLECT_BUILD_SOURCE_ID": expected}):
                _, approved, _ = guard.configuration_and_approval(self.root)
                self.assertEqual(approved, self.profile)
        builder.assert_not_called()

    def test_invalid_diagnostic_source_is_refused_before_builder(self):
        (self.root / "lib/linked.dart").symlink_to(self.root / "lib/main.dart")
        with patch.object(guard, "command", side_effect=self.git_command), \
                patch.object(guard, "run_builder") as builder:
            with self.assertRaisesRegex(guard.Blocked, "ANDROID_DIAGNOSTIC_SOURCE_INVALID"):
                guard.build()
        builder.assert_not_called()

    def test_current_environment_must_have_independent_review_no_bypass_and_main_only(self):
        with patch.object(guard, "command", side_effect=self.policy_command):
            guard.environment_policy()
            for key, value in (("can_admins_bypass", True), ("protection_rules", []), ("deployment_branch_policy", None)):
                original = self.policy[key]
                self.policy[key] = value
                with self.subTest(key=key), self.assertRaises(guard.Blocked):
                    guard.environment_policy()
                self.policy[key] = original
            self.policy["protection_rules"][0]["prevent_self_review"] = False
            with self.assertRaises(guard.Blocked):
                guard.environment_policy()
            self.policy["protection_rules"][0]["prevent_self_review"] = True
            self.branches["branch_policies"][0]["type"] = "tag"
            with self.assertRaises(guard.Blocked):
                guard.environment_policy()

    def test_policy_preflight_needs_only_main_identity_and_read_only_environment_queries(self):
        # This job must run before any environment or signing inputs are bound.
        minimal = {key: self.env[key] for key in ("GITHUB_WORKSPACE", "GITHUB_REPOSITORY", "GITHUB_REF",
                                                 "GITHUB_SHA", "COLLECT_ANDROID_EXPECTED_COMMIT")}
        calls = []

        def reads(args, **kwargs):
            calls.append(args)
            return self.git_command(args, **kwargs) if args[0] == "git" else self.policy_command(args, **kwargs)

        with patch.dict(os.environ, minimal, clear=True), patch.object(guard, "command", side_effect=reads), \
                patch.object(guard, "configuration_and_approval") as approval, \
                patch.object(guard, "run_builder") as builder:
            guard.policy_preflight()
        self.assertEqual(calls[0], ["git", "rev-parse", "HEAD"])
        self.assertEqual(calls[1:], [
            ["gh", "api", "repos/ikanisa/COOL/environments/collect-android-signing"],
            ["gh", "api", "repos/ikanisa/COOL/environments/collect-android-signing/deployment-branch-policies?per_page=100"],
        ])
        approval.assert_not_called()
        builder.assert_not_called()
        self.assertFalse((self.base / "collect-android-signing").exists())

    def test_missing_or_unprotected_environment_blocks_policy_without_creation_or_signing(self):
        import contextlib
        import io

        for missing in (True, False):
            calls = []
            self.policy["can_admins_bypass"] = not missing

            def reads(args, **kwargs):
                calls.append(args)
                if args[0] == "git":
                    return self.git_command(args, **kwargs)
                if missing:
                    raise guard.Blocked("ANDROID_TOOL_FAILED")
                return self.policy_command(args, **kwargs)

            output = io.StringIO()
            with self.subTest(missing=missing), patch.object(guard, "command", side_effect=reads), \
                    patch.object(guard.sys, "argv", ["candidate", "policy"]), \
                    patch.object(guard, "run_builder") as builder, contextlib.redirect_stdout(output):
                self.assertEqual(guard.main(), 1)
            self.assertEqual(json.loads(output.getvalue())["status"], "blocked")
            self.assertTrue(all(args[:2] == ["gh", "api"] or args[0] == "git" for args in calls))
            self.assertFalse(any(word in ("POST", "PUT", "PATCH", "--method") for args in calls for word in args))
            builder.assert_not_called()

    def test_wrong_dispatch_identity_blocks_before_environment_query(self):
        with patch.dict(os.environ, {"GITHUB_REF": "refs/heads/other"}), \
                patch.object(guard, "command") as read:
            with self.assertRaises(guard.Blocked):
                guard.policy_preflight()
        read.assert_not_called()

    def test_workflow_policy_job_has_no_environment_or_secrets_and_controls_signing_dependency(self):
        source = (ROOT / ".github/workflows/ci.yml").read_text()

        def job(name):
            match = re.search(r"^  " + name + r":\n(.*?)(?=^  [a-zA-Z0-9_-]+:|\Z)", source, re.M | re.S)
            self.assertIsNotNone(match, name)
            return match.group(1)

        policy = job("android-signing-policy")
        signed = job("android-signed-candidate")
        self.assertIsNone(re.search(r"^\s*environment:", policy, re.M))
        self.assertNotIn("secrets.", policy)
        self.assertIn("scripts/qa/android_signed_candidate.py policy", policy)
        self.assertIn("android_signed_candidate", policy)
        self.assertIn("github.ref == 'refs/heads/main'", policy)
        needs = re.search(r"^\s+needs:\s*\[([^]]+)\]", signed, re.M)
        self.assertIsNotNone(needs)
        self.assertEqual({value.strip() for value in needs.group(1).split(",")}, {"analyze", "android-signing-policy"})
        self.assertIn("environment: collect-android-signing", signed)
        self.assertIn("${{ runner.temp }}/android-delivery/Collect.apk", signed)
        self.assertIn("${{ runner.temp }}/android-delivery/Collect.aab", signed)
        acquisition = re.search(r"      - name: Prepare pinned Android bundletool\n(.*?)(?=^      - |\Z)",
                                signed, re.M | re.S)
        self.assertIsNotNone(acquisition)
        step = acquisition.group(1)
        self.assertIn("https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar", step)
        self.assertIn("a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29", step)
        self.assertIn("hashlib.sha256()", step)
        self.assertIn("digest.hexdigest()", step)
        self.assertIn("limit = 32520401", step)
        self.assertIn("total != limit", step)
        self.assertIn("COLLECT_BUNDLETOOL_JAR=%s", step)
        self.assertIn("--proto '=https' --proto-redir '=https'", step)
        self.assertNotIn("secrets.", step)
        self.assertLess(step.index("digest.hexdigest()"), step.index("COLLECT_BUNDLETOOL_JAR=%s"))
        self.assertLess(signed.index("name: Prepare pinned Android bundletool"),
                        signed.index("scripts/qa/android_signed_candidate.py prepare"))
        self.assertLess(signed.index("scripts/qa/android_signed_candidate.py prepare"),
                        signed.index("scripts/qa/android_signed_candidate.py build"))

    def build_fixture(self):
        _, pristine, output, _ = guard.paths()
        pristine.mkdir()
        (pristine / guard.source_export.MANIFEST).write_text("{}")
        output.mkdir()
        aab = self.root / guard.AAB
        aab.parent.mkdir(parents=True)
        aab.write_bytes(b"SYNTHETIC NOT A SIGNED BUNDLE")
        digest = guard.sha(aab.read_bytes())
        apk = self.root / guard.APK
        apk.parent.mkdir(parents=True)
        apk.write_bytes(b"SYNTHETIC NOT A SIGNED APK")
        apk_digest = guard.sha(apk.read_bytes())
        manifest = {"backend": "supabase", "mobile_evidence_mode": False, "artifact_version": "1.0.8+65",
                    "public_runtime_config_sha256": self.record["public_runtime_config_sha256"],
                    "artifacts": {"aab": {"sha256": digest}, "apk": {"sha256": apk_digest}}}
        native = {"schema_version": 3, "platform": "android", "version": "1.0.8+65", "source_file_count": 1,
                  "artifacts": {"aab": digest, "apk": apk_digest}, "artifact_metadata": {
                  "aab": {"artifact_sha256": digest, "status": "pass",
                          "actual": {"package": guard.PACKAGE, "version_name": "1.0.8", "version_code": 65}},
                  "apk": {"artifact_sha256": apk_digest, "status": "pass",
                          "actual": {"package": guard.PACKAGE, "version_name": "1.0.8", "version_code": 65}}}, "release_approval": False}
        for name, value in ((".cache/android_play_store_build/1.0.8+65.json", manifest), (".cache/native-build/android.json", native)):
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps(value))
        return output

    def test_bundletool_must_be_an_absolute_regular_file_with_the_pinned_bytes(self):
        link = self.base / "bundletool-link.jar"
        link.symlink_to(self.bundletool)
        wrong = self.base / "wrong.jar"
        wrong.write_bytes(b"WRONG SYNTHETIC TOOL")
        fifo = self.base / "synthetic-fifo"
        os.mkfifo(fifo)
        for value in ("", "relative.jar", str(link), str(self.base), str(wrong), str(fifo), str(self.base / "missing.jar")):
            with self.subTest(value=value), patch.dict(os.environ, {"COLLECT_BUNDLETOOL_JAR": value}):
                with self.assertRaises(guard.Blocked):
                    guard.bundletool_input()
        jar, java, java_digest = guard.bundletool_input()
        self.assertEqual(jar, self.bundletool)
        self.assertEqual(java, str((self.base / "bin/java").resolve()))
        self.assertEqual(java_digest, guard.sha(Path(java).read_bytes()))

    def test_bad_bundletool_blocks_before_any_builder_or_transient_signing(self):
        output = self.build_fixture()
        with patch.dict(os.environ, {"COLLECT_BUNDLETOOL_JAR": ""}), \
                patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, b"{}")), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder") as builder:
            with self.assertRaises(guard.Blocked):
                guard.build()
        builder.assert_not_called()
        self.assertFalse((self.base / "collect-android-signing").exists())
        self.assertEqual(list(output.iterdir()), [])

    def test_manifest_rejects_missing_duplicate_nonnumeric_old_and_malformed_sdk_values(self):
        self.assertEqual(guard.sdk_from_manifest(SDK_XML), {"compile_sdk": 36, "target_sdk": 36})
        self.assertEqual(guard.sdk_from_manifest(SDK_XML.replace(b'Version="36"', b'Version="37"')),
                         {"compile_sdk": 37, "target_sdk": 37})
        bad = {
            "missing-compile": SDK_XML.replace(b' android:compileSdkVersion="36"', b""),
            "missing-target": SDK_XML.replace(b' android:targetSdkVersion="36"', b""),
            "missing-uses-sdk": re.sub(rb"\s*<uses-sdk[^>]*/>", b"", SDK_XML),
            "old-compile": SDK_XML.replace(b'compileSdkVersion="36"', b'compileSdkVersion="35"'),
            "old-target": SDK_XML.replace(b'targetSdkVersion="36"', b'targetSdkVersion="35"'),
            "preview": SDK_XML.replace(b'targetSdkVersion="36"', b'targetSdkVersion="Baklava"'),
            "signed": SDK_XML.replace(b'targetSdkVersion="36"', b'targetSdkVersion="+36"'),
            "integer-overflow": SDK_XML.replace(b'targetSdkVersion="36"', b'targetSdkVersion="2147483648"'),
            "duplicate-attribute": SDK_XML.replace(b'android:targetSdkVersion="36"',
                                                    b'android:targetSdkVersion="36" android:targetSdkVersion="36"'),
            "duplicate-uses-sdk": SDK_XML.replace(b"<application />", b'<uses-sdk android:targetSdkVersion="36"/><application />'),
            "nested-uses-sdk": SDK_XML.replace(b"<application />", b'<application><uses-sdk android:targetSdkVersion="36"/></application>'),
            "wrong-namespace": SDK_XML.replace(b"http://schemas.android.com/apk/res/android", b"https://wrong.invalid"),
            "malformed": SDK_XML.replace(b"</manifest>", b"</other>"),
            "doctype": SDK_XML.replace(b"<manifest", b'<!DOCTYPE manifest [<!ENTITY x "36">]><manifest'),
            "not-utf8": SDK_XML + b"\xff",
            "oversize": b" " * (guard.BUNDLETOOL_STDOUT_MAX + 1),
        }
        for case, manifest in bad.items():
            with self.subTest(case=case), self.assertRaises(guard.Blocked):
                guard.sdk_from_manifest(manifest)

    def test_manifest_snapshot_is_bound_to_original_aab_and_pinned_tool_bytes(self):
        aab = self.base / "candidate.aab"
        aab_bytes = b"SYNTHETIC candidate input"
        jar_bytes = self.bundletool.read_bytes()
        java_path = self.base / "bin/java"
        java_bytes = java_path.read_bytes()
        java_digest = guard.sha(java_bytes)
        digest = guard.sha(aab_bytes)
        for changed in ("source-aab", "snapshot-aab", "source-tool", "snapshot-tool", "java-launcher"):
            with self.subTest(changed=changed):
                aab.write_bytes(aab_bytes)
                self.bundletool.write_bytes(jar_bytes)
                java_path.write_bytes(java_bytes)
                private = self.base / ("private-" + changed)
                private.mkdir()
                aab_snapshot = private / "manifest-candidate.aab"
                aab_snapshot.write_bytes(aab_bytes)

                def mutate(args, _root, _private):
                    self.assertEqual(args[-1], "--module=base")
                    stage_aab = Path(next(arg[len("--bundle="):] for arg in args if arg.startswith("--bundle=")))
                    stage_jar = Path(args[args.index("-jar") + 1])
                    victim = {"source-aab": aab, "snapshot-aab": stage_aab,
                              "source-tool": self.bundletool, "snapshot-tool": stage_jar,
                              "java-launcher": java_path}[changed]
                    victim.write_bytes(b"altered synthetic content")
                    return SDK_XML

                with patch.object(guard, "run_bounded_tool", side_effect=mutate):
                    with self.assertRaises(guard.Blocked):
                        guard.inspect_aab_sdk(aab, aab_snapshot, digest, private, self.root,
                                              self.bundletool, str(java_path), java_digest)

    def test_manifest_failure_does_not_export_an_otherwise_valid_candidate(self):
        output = self.build_fixture()
        inspected = {"status": "pass", "signer_sha256": self.pin, "verified_payload_entries": 3}
        old_target = SDK_XML.replace(b'targetSdkVersion="36"', b'targetSdkVersion="35"')
        def tool(args, _root, _private, *, purpose="bundletool"):
            self.assertEqual(purpose, "signature" if "scripts/qa/VerifySignedBundle.java" in args else "bundletool")
            return json.dumps(inspected).encode() if "scripts/qa/VerifySignedBundle.java" in args else old_target
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard, "run_bounded_tool", side_effect=tool):
            with self.assertRaises(guard.Blocked):
                guard.build()
        self.assertEqual(list(output.iterdir()), [])
        self.assertFalse((self.base / "collect-android-signing").exists())
        self.assertFalse((self.root / "android/app/google-services.json").exists())

    def test_bounded_tool_enforces_output_exit_and_timeout_without_retaining_marker(self):
        private = self.base / "bounded-tool-private"
        private.mkdir()
        python = sys.executable
        commands = (
            ("stdout", "import sys; sys.stdout.write('x' * 5000)"),
            ("stderr", "import sys; sys.stderr.write('x' * 5000)"),
            ("exit", "import sys; sys.exit(8)"),
            ("timeout", "import time; time.sleep(10)"),
        )
        with patch.object(guard, "BUNDLETOOL_STDOUT_MAX", 1024), \
                patch.object(guard, "BUNDLETOOL_STDERR_MAX", 1024), \
                patch.object(guard, "BUNDLETOOL_TIMEOUT_SECONDS", .5):
            for case, source in commands:
                with self.subTest(case=case), self.assertRaises(guard.Blocked):
                    guard.run_bounded_tool([python, "-I", "-B", "-c", source], self.root, private)
                self.assertFalse((private / "owned-builder-group").exists())
        self.assertEqual(guard.run_bounded_tool([python, "-I", "-B", "-c", "print('ok')"], self.root, private), b"ok\n")
        self.assertEqual(guard.run_bounded_tool([python, "-I", "-B", "-c",
                                                "import os; print('KEY_PASSWORD' in os.environ)"],
                                               self.root, private), b"False\n")

    def test_bounded_tool_fake_streams_cover_success_limit_and_nonzero_exit(self):
        from unittest.mock import Mock

        for purpose, case in ((purpose, case) for purpose in ("signature", "bundletool")
                              for case in ("success", "output-bound", "stderr-bound", "nonzero")):
            with self.subTest(purpose=purpose, case=case):
                private = self.base / ("fake-tool-" + purpose + "-" + case)
                private.mkdir()
                out_read, out_write = os.pipe()
                err_read, err_write = os.pipe()
                os.write(out_write, b"x" * (101 if case == "output-bound" else 2))
                if case == "stderr-bound":
                    os.write(err_write, b"x" * 101)
                os.close(out_write)
                os.close(err_write)
                process = Mock(pid=123456, returncode=7 if case == "nonzero" else 0)
                process.stdout = os.fdopen(out_read, "rb", buffering=0)
                process.stderr = os.fdopen(err_read, "rb", buffering=0)
                process.wait.return_value = process.returncode
                with patch.object(guard.subprocess, "Popen", return_value=process) as launcher, \
                        patch.object(guard, "owned_group_exists", return_value=False), \
                        patch.object(guard.os, "killpg") as signal_group, \
                        patch.object(guard, "BUNDLETOOL_STDOUT_MAX", 100), \
                        patch.object(guard, "BUNDLETOOL_STDERR_MAX", 100):
                    if case == "success":
                        self.assertEqual(guard.run_bounded_tool(["/fake/tool"], self.root, private, purpose=purpose), b"xx")
                    else:
                        with self.assertRaises(guard.Blocked) as failure:
                            guard.run_bounded_tool(["/fake/tool"], self.root, private, purpose=purpose)
                        prefix = "ANDROID_SIGNATURE_INSPECTOR" if purpose == "signature" else "ANDROID_BUNDLETOOL"
                        suffix = "FAILED" if case == "nonzero" else "OUTPUT_BOUND"
                        self.assertEqual(str(failure.exception), prefix + "_" + suffix)
                self.assertEqual(launcher.call_args.kwargs["env"], {"PATH": "/usr/bin:/bin", "LC_ALL": "C"})
                self.assertTrue(launcher.call_args.kwargs["start_new_session"])
                self.assertEqual(launcher.call_args.kwargs["stdin"], subprocess.DEVNULL)
                signal_group.assert_not_called()
                self.assertFalse((private / "owned-builder-group").exists())

    def test_interrupted_tool_launch_retains_marker_and_blocks_cleanup_without_signalling(self):
        private = self.base / "collect-android-signing"
        private.mkdir()
        (private / "owned-stage").write_text("collect-android-candidate-v1\n")
        with patch.object(guard.subprocess, "Popen", side_effect=KeyboardInterrupt), \
                patch.object(guard.os, "killpg") as signal_group:
            with self.assertRaises(KeyboardInterrupt):
                guard.run_bounded_tool(["/synthetic/not-executed"], self.root, private)
            self.assertEqual((private / "owned-builder-group").read_text(), "starting\n")
            with self.assertRaises(guard.Blocked):
                guard.cleanup()
        signal_group.assert_not_called()
        self.assertTrue((private / "owned-builder-group").exists())

    def test_reaped_tool_group_is_never_signalled_and_unknown_survivors_remain_unresolved(self):
        from unittest.mock import Mock

        process = Mock(pid=123456, returncode=7)
        with patch.object(guard.os, "killpg") as signal_group, \
                patch.object(guard, "owned_group_exists", side_effect=[False, True]):
            self.assertTrue(guard.settle_bounded_tool(process))
            self.assertFalse(guard.settle_bounded_tool(process))
        signal_group.assert_not_called()
        process.poll.assert_not_called()
        live = Mock(pid=234567, returncode=None)
        live.poll.return_value = None
        with patch.object(guard.os, "killpg") as signal_group, \
                patch.object(guard, "wait_for_owned_group_exit", return_value=True):
            self.assertTrue(guard.settle_bounded_tool(live))
        signal_group.assert_called_once_with(live.pid, signal.SIGKILL)

    def test_transient_signing_cleanup_after_signature_refusal(self):
        output = self.build_fixture()
        calls = []

        def fake_build(root, child, log, private):
            calls.append(root)
            key = Path(child["COOL_ANDROID_STORE_FILE"])
            self.assertEqual(key.read_bytes(), b"SYNTHETIC NOT A KEYSTORE")
            self.assertEqual(key.stat().st_mode & 0o777, 0o600)
            self.assertNotIn("KEYSTORE_BASE64", child)
            self.assertEqual(child["COLLECT_BUILD_SOURCE_ID"], self.profile["COLLECT_BUILD_SOURCE_ID"])
            self.assertEqual(child["COOL_EXPECTED_UPLOAD_SIGNING_SHA256"], self.pin)
            self.assertEqual(child["COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY"], "false")
            self.assertNotEqual(log, subprocess.PIPE)
            self.assertTrue((self.root / "android/app/google-services.json").exists())
            return 0

        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", side_effect=fake_build), \
                patch.object(guard, "run_bounded_tool", return_value=b'{"status":"blocked"}'):
            with self.assertRaises(guard.Blocked):
                guard.build()
        self.assertEqual(calls, [self.root])
        self.assertFalse((self.base / "collect-android-signing").exists())
        self.assertFalse((self.root / "android/app/google-services.json").exists())
        self.assertFalse((output / "Collect.aab").exists())

    def test_interrupted_signature_inspector_retains_ownership_marker_and_snapshot(self):
        output = self.build_fixture()
        private = self.base / "collect-android-signing"
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard.subprocess, "Popen", side_effect=KeyboardInterrupt), \
                patch.object(guard.os, "killpg") as signal_group:
            with self.assertRaises(guard.Blocked) as failure:
                guard.build()
        signal_group.assert_not_called()
        self.assertIsInstance(failure.exception, guard.DiagnosticFailure)
        self.assertEqual(failure.exception.primary_reason, "ANDROID_SIGNATURE_INSPECTOR_INTERRUPTED")
        self.assertEqual(failure.exception.settlement_reason, "ANDROID_PROCESS_SETTLEMENT_UNCONFIRMED")
        self.assertEqual(failure.exception.cleanup_reason, "ANDROID_BUILDER_LIFECYCLE_UNRESOLVED")
        self.assertEqual((private / "owned-builder-group").read_text(), "starting\n")
        self.assertTrue((private / "manifest-candidate.aab").exists())
        self.assertFalse((private / "upload.keystore").exists())
        self.assertFalse((private / "build.log").exists())
        self.assertEqual(list(output.iterdir()), [])

    def test_signature_inspector_oversize_output_blocks_export_without_signalling_reaped_group(self):
        from unittest.mock import Mock

        output = self.build_fixture()
        out_read, out_write = os.pipe()
        err_read, err_write = os.pipe()
        os.write(out_write, b"x" * 101)
        os.close(out_write)
        os.close(err_write)
        process = Mock(pid=123456, returncode=0)
        process.stdout = os.fdopen(out_read, "rb", buffering=0)
        process.stderr = os.fdopen(err_read, "rb", buffering=0)
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard.subprocess, "Popen", return_value=process), \
                patch.object(guard, "owned_group_exists", return_value=False), \
                patch.object(guard.os, "killpg") as signal_group, \
                patch.object(guard, "BUNDLETOOL_STDOUT_MAX", 100):
            with self.assertRaises(guard.Blocked) as failure:
                guard.build()
        signal_group.assert_not_called()
        self.assertEqual(str(failure.exception), "ANDROID_SIGNATURE_INSPECTOR_OUTPUT_BOUND")
        self.assertEqual(list(output.iterdir()), [])
        self.assertFalse((self.base / "collect-android-signing").exists())

    def test_signature_inspector_timeout_retains_unconfirmed_group_and_snapshot(self):
        from unittest.mock import Mock

        output = self.build_fixture()
        private = self.base / "collect-android-signing"
        out_read, out_write = os.pipe()
        err_read, err_write = os.pipe()
        os.close(out_write)
        os.close(err_write)
        process = Mock(pid=123456, returncode=None)
        process.poll.return_value = None
        process.stdout = os.fdopen(out_read, "rb", buffering=0)
        process.stderr = os.fdopen(err_read, "rb", buffering=0)
        selector = Mock()
        selector.get_map.return_value = {"pending": True}
        selector.select.return_value = []
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard.subprocess, "Popen", return_value=process), \
                patch.object(guard.selectors, "DefaultSelector", return_value=selector), \
                patch.object(guard, "wait_for_owned_group_exit", return_value=False), \
                patch.object(guard.os, "killpg") as signal_group:
            with self.assertRaises(guard.Blocked) as failure:
                guard.build()
        signal_group.assert_called_once_with(process.pid, signal.SIGKILL)
        self.assertIsInstance(failure.exception, guard.DiagnosticFailure)
        self.assertEqual(failure.exception.primary_reason, "ANDROID_SIGNATURE_INSPECTOR_TIMEOUT")
        self.assertEqual(failure.exception.settlement_reason, "ANDROID_PROCESS_SETTLEMENT_UNCONFIRMED")
        self.assertEqual(failure.exception.cleanup_reason, "ANDROID_BUILDER_LIFECYCLE_UNRESOLVED")
        self.assertEqual((private / "owned-builder-group").read_text(), "123456\n")
        self.assertTrue((private / "manifest-candidate.aab").exists())
        self.assertFalse((private / "upload.keystore").exists())
        self.assertFalse((private / "build.log").exists())
        self.assertEqual(list(output.iterdir()), [])

    def assert_signature_launch_diagnostics(self, settlement):
        import contextlib
        import io

        output = self.build_fixture()
        private = self.base / "collect-android-signing"
        secret = "SYNTHETIC_PRIVATE_ALIAS_AND_PASSWORD"
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())))
            stack.enter_context(patch.object(guard, "source_check"))
            stack.enter_context(patch.object(guard, "environment_policy", return_value={}))
            stack.enter_context(patch.object(guard, "run_builder", return_value=0))
            stack.enter_context(patch.object(guard.subprocess, "Popen", side_effect=OSError(secret)))
            signal_group = stack.enter_context(patch.object(guard.os, "killpg"))
            if settlement == "known":
                stack.enter_context(patch.object(guard, "settle_bounded_tool", side_effect=guard.Blocked("ANDROID_BUILDER_GROUP_STATE_UNKNOWN")))
            elif settlement == "unknown":
                stack.enter_context(patch.object(guard, "settle_bounded_tool", side_effect=OSError(secret)))
            stack.enter_context(patch.object(sys, "argv", ["candidate", "build"]))
            stack.enter_context(contextlib.redirect_stdout(stdout))
            stack.enter_context(contextlib.redirect_stderr(stderr))
            self.assertEqual(guard.main(), 1)
        signal_group.assert_not_called()
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["reason"], "ANDROID_SIGNATURE_INSPECTOR_LAUNCH_FAILED")
        self.assertEqual(result["cleanup"], {"status": "blocked", "reason": "ANDROID_BUILDER_LIFECYCLE_UNRESOLVED"})
        if settlement == "known":
            self.assertEqual(result["process_settlement"], {"status": "blocked", "reason": "ANDROID_BUILDER_GROUP_STATE_UNKNOWN"})
        elif settlement == "unknown":
            self.assertEqual(result["process_settlement"], {"status": "blocked", "reason": "ANDROID_PROCESS_SETTLEMENT_FAILED"})
        else:
            self.assertEqual(result["process_settlement"], {"status": "blocked", "reason": "ANDROID_PROCESS_SETTLEMENT_UNCONFIRMED"})
        self.assertEqual((private / "owned-builder-group").read_text(), "starting\n")
        self.assertTrue((private / "manifest-candidate.aab").exists())
        self.assertFalse((private / "upload.keystore").exists())
        self.assertFalse((private / "build.log").exists())
        self.assertEqual(list(output.iterdir()), [])

    def test_signature_launch_and_cleanup_diagnostics_are_distinct_and_redacted(self):
        self.assert_signature_launch_diagnostics(None)

    def test_signature_launch_settlement_and_cleanup_diagnostics_are_all_preserved(self):
        self.assert_signature_launch_diagnostics("known")

    def test_signature_unknown_settlement_error_is_sanitized(self):
        self.assert_signature_launch_diagnostics("unknown")

    def test_signature_timeout_and_finalization_error_preserve_both_causes(self):
        import contextlib
        import io
        from unittest.mock import Mock

        output = self.build_fixture()
        private = self.base / "collect-android-signing"
        secret = "SYNTHETIC_PRIVATE_FINALIZATION_ERROR"
        out_read, out_write = os.pipe()
        err_read, err_write = os.pipe()
        os.close(out_write)
        os.close(err_write)
        process = Mock(pid=123456, returncode=None)
        process.stdout = os.fdopen(out_read, "rb", buffering=0)
        process.stderr = os.fdopen(err_read, "rb", buffering=0)
        selector = Mock()
        selector.get_map.return_value = {"pending": True}
        selector.select.return_value = []
        selector.close.side_effect = OSError(secret)
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard.subprocess, "Popen", return_value=process), \
                patch.object(guard.selectors, "DefaultSelector", return_value=selector), \
                patch.object(guard, "settle_bounded_tool", return_value=False), \
                patch.object(guard.os, "killpg") as signal_group, \
                patch.object(sys, "argv", ["candidate", "build"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        signal_group.assert_not_called()
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["reason"], "ANDROID_SIGNATURE_INSPECTOR_TIMEOUT")
        self.assertEqual(result["process_settlement"], {"status": "blocked", "reason": "ANDROID_PROCESS_SETTLEMENT_UNCONFIRMED"})
        self.assertEqual(result["finalization"], {"status": "blocked", "failures": [
            {"step": "selector_close", "reason": "ANDROID_PROCESS_FINALIZATION_FAILED"}]})
        self.assertEqual(result["cleanup"], {"status": "blocked", "reason": "ANDROID_BUILDER_LIFECYCLE_UNRESOLVED"})
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())
        self.assertEqual((private / "owned-builder-group").read_text(), "123456\n")
        self.assertEqual(list(output.iterdir()), [])

    def test_signature_settlement_and_all_finalization_errors_are_reported_separately(self):
        import contextlib
        import io
        from unittest.mock import Mock

        output = self.build_fixture()
        private = self.base / "collect-android-signing"
        secret = "SYNTHETIC_PRIVATE_MULTIPLE_ERRORS"
        process = Mock(pid=123456, returncode=None)
        for name in ("stdout", "stderr"):
            read_fd, write_fd = os.pipe()
            os.close(write_fd)
            stream = Mock()
            stream.fileno.return_value = read_fd

            def close_and_fail(fd=read_fd):
                os.close(fd)
                raise OSError(secret)

            stream.close.side_effect = close_and_fail
            setattr(process, name, stream)
        selector = Mock()
        selector.get_map.return_value = {"pending": True}
        selector.select.return_value = []
        selector.close.side_effect = OSError(secret)
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard.subprocess, "Popen", return_value=process), \
                patch.object(guard.selectors, "DefaultSelector", return_value=selector), \
                patch.object(guard, "settle_bounded_tool", side_effect=guard.Blocked("ANDROID_BUILDER_GROUP_STATE_UNKNOWN")), \
                patch.object(guard.os, "killpg") as signal_group, \
                patch.object(sys, "argv", ["candidate", "build"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        signal_group.assert_not_called()
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["reason"], "ANDROID_SIGNATURE_INSPECTOR_TIMEOUT")
        self.assertEqual(result["process_settlement"], {"status": "blocked", "reason": "ANDROID_BUILDER_GROUP_STATE_UNKNOWN"})
        self.assertEqual(result["finalization"], {"status": "blocked", "failures": [
            {"step": "selector_close", "reason": "ANDROID_PROCESS_FINALIZATION_FAILED"},
            {"step": "stdout_close", "reason": "ANDROID_PROCESS_FINALIZATION_FAILED"},
            {"step": "stderr_close", "reason": "ANDROID_PROCESS_FINALIZATION_FAILED"}]})
        self.assertEqual(result["cleanup"], {"status": "blocked", "reason": "ANDROID_BUILDER_LIFECYCLE_UNRESOLVED"})
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())
        self.assertEqual((private / "owned-builder-group").read_text(), "123456\n")
        self.assertEqual(list(output.iterdir()), [])

    def test_prelaunch_selector_failure_is_labeled_and_keeps_the_stage(self):
        import contextlib
        import io

        output = self.build_fixture()
        private = self.base / "collect-android-signing"
        secret = "SYNTHETIC_PRIVATE_SELECTOR_FAILURE"
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard.subprocess, "Popen") as launch, \
                patch.object(guard.selectors, "DefaultSelector", side_effect=OSError(secret)), \
                patch.object(guard.os, "killpg") as signal_group, \
                patch.object(sys, "argv", ["candidate", "build"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        launch.assert_not_called()
        signal_group.assert_not_called()
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["reason"], "ANDROID_SIGNATURE_INSPECTOR_IO_FAILED")
        self.assertEqual(result["process_settlement"], {"status": "blocked", "reason": "ANDROID_PROCESS_SETTLEMENT_UNCONFIRMED"})
        self.assertEqual(result["cleanup"], {"status": "blocked", "reason": "ANDROID_BUILDER_LIFECYCLE_UNRESOLVED"})
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())
        self.assertEqual((private / "owned-builder-group").read_text(), "starting\n")
        self.assertEqual(list(output.iterdir()), [])

    def test_marker_release_error_preserves_primary_and_cleanup_status(self):
        import contextlib
        import io
        from unittest.mock import Mock

        output = self.build_fixture()
        private = self.base / "collect-android-signing"
        secret = "SYNTHETIC_PRIVATE_MARKER_ERROR"
        out_read, out_write = os.pipe()
        err_read, err_write = os.pipe()
        os.write(out_write, b"x" * 101)
        os.close(out_write)
        os.close(err_write)
        process = Mock(pid=123456, returncode=0)
        process.stdout = os.fdopen(out_read, "rb", buffering=0)
        process.stderr = os.fdopen(err_read, "rb", buffering=0)
        actual_unlink = Path.unlink

        def fail_marker(path, *args, **kwargs):
            if path.name == "owned-builder-group":
                raise OSError(secret)
            return actual_unlink(path, *args, **kwargs)

        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard.subprocess, "Popen", return_value=process), \
                patch.object(guard, "owned_group_exists", return_value=False), \
                patch.object(guard.os, "killpg") as signal_group, \
                patch.object(guard, "BUNDLETOOL_STDOUT_MAX", 100), \
                patch.object(Path, "unlink", autospec=True, side_effect=fail_marker), \
                patch.object(sys, "argv", ["candidate", "build"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        signal_group.assert_not_called()
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["reason"], "ANDROID_SIGNATURE_INSPECTOR_OUTPUT_BOUND")
        self.assertEqual(result["finalization"], {"status": "blocked", "failures": [
            {"step": "marker_release", "reason": "ANDROID_PROCESS_FINALIZATION_FAILED"}]})
        self.assertEqual(result["cleanup"], {"status": "blocked", "reason": "ANDROID_BUILDER_LIFECYCLE_UNRESOLVED"})
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())
        self.assertEqual((private / "owned-builder-group").read_text(), "123456\n")
        self.assertEqual(list(output.iterdir()), [])

    def test_settled_signature_interrupt_is_labeled_without_traceback_or_secrets(self):
        import contextlib
        import io
        from unittest.mock import Mock

        output = self.build_fixture()
        secret = "SYNTHETIC_PRIVATE_SIGNATURE_INTERRUPT"
        out_read, out_write = os.pipe()
        err_read, err_write = os.pipe()
        os.close(out_write)
        os.close(err_write)
        process = Mock(pid=123456, returncode=None)
        process.stdout = os.fdopen(out_read, "rb", buffering=0)
        process.stderr = os.fdopen(err_read, "rb", buffering=0)
        selector = Mock()
        selector.get_map.return_value = {"pending": True}
        selector.select.side_effect = KeyboardInterrupt(secret)
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard.subprocess, "Popen", return_value=process), \
                patch.object(guard.selectors, "DefaultSelector", return_value=selector), \
                patch.object(guard, "settle_bounded_tool", return_value=True), \
                patch.object(guard.os, "killpg") as signal_group, \
                patch.object(sys, "argv", ["candidate", "build"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        signal_group.assert_not_called()
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["reason"], "ANDROID_SIGNATURE_INSPECTOR_INTERRUPTED")
        self.assertNotIn("cleanup", result)
        self.assertNotIn("process_settlement", result)
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())
        self.assertNotIn("Traceback", stderr.getvalue())
        self.assertFalse((self.base / "collect-android-signing").exists())
        self.assertEqual(list(output.iterdir()), [])

    def test_cleanup_only_failure_has_structured_redacted_status(self):
        import contextlib
        import io

        output = self.build_fixture()
        secret = "SYNTHETIC_PRIVATE_CLEANUP_ONLY"
        inspected = {"status": "pass", "signer_sha256": self.pin, "verified_payload_entries": 3}

        def tool(_args, _root, _private, *, purpose="bundletool"):
            return json.dumps(inspected).encode() if purpose == "signature" else SDK_XML

        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard, "run_bounded_tool", side_effect=tool), \
                patch.object(guard, "cleanup", side_effect=OSError(secret)), \
                patch.object(sys, "argv", ["candidate", "build"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["reason"], "ANDROID_CLEANUP_FAILED")
        self.assertEqual(result["cleanup"], {"status": "blocked", "reason": "ANDROID_CLEANUP_FAILED"})
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())
        self.assertTrue((self.base / "collect-android-signing").exists())
        self.assertTrue((output / "Collect.aab").exists())

    def test_standalone_cleanup_failure_has_structured_status(self):
        import contextlib
        import io

        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "cleanup", side_effect=guard.Blocked("ANDROID_PRIVATE_STAGE_NOT_OWNED")), \
                patch.object(sys, "argv", ["candidate", "cleanup"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["reason"], "ANDROID_CLEANUP_FAILED")
        self.assertEqual(result["cleanup"], {"status": "blocked", "reason": "ANDROID_PRIVATE_STAGE_NOT_OWNED"})
        self.assertEqual(stderr.getvalue(), "")

    def test_primary_and_unknown_cleanup_failure_are_redacted_and_kept_separate(self):
        import contextlib
        import io

        self.build_fixture()
        secret = "SYNTHETIC_PRIVATE_CLEANUP_DIAGNOSTIC"
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard, "run_bounded_tool", side_effect=guard.Blocked("ANDROID_SIGNATURE_INSPECTOR_TIMEOUT")), \
                patch.object(guard, "cleanup", side_effect=OSError(secret)), \
                patch.object(sys, "argv", ["candidate", "build"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["reason"], "ANDROID_SIGNATURE_INSPECTOR_TIMEOUT")
        self.assertEqual(result["cleanup"], {"status": "blocked", "reason": "ANDROID_CLEANUP_FAILED"})
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())

    def test_unallowlisted_blocked_exception_does_not_echo_secret_text(self):
        import contextlib
        import io

        secret_code = "ANDROID_SYNTHETIC_PRIVATE_SECRET"
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "policy_preflight", side_effect=guard.Blocked(secret_code)), \
                patch.object(sys, "argv", ["candidate", "policy"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        self.assertEqual(json.loads(stdout.getvalue())["reason"], "ANDROID_CANDIDATE_BLOCKED")
        self.assertNotIn(secret_code, stdout.getvalue() + stderr.getvalue())

    def test_unexpected_operation_error_is_blocked_without_traceback_or_secret(self):
        import contextlib
        import io

        secret = "SYNTHETIC_PRIVATE_UNEXPECTED_EXCEPTION"
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "policy_preflight", side_effect=RuntimeError(secret)), \
                patch.object(sys, "argv", ["candidate", "policy"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        self.assertEqual(json.loads(stdout.getvalue())["status"], "blocked")
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())
        self.assertNotIn("Traceback", stderr.getvalue())

    def test_operation_system_exit_is_labeled_without_secret(self):
        import contextlib
        import io

        secret = "SYNTHETIC_PRIVATE_SYSTEM_EXIT"
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "policy_preflight", side_effect=SystemExit(secret)), \
                patch.object(sys, "argv", ["candidate", "policy"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        self.assertEqual(json.loads(stdout.getvalue())["reason"], "ANDROID_OPERATION_ABORTED")
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())

    def test_multiple_settlement_reasons_remain_distinct(self):
        first = guard.DiagnosticFailure(guard.Blocked("ANDROID_SIGNATURE_INSPECTOR_TIMEOUT"),
                                        settlement=guard.Blocked("ANDROID_BUILDER_GROUP_STATE_UNKNOWN"))
        second = guard.DiagnosticFailure(first, settlement=guard.Blocked("ANDROID_BUILDER_GROUP_TEARDOWN_UNCONFIRMED"))
        result = guard.blocked_result("build", second)
        self.assertEqual(result["reason"], "ANDROID_SIGNATURE_INSPECTOR_TIMEOUT")
        self.assertEqual(result["process_settlement"], {"status": "blocked", "reason": "ANDROID_BUILDER_GROUP_STATE_UNKNOWN",
                                                        "additional_reasons": ["ANDROID_BUILDER_GROUP_TEARDOWN_UNCONFIRMED"]})

    def test_mutated_diagnostic_fields_are_revalidated_before_output(self):
        secret = "SYNTHETIC_PRIVATE_MUTATED_DIAGNOSTIC"
        failure = guard.DiagnosticFailure(guard.Blocked("ANDROID_SIGNATURE_INSPECTOR_TIMEOUT"))
        failure.primary_reason = secret
        failure.settlement_reasons = [secret]
        failure.finalization_failures = [{"step": secret, "reason": secret}]
        failure.cleanup_reason = secret
        result = guard.blocked_result("build", failure)
        self.assertEqual(result["reason"], "ANDROID_CANDIDATE_BLOCKED")
        self.assertEqual(result["process_settlement"]["reason"], "ANDROID_PROCESS_SETTLEMENT_FAILED")
        self.assertEqual(result["finalization"]["failures"], [{"step": "unknown", "reason": "ANDROID_PROCESS_FINALIZATION_FAILED"}])
        self.assertEqual(result["cleanup"]["reason"], "ANDROID_CLEANUP_FAILED")
        self.assertNotIn(secret, json.dumps(result))

    def test_invalid_signature_inspector_output_reports_safe_specific_reason(self):
        import contextlib
        import io

        self.build_fixture()
        secret = "SYNTHETIC_PRIVATE_INVALID_OUTPUT"
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard, "run_bounded_tool", return_value=("{" + secret).encode()), \
                patch.object(sys, "argv", ["candidate", "build"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        self.assertEqual(json.loads(stdout.getvalue())["reason"], "ANDROID_SIGNATURE_INSPECTOR_INVALID_OUTPUT")
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())

    def test_only_a_signature_and_provenance_bound_success_retains_the_eight_public_outputs(self):
        output = self.build_fixture()
        inspected = {"status": "pass", "signer_sha256": self.pin, "verified_payload_entries": 3}
        original = (self.root / guard.AAB).read_bytes()
        snapshot = self.base / "collect-android-signing/manifest-candidate.aab"
        observed = {}

        def tool(args, root, private, *, purpose="bundletool"):
            self.assertEqual(root, self.root)
            self.assertEqual(private, snapshot.parent)
            if "scripts/qa/VerifySignedBundle.java" in args:
                self.assertEqual(purpose, "signature")
                index = args.index("scripts/qa/VerifySignedBundle.java")
                self.assertEqual(Path(args[index + 1]), snapshot)
                self.assertEqual(args[index + 2], self.pin)
                self.assertEqual(snapshot.read_bytes(), original)
                self.assertFalse((snapshot.parent / "upload.keystore").exists())
                self.assertFalse((snapshot.parent / "build.log").exists())
                observed["signature_called"] = True
                return json.dumps(inspected).encode()
            self.assertIn("--bundle=" + str(snapshot), args)
            self.assertEqual(purpose, "bundletool")
            self.assertEqual(snapshot.read_bytes(), original)
            observed["manifest_called"] = True
            return SDK_XML

        actual_copy = guard.shutil.copyfile

        def track_copy(source, destination, *args, **kwargs):
            if Path(destination).name == "Collect.aab":
                observed["export_source"] = Path(source)
            return actual_copy(source, destination, *args, **kwargs)

        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard, "run_bounded_tool", side_effect=tool) as inspector, \
                patch.object(guard.shutil, "copyfile", side_effect=track_copy):
            guard.build()
        self.assertEqual(inspector.call_count, 2)
        self.assertTrue(observed["signature_called"] and observed["manifest_called"])
        self.assertEqual(observed["export_source"], snapshot)
        self.assertEqual({p.name for p in output.iterdir()}, {"Collect.aab", "Collect.apk", "inspection.json", "source-manifest.json", "public-profile.json", "build-manifest.json", "native-build.json", "environment-policy.json"})
        inspection = json.loads((output / "inspection.json").read_text())
        self.assertEqual(inspection["apk_sha256"], guard.sha((output / "Collect.apk").read_bytes()))
        self.assertEqual(inspection["aab_sdk"], {"module": "base", "aab_sha256": inspection["aab_sha256"],
                                                  "bundletool_sha256": guard.BUNDLETOOL_SHA256,
                                                  "java_launcher_sha256": guard.sha((self.base / "bin/java").read_bytes()),
                                                  "compile_sdk": 36, "target_sdk": 36})
        self.assertEqual((output / "Collect.apk").read_bytes(), (self.root / guard.APK).read_bytes())
        self.assertFalse(json.loads((output / "inspection.json").read_text())["publication"])
        self.assertFalse((self.base / "collect-android-signing").exists())
        self.assertFalse((self.root / "android/app/google-services.json").exists())

    def test_signature_uses_snapshot_when_original_is_temporarily_swapped_and_restored(self):
        output = self.build_fixture()
        original_path = self.root / guard.AAB
        original = original_path.read_bytes()
        snapshot = self.base / "collect-android-signing/manifest-candidate.aab"
        inspected = {"status": "pass", "signer_sha256": self.pin, "verified_payload_entries": 3}

        def tool(args, _root, _private, *, purpose="bundletool"):
            if "scripts/qa/VerifySignedBundle.java" not in args:
                self.assertEqual(purpose, "bundletool")
                return SDK_XML
            self.assertEqual(purpose, "signature")
            original_path.write_bytes(b"TEMPORARY DIFFERENT SYNTHETIC BUNDLE")
            try:
                index = args.index("scripts/qa/VerifySignedBundle.java")
                self.assertEqual(Path(args[index + 1]), snapshot)
                self.assertEqual(Path(args[index + 1]).read_bytes(), original)
            finally:
                original_path.write_bytes(original)
            return json.dumps(inspected).encode()

        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard, "run_bounded_tool", side_effect=tool):
            guard.build()
        self.assertEqual((output / "Collect.aab").read_bytes(), original)

    def assert_signature_change_blocks_export(self, change_snapshot):
        output = self.build_fixture()
        inspected = {"status": "pass", "signer_sha256": self.pin, "verified_payload_entries": 3}
        original_path = self.root / guard.AAB
        snapshot = self.base / "collect-android-signing/manifest-candidate.aab"

        def tool(args, _root, _private, *, purpose="bundletool"):
            self.assertEqual(purpose, "signature")
            index = args.index("scripts/qa/VerifySignedBundle.java")
            self.assertEqual(Path(args[index + 1]), snapshot)
            (snapshot if change_snapshot else original_path).write_bytes(b"CHANGED SYNTHETIC BUNDLE")
            return json.dumps(inspected).encode()

        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard, "run_bounded_tool", side_effect=tool) as inspector:
            with self.assertRaises(guard.Blocked):
                guard.build()
        self.assertEqual(inspector.call_count, 1)
        self.assertEqual(list(output.iterdir()), [])

    def test_source_change_during_signature_blocks_export(self):
        self.assert_signature_change_blocks_export(False)

    def test_snapshot_change_during_signature_blocks_export(self):
        self.assert_signature_change_blocks_export(True)

    def test_missing_changed_or_wrong_identity_apk_cannot_be_exported_with_valid_aab(self):
        for mutation in ("missing", "bytes", "identity"):
            with self.subTest(mutation=mutation):
                output = self.build_fixture()
                apk = self.root / guard.APK
                if mutation == "missing":
                    apk.unlink()
                elif mutation == "bytes":
                    apk.write_bytes(b"DIFFERENT SYNTHETIC APK")
                else:
                    path = self.root / ".cache/native-build/android.json"
                    native = json.loads(path.read_text())
                    native["artifact_metadata"]["apk"]["actual"]["package"] = "other.app"
                    path.write_text(json.dumps(native))
                with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                        patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                        patch.object(guard, "run_builder", return_value=0), \
                        patch.object(guard, "run_bounded_tool", return_value=json.dumps({"status": "pass", "signer_sha256": self.pin, "verified_payload_entries": 3}).encode()):
                    with self.assertRaises(guard.Blocked):
                        guard.build()
                self.assertEqual(list(output.iterdir()), [])
                # Remove only the isolated fixture artifacts for the next case.
                output.rmdir()
                (self.base / "collect-android-pristine" / guard.source_export.MANIFEST).unlink()
                (self.base / "collect-android-pristine").rmdir()
                import shutil
                shutil.rmtree(self.root / "build")

    def test_malformed_or_incomplete_signing_inputs_never_call_the_builder_and_leave_no_key(self):
        self.build_fixture()
        for changes in ({"KEYSTORE_BASE64": "invalid!"}, {"KEY_ALIAS": ""}, {"KEY_PASSWORD": ""}, {"STORE_PASSWORD": ""}):
            with self.subTest(fields=list(changes)), patch.dict(os.environ, changes), \
                    patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, b"{}")), \
                    patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                    patch.object(guard, "run_builder") as builder:
                with self.assertRaises((guard.Blocked, ValueError)):
                    guard.build()
                builder.assert_not_called()
                self.assertFalse((self.base / "collect-android-signing").exists())
                self.assertFalse((self.root / "android/app/google-services.json").exists())

    def test_changed_reviewed_source_blocks_before_any_transient_key_or_builder(self):
        self.build_fixture()
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, b"{}")), \
                patch.object(guard, "source_check", side_effect=guard.Blocked("ANDROID_REVIEWED_SOURCE_CHANGED")), \
                patch.object(guard, "run_builder") as builder:
            with self.assertRaises(guard.Blocked):
                guard.build()
        builder.assert_not_called()
        self.assertFalse((self.base / "collect-android-signing").exists())
        self.assertFalse((self.root / "android/app/google-services.json").exists())

    def test_changed_provider_input_is_refused_before_signed_artifact_inspection(self):
        output = self.build_fixture()

        def changed_provider(root, child, log, private):
            (self.root / "android/app/google-services.json").write_text("{}")
            return 0

        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", side_effect=changed_provider), \
                patch.object(guard, "run_bounded_tool") as inspector:
            with self.assertRaises(guard.Blocked):
                guard.build()
        inspector.assert_not_called()
        self.assertFalse((output / "Collect.aab").exists())
        self.assertFalse((self.root / "android/app/google-services.json").exists())

    def test_builder_error_text_is_never_printed_and_cleanup_runs_on_failure(self):
        import contextlib
        import io
        import sys

        self.build_fixture()
        output = io.StringIO()

        def failed_build(root, child, log, private):
            log.write(os.environ["KEY_ALIAS"].encode())
            return 1

        with patch.object(sys, "argv", ["candidate", "build"]), \
                patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, b"{}")), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", side_effect=failed_build), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            self.assertEqual(guard.main(), 1)
        self.assertNotIn(os.environ["KEY_ALIAS"], output.getvalue())
        self.assertEqual(json.loads(output.getvalue())["status"], "blocked")
        self.assertFalse((self.base / "collect-android-signing").exists())
        self.assertFalse((self.root / "android/app/google-services.json").exists())

    def test_cleanup_refuses_an_existing_unowned_directory(self):
        private = self.base / "collect-android-signing"
        private.mkdir()
        sentinel = private / "unrelated"
        sentinel.write_text("preserve")
        with self.assertRaises(guard.Blocked):
            guard.cleanup()
        self.assertEqual(sentinel.read_text(), "preserve")

    def test_builder_reaped_leader_with_unresolved_group_is_not_signalled_or_cleaned(self):
        from unittest.mock import Mock

        private = self.base / "collect-android-signing"
        private.mkdir()
        (private / "owned-stage").write_text("collect-android-candidate-v1\n")
        process = Mock(pid=123456, returncode=0)
        process.wait.return_value = 0
        with (private / "build.log").open("wb") as log, \
                patch.object(guard.subprocess, "Popen", return_value=process), \
                patch.object(guard, "owned_group_exists", return_value=True), \
                patch.object(guard.os, "killpg") as signal_group:
            with self.assertRaises(guard.Blocked):
                guard.run_builder(self.root, {}, log, private)
            with self.assertRaises(guard.Blocked):
                guard.cleanup()
        signal_group.assert_not_called()
        self.assertEqual((private / "owned-builder-group").read_text(), "123456\n")
        self.assertTrue((private / "build.log").exists())

    def test_builder_interrupted_before_handle_retains_marker_without_signalling(self):
        private = self.base / "collect-android-signing"
        private.mkdir()
        (private / "owned-stage").write_text("collect-android-candidate-v1\n")
        with (private / "build.log").open("wb") as log, \
                patch.object(guard.subprocess, "Popen", side_effect=KeyboardInterrupt), \
                patch.object(guard.os, "killpg") as signal_group:
            with self.assertRaises(KeyboardInterrupt):
                guard.run_builder(self.root, {}, log, private)
            with self.assertRaises(guard.Blocked):
                guard.cleanup()
        signal_group.assert_not_called()
        self.assertEqual((private / "owned-builder-group").read_text(), "starting\n")

    def test_builder_live_owned_group_gets_one_signal_and_retains_marker_if_unconfirmed(self):
        from unittest.mock import Mock

        private = self.base / "collect-android-signing"
        private.mkdir()
        (private / "owned-stage").write_text("collect-android-candidate-v1\n")
        process = Mock(pid=123456, returncode=None)
        process.wait.side_effect = subprocess.TimeoutExpired("inert fixture", 1)
        process.poll.return_value = None
        with (private / "build.log").open("wb") as log, \
                patch.object(guard.subprocess, "Popen", return_value=process), \
                patch.object(guard, "wait_for_owned_group_exit", return_value=False), \
                patch.object(guard.os, "killpg") as signal_group:
            with self.assertRaises(subprocess.TimeoutExpired):
                guard.run_builder(self.root, {}, log, private)
            with self.assertRaises(guard.Blocked):
                guard.cleanup()
        signal_group.assert_called_once_with(process.pid, signal.SIGKILL)
        self.assertEqual((private / "owned-builder-group").read_text(), "123456\n")

    def test_builder_timeout_and_cleanup_diagnostics_are_distinct_and_redacted(self):
        import contextlib
        import io
        from unittest.mock import Mock

        output = self.build_fixture()
        private = self.base / "collect-android-signing"
        secret = "SYNTHETIC_PRIVATE_BUILDER_COMMAND"
        process = Mock(pid=123456, returncode=None)
        process.wait.side_effect = subprocess.TimeoutExpired(secret, 1)
        process.poll.return_value = None
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard.subprocess, "Popen", return_value=process), \
                patch.object(guard, "wait_for_owned_group_exit", return_value=False), \
                patch.object(guard.os, "killpg") as signal_group, \
                patch.object(sys, "argv", ["candidate", "build"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        signal_group.assert_called_once_with(process.pid, signal.SIGKILL)
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["reason"], "ANDROID_BUILDER_TIMEOUT")
        self.assertEqual(result["process_settlement"], {"status": "blocked", "reason": "ANDROID_PROCESS_SETTLEMENT_UNCONFIRMED"})
        self.assertEqual(result["cleanup"], {"status": "blocked", "reason": "ANDROID_BUILDER_LIFECYCLE_UNRESOLVED"})
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())
        self.assertEqual((private / "owned-builder-group").read_text(), "123456\n")
        self.assertTrue((private / "upload.keystore").exists())
        self.assertTrue((private / "build.log").exists())
        self.assertEqual(list(output.iterdir()), [])

    def assert_settled_builder_failure_is_redacted(self, failure, expected):
        import contextlib
        import io
        from unittest.mock import Mock

        output = self.build_fixture()
        secret = "SYNTHETIC_PRIVATE_SETTLED_BUILDER"
        process = Mock(pid=123456, returncode=None)
        process.wait.side_effect = KeyboardInterrupt(secret) if failure == "interrupt" else subprocess.TimeoutExpired(secret, 1)
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard.subprocess, "Popen", return_value=process), \
                patch.object(guard, "settle_bounded_tool", return_value=True), \
                patch.object(guard.os, "killpg") as signal_group, \
                patch.object(sys, "argv", ["candidate", "build"]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(guard.main(), 1)
        signal_group.assert_not_called()
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["reason"], expected)
        self.assertNotIn("process_settlement", result)
        self.assertNotIn("cleanup", result)
        self.assertNotIn(secret, stdout.getvalue() + stderr.getvalue())
        self.assertNotIn("Traceback", stderr.getvalue())
        self.assertFalse((self.base / "collect-android-signing").exists())
        self.assertEqual(list(output.iterdir()), [])

    def test_settled_builder_interrupt_is_labeled_and_redacted(self):
        self.assert_settled_builder_failure_is_redacted("interrupt", "ANDROID_BUILDER_INTERRUPTED")

    def test_settled_builder_timeout_is_labeled_and_redacted(self):
        self.assert_settled_builder_failure_is_redacted("timeout", "ANDROID_BUILDER_TIMEOUT")

    def inert_builder_tree(self, normal_exit=False):
        scripts = self.root / "scripts"
        scripts.mkdir()
        fixture = scripts / "inert_builder.py"
        fixture.write_text('''import json,os,signal,subprocess,sys,time
from pathlib import Path
signal.signal(signal.SIGTERM, signal.SIG_IGN)
role=sys.argv[1]
record=Path(sys.argv[2])
if role=="parent": assert os.getpgrp()==os.getpid(), "Inert fixture requires an isolated owned group"
with record.open("a") as stream:
 stream.write(json.dumps({"pid":os.getpid(),"group":os.getpgrp(),"role":role})+"\\n")
 stream.flush()
if role=="parent":
 subprocess.Popen([sys.executable,__file__,"child",str(record)])
elif role=="child":
 subprocess.Popen([sys.executable,__file__,"grandchild",str(record)])
if role=="parent" and sys.argv[-1]=="normal-exit":
 deadline=time.monotonic()+5
 while len(record.read_text().splitlines())<3 and time.monotonic()<deadline: time.sleep(.01)
 sys.exit(0)
while True: time.sleep(.05)
''')
        record = scripts / "inert-pids.jsonl"
        mode = "normal-exit" if normal_exit else "timeout"
        (scripts / "android_play_store_build.sh").write_text(
            "exec " + shlex.quote(sys.executable) + " " + shlex.quote(str(fixture))
            + " parent " + shlex.quote(str(record)) + " " + mode + "\n")

        def emergency_teardown():
            # Only this fixture's newly created group is eligible for fallback
            # teardown if an assertion fails; no source/SDK process is involved.
            if record.exists():
                parent = json.loads(record.read_text().splitlines()[0])
                if parent["pid"] == parent["group"]:
                    try:
                        os.killpg(parent["group"], signal.SIGKILL)
                    except ProcessLookupError:
                        pass

        self.addCleanup(emergency_teardown)
        return record

    def assert_tree_absent_before_cleanup(self, record):
        rows = [json.loads(line) for line in record.read_text().splitlines()]
        self.assertEqual({row["role"] for row in rows}, {"parent", "child", "grandchild"})
        self.assertEqual(len({row["group"] for row in rows}), 1)
        self.assertEqual(next(row["pid"] for row in rows if row["role"] == "parent"), rows[0]["group"])
        for row in rows:
            with self.assertRaises(ProcessLookupError):
                os.kill(row["pid"], 0)
        with self.assertRaises(ProcessLookupError):
            os.killpg(rows[0]["group"], 0)
        private = self.base / "collect-android-signing"
        self.assertTrue((private / "upload.keystore").exists())
        self.assertTrue((private / "build.log").exists())
        self.assertTrue((self.root / "android/app/google-services.json").exists())
        self.assertFalse((private / "owned-builder-group").exists())

    def exercise_actual_tree_teardown(self, normal_exit=False, interrupt_wait=False):
        output = self.build_fixture()
        record = self.inert_builder_tree(normal_exit)
        actual_cleanup = guard.cleanup
        observed = []

        def checked_cleanup():
            self.assert_tree_absent_before_cleanup(record)
            observed.append(True)
            actual_cleanup()

        actual_popen = subprocess.Popen

        def interrupted_popen(*args, **kwargs):
            process = actual_popen(*args, **kwargs)
            actual_wait = process.wait

            def first_wait(timeout=None):
                process.wait = actual_wait
                deadline = time.monotonic() + 5
                while (not record.exists() or len(record.read_text().splitlines()) < 3) and time.monotonic() < deadline:
                    time.sleep(.01)
                raise KeyboardInterrupt()

            process.wait = first_wait
            return process

        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "cleanup", side_effect=checked_cleanup), \
                patch.object(guard, "BUILD_TIMEOUT_SECONDS", 1), \
                patch.object(guard, "BUILD_TERM_GRACE_SECONDS", .1), \
                patch.object(guard, "BUILD_KILL_GRACE_SECONDS", 5), \
                patch.object(guard.subprocess, "Popen", side_effect=interrupted_popen if interrupt_wait else actual_popen):
            expected = KeyboardInterrupt if interrupt_wait else guard.Blocked if normal_exit else subprocess.TimeoutExpired
            with self.assertRaises(expected):
                guard.build()
        self.assertEqual(observed, [True])
        self.assertFalse((self.base / "collect-android-signing").exists())
        self.assertFalse((self.root / "android/app/google-services.json").exists())
        self.assertFalse((output / "Collect.aab").exists())

    def test_timeout_kills_TERM_ignoring_child_and_grandchild_before_private_cleanup(self):
        self.exercise_actual_tree_teardown()

    def test_reaped_wrapper_with_group_survivors_retains_private_stage(self):
        # Once the leader is reaped, its numeric group ID can be reused.  The
        # candidate must retain its private stage instead of signalling a group
        # it can no longer prove it owns. The fixture's own cleanup tears down
        # only the synthetic group it started.
        output = self.build_fixture()
        record = self.inert_builder_tree(normal_exit=True)
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "BUILD_TIMEOUT_SECONDS", 1):
            with self.assertRaises(guard.DiagnosticFailure) as caught:
                guard.build()
        self.assertEqual(caught.exception.primary_reason, "ANDROID_BUILDER_DESCENDANTS_SURVIVED")
        self.assertEqual(caught.exception.cleanup_reason, "ANDROID_BUILDER_LIFECYCLE_UNRESOLVED")
        self.assertEqual(len(record.read_text().splitlines()), 3)
        private = self.base / "collect-android-signing"
        self.assertTrue((private / "owned-builder-group").exists())
        self.assertTrue((private / "upload.keystore").exists())
        self.assertTrue((private / "build.log").exists())
        self.assertTrue((self.root / "android/app/google-services.json").exists())
        self.assertFalse((output / "Collect.aab").exists())

    def test_BaseException_wait_path_tears_down_owned_tree_before_private_cleanup(self):
        self.exercise_actual_tree_teardown(interrupt_wait=True)

    def test_unresolved_group_marker_retains_all_private_files_without_signalling_stale_group(self):
        private = self.base / "collect-android-signing"
        private.mkdir()
        (private / "owned-stage").write_text("collect-android-candidate-v1\n")
        (private / "owned-builder-group").write_text("123456\n")
        (private / "google-services-created").write_text("owned\n")
        for path in (private / "upload.keystore", private / "build.log", self.root / "android/app/google-services.json"):
            path.write_text("SYNTHETIC retained fixture")
        with patch.object(guard.os, "killpg") as signal_group:
            with self.assertRaises(guard.Blocked):
                guard.cleanup()
        signal_group.assert_not_called()
        self.assertTrue((private / "upload.keystore").exists())
        self.assertTrue((private / "build.log").exists())
        self.assertTrue((self.root / "android/app/google-services.json").exists())

    def test_uncertain_owned_group_teardown_keeps_marker_and_refuses_cleanup(self):
        private = self.base / "collect-android-signing"
        private.mkdir()
        (private / "owned-stage").write_text("collect-android-candidate-v1\n")
        with (private / "build.log").open("wb") as log, \
                patch.object(guard.subprocess, "Popen") as launch, \
                patch.object(guard.os, "killpg", side_effect=PermissionError):
            process = launch.return_value
            process.pid = 123456
            process.wait.side_effect = subprocess.TimeoutExpired("inert fixture", 1)
            with self.assertRaises(guard.Blocked):
                guard.run_builder(self.root, {}, log, private)
        self.assertEqual((private / "owned-builder-group").read_text(), "123456\n")
        with self.assertRaises(guard.Blocked):
            guard.cleanup()
        self.assertTrue((private / "build.log").exists())

    def test_unknown_group_probe_needs_positive_absence_and_reap_within_bound(self):
        from unittest.mock import Mock

        process = Mock(pid=123456)
        process.poll.return_value = 0
        with patch.object(guard, "owned_group_exists", side_effect=[guard.Blocked("ANDROID_BUILDER_GROUP_STATE_UNKNOWN"), False]), \
                patch.object(guard.time, "sleep"):
            self.assertTrue(guard.wait_for_owned_group_exit(process, 1))
        process.wait.assert_called_once_with(timeout=0)
        process.reset_mock()
        with patch.object(guard, "owned_group_exists", side_effect=guard.Blocked("ANDROID_BUILDER_GROUP_STATE_UNKNOWN")):
            self.assertFalse(guard.wait_for_owned_group_exit(process, 0))
        process.wait.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
