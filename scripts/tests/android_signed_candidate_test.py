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


class CandidateBoundaryTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.root = self.base / "repo"
        (self.root / "android/app").mkdir(parents=True)
        (self.root / "pubspec.yaml").write_text("name: collect_app\nversion: 1.0.8+65\n")
        self.commit = "a" * 40
        self.pin = "B" * 64
        provider = json.dumps({"client": [{"client_info": {"android_client_info": {"package_name": guard.PACKAGE}}}]})
        self.env = {"GITHUB_WORKSPACE": str(self.root), "RUNNER_TEMP": str(self.base),
                    "GITHUB_REPOSITORY": "ikanisa/COOL", "GITHUB_REF": "refs/heads/main", "GITHUB_SHA": self.commit,
                    "COLLECT_ANDROID_EXPECTED_COMMIT": self.commit, "COLLECT_ANDROID_SOURCE_SHA256": "c" * 64,
                    "COLLECT_ANDROID_APPROVED_UPLOAD_CERT_SHA256": self.pin,
                    "PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER": "123456789012", "COLLECT_ANDROID_GOOGLE_SERVICES_JSON": provider,
                    "SUPABASE_URL": guard.native_build_config.PROJECT, "SUPABASE_API_URL": guard.native_build_config.ADMIN,
                    "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_syntheticPublicKey1234",
                    "AUTH_CAPTCHA_SITE_KEY": "1x00000000000000000000AA", "FLUTTER_ROOT": str(self.base / "unused-sdk"),
                    "KEYSTORE_BASE64": base64.b64encode(b"SYNTHETIC NOT A KEYSTORE").decode(),
                    "KEY_ALIAS": "synthetic-alias", "KEY_PASSWORD": "synthetic-password", "STORE_PASSWORD": "synthetic-password"}
        self.profile = guard.native_build_config.configuration(self.env, "android", self.root / "pubspec.yaml")
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

    def test_transient_signing_cleanup_after_signature_refusal(self):
        output = self.build_fixture()
        calls = []

        def fake_build(root, child, log, private):
            calls.append(root)
            key = Path(child["COOL_ANDROID_STORE_FILE"])
            self.assertEqual(key.read_bytes(), b"SYNTHETIC NOT A KEYSTORE")
            self.assertEqual(key.stat().st_mode & 0o777, 0o600)
            self.assertNotIn("KEYSTORE_BASE64", child)
            self.assertEqual(child["COOL_EXPECTED_UPLOAD_SIGNING_SHA256"], self.pin)
            self.assertEqual(child["COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY"], "false")
            self.assertNotEqual(log, subprocess.PIPE)
            self.assertTrue((self.root / "android/app/google-services.json").exists())
            return 0

        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", side_effect=fake_build), \
                patch.object(guard, "command", return_value=b'{"status":"blocked"}'):
            with self.assertRaises(guard.Blocked):
                guard.build()
        self.assertEqual(calls, [self.root])
        self.assertFalse((self.base / "collect-android-signing").exists())
        self.assertFalse((self.root / "android/app/google-services.json").exists())
        self.assertFalse((output / "Collect.aab").exists())

    def test_only_a_signature_and_provenance_bound_success_retains_the_eight_public_outputs(self):
        output = self.build_fixture()
        inspected = {"status": "pass", "signer_sha256": self.pin, "verified_payload_entries": 3}
        with patch.object(guard, "configuration_and_approval", return_value=(self.record, self.profile, self.env["COLLECT_ANDROID_GOOGLE_SERVICES_JSON"].encode())), \
                patch.object(guard, "source_check"), patch.object(guard, "environment_policy", return_value={}), \
                patch.object(guard, "run_builder", return_value=0), \
                patch.object(guard, "command", return_value=json.dumps(inspected).encode()) as inspector:
            guard.build()
        self.assertTrue(all(key not in inspector.call_args.kwargs["env"]
                            for key in ("KEYSTORE_BASE64", "KEY_ALIAS", "KEY_PASSWORD", "STORE_PASSWORD",
                                        "GH_TOKEN", "GITHUB_TOKEN", "REVIEWED_ANDROID_APPROVAL_RECORD")))
        self.assertEqual({p.name for p in output.iterdir()}, {"Collect.aab", "Collect.apk", "inspection.json", "source-manifest.json", "public-profile.json", "build-manifest.json", "native-build.json", "environment-policy.json"})
        inspection = json.loads((output / "inspection.json").read_text())
        self.assertEqual(inspection["apk_sha256"], guard.sha((output / "Collect.apk").read_bytes()))
        self.assertEqual((output / "Collect.apk").read_bytes(), (self.root / guard.APK).read_bytes())
        self.assertFalse(json.loads((output / "inspection.json").read_text())["publication"])
        self.assertFalse((self.base / "collect-android-signing").exists())
        self.assertFalse((self.root / "android/app/google-services.json").exists())

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
                        patch.object(guard, "command", return_value=json.dumps({"status": "pass", "signer_sha256": self.pin, "verified_payload_entries": 3}).encode()):
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
                patch.object(guard, "command") as inspector:
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

    def test_ordinary_wrapper_exit_with_group_survivors_is_refused_and_tears_down_before_cleanup(self):
        self.exercise_actual_tree_teardown(normal_exit=True)

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
