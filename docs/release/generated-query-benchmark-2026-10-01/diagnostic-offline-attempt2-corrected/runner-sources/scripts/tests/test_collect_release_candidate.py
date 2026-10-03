#!/usr/bin/env python3
"""Synthetic Git/SDK/stdio tests; never contact production or load Keychain."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "qa/collect_release_candidate.py"
SPEC = importlib.util.spec_from_file_location("collect_candidate", SOURCE)
candidate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(candidate)


class CandidateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / "repo"
        self.root.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        for name in candidate.REQUIRED:
            self.write(name, "synthetic source")
        self.write(".fvmrc", json.dumps({"flutter": "3.44.4"}))
        self.write(".dvmrc", "2.5.6\n")
        self.write("tools/collect-notification-mcp/package.json", json.dumps({"dependencies": {"@modelcontextprotocol/server": "2.0.0", "zod": "4.5.4"}}))
        self.sdk = self.base / "flutter"
        (self.sdk / "bin/cache").mkdir(parents=True)
        (self.sdk / "bin/flutter").write_text("synthetic launcher")
        (self.sdk / "bin/cache/flutter.version.json").write_text(json.dumps({"frameworkVersion": "3.44.4", "frameworkRevision": "synthetic_revision", "dartSdkVersion": "3.12.2"}))
        self.destination = self.base / "candidate"

    def write(self, name, content="synthetic source"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def export(self):
        return candidate.export_candidate(self.root, self.destination, self.sdk)

    def manifest(self):
        return json.loads((self.destination / candidate.MANIFEST).read_text())

    def test_tracked_dirty_and_required_untracked_source_are_preserved_with_exact_readback(self):
        tracked = self.write("lib/tracked.dart", "original")
        subprocess.run(["git", "add", "lib/tracked.dart"], cwd=self.root, check=True)
        tracked.write_text("changed current bytes")
        untracked = self.write("lib/untracked_required.dart", "new current bytes")
        result = self.export()
        self.assertEqual(result["status"], "pass")
        self.assertEqual((self.destination / tracked.relative_to(self.root)).read_bytes(), tracked.read_bytes())
        self.assertEqual((self.destination / untracked.relative_to(self.root)).read_bytes(), untracked.read_bytes())
        self.assertTrue(all(value is False for value in result["approvals"].values()))
        self.assertEqual(candidate.verify_candidate(self.destination, self.root, result["manifest_sha256"])["changes"], [])

    def test_private_indexed_files_ignored_inputs_caches_artifacts_and_qa_dumps_are_excluded(self):
        self.write(".gitignore", "lib/ignored.dart\n")
        self.write("lib/ignored.dart", "ignored private input")
        paths = [".env.json", "android/key.properties", "android/app/google-services.json", "ios/Runner/GoogleService-Info.plist",
                 "android/upload.jks", "ios/AuthKey.p8", "tools/x/node_modules/data.js", "lib/build/generated.dart",
                 "supabase/.temp/database-url", "docs/release/raw-customer.json", "output/raw.json", "test/payload.xlsx",
                 "test/failures/customer.png", "ios/report.dSYM/Contents/data"]
        for name in paths:
            self.write(name, "DO_NOT_COPY_PRIVATE")
        subprocess.run(["git", "add", "-f", ".env.json", "android/key.properties"], cwd=self.root, check=True)
        self.export()
        for name in paths + ["lib/ignored.dart"]:
            self.assertFalse((self.destination / name).exists(), name)
        self.assertEqual(self.manifest()["private_or_ignored_inputs_copied"], False)
        self.assertIn("private_configuration", self.manifest()["excluded_file_counts"])

    def test_private_material_in_an_innocent_source_file_blocks_before_export(self):
        for value in ["-----BEGIN PRIVATE KEY-----\n" + "A" * 32, "ghp_" + "a" * 40, "sb_secret_" + "x" * 30]:
            self.write("lib/public.dart", value)
            with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_CREDENTIAL_PATTERN"):
                self.export()
            self.assertFalse(self.destination.exists())

    def test_upstream_auth_fixture_tests_are_excluded_but_runtime_provenance_and_app_tests_remain(self):
        self.write("third_party/gotrue/test/client_test.dart", "sb_secret_" + "x" * 30)
        retained = ["third_party/gotrue/lib/gotrue.dart", "third_party/gotrue/pubspec.yaml",
                    "third_party/gotrue/LICENSE", "third_party/gotrue/COLLECT_FORK.md",
                    "third_party/gotrue/UPSTREAM-SHA", "test/collect_auth_test.dart"]
        for name in retained:
            self.write(name)
        self.export()
        self.assertFalse((self.destination / "third_party/gotrue/test/client_test.dart").exists())
        self.assertEqual(self.manifest()["excluded_file_counts"]["upstream_qa_fixture_source"], 1)
        recorded = self.manifest()["excluded_upstream_qa_source"]["third_party/gotrue/test/client_test.dart"]
        self.assertEqual(recorded["sha256"], candidate.sha((self.root / "third_party/gotrue/test/client_test.dart").read_bytes()))
        self.assertEqual(recorded["reason"], "upstream_qa_fixture_source")
        self.assertNotIn("sb_secret_", json.dumps(self.manifest()))
        for name in retained:
            self.assertEqual((self.destination / name).read_bytes(), (self.root / name).read_bytes())
        self.write("third_party/gotrue/test/client_test.dart", "updated upstream regression fixture")
        self.assertIn({"path": "third_party/gotrue/test/client_test.dart", "reason": "excluded_source_changed"},
                      candidate.verify_candidate(self.destination, self.root)["changes"])

    def test_a_private_key_detection_rule_is_source_code_without_private_key_material(self):
        self.write("scripts/check.py", 'forbidden_header = "-----BEGIN PRIVATE KEY-----"\n')
        self.assertEqual(self.export()["status"], "pass")

    def test_authenticated_jwt_and_opaque_refresh_token_are_excluded_public_anon_is_distinct(self):
        def token(role):
            header = base64.urlsafe_b64encode(b'{"alg":"HS256"}').decode().rstrip("=")
            body = base64.urlsafe_b64encode(json.dumps({"role": role, "exp": 1234567890}).encode()).decode().rstrip("=")
            return header + "." + body + "." + "z" * 32
        self.write("contracts/input.json", json.dumps({"token": token("authenticated")}))
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_CREDENTIAL_PATTERN"):
            self.export()
        self.write("contracts/input.json", json.dumps({"refresh_token": "opaque_private_value"}))
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_CREDENTIAL_PATTERN"):
            self.export()
        self.write("contracts/input.json", json.dumps({"public_anon": token("anon")}))
        self.assertEqual(self.export()["status"], "pass")

    def test_selected_file_tampering_and_extra_candidate_payloads_are_reported_per_file(self):
        self.export()
        (self.destination / "lib/main.dart").write_text("tampered")
        (self.destination / "extra.json").write_text("unlisted")
        report = candidate.verify_candidate(self.destination, self.root)
        self.assertEqual(report["status"], "blocked")
        self.assertIn({"path": "lib/main.dart", "reason": "candidate_changed"}, report["changes"])
        self.assertIn({"path": "extra.json", "reason": "candidate_unlisted_file"}, report["changes"])

    def test_source_edits_additions_removals_and_executable_mode_changes_stale_the_export(self):
        removable = self.write("lib/remove.dart")
        self.export()
        self.write("lib/main.dart", "changed")
        self.write("lib/added.dart")
        removable.unlink()
        (self.root / "lib/main_admin.dart").chmod(0o755)
        changes = candidate.verify_candidate(self.destination, self.root)["changes"]
        for path, reason in [("lib/main.dart", "source_changed"), ("lib/added.dart", "source_added"),
                             ("lib/remove.dart", "source_removed"), ("lib/main_admin.dart", "source_changed")]:
            self.assertIn({"path": path, "reason": reason}, changes)

    def test_external_manifest_hash_detects_metadata_rewrite_and_approval_flags_cannot_be_promoted(self):
        result = self.export()
        manifest = self.manifest()
        manifest["toolchain"]["node"]["version"] = "rewritten"
        (self.destination / candidate.MANIFEST).write_bytes(candidate.canonical(manifest))
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_MANIFEST_HASH_CHANGED"):
            candidate.verify_candidate(self.destination, expected_manifest_sha256=result["manifest_sha256"])
        manifest["approvals"]["reviewed"] = True
        (self.destination / candidate.MANIFEST).write_bytes(candidate.canonical(manifest))
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_MANIFEST_INVALID"):
            candidate.verify_candidate(self.destination)

    def test_internal_external_and_ancestor_source_symlinks_are_refused(self):
        target = self.write("lib/real.dart")
        outside = self.base / "outside.dart"
        outside.write_text("private outside")
        for target_path in [target, outside]:
            link = self.root / "lib/alias.dart"
            link.symlink_to(target_path)
            with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_SYMLINK_REFUSED"):
                self.export()
            link.unlink()
        folder = self.base / "outside_dir"
        folder.mkdir()
        (folder / "file.dart").write_text("outside")
        (self.root / "lib/linked").symlink_to(folder, target_is_directory=True)
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_SYMLINK_REFUSED"):
            self.export()

    def test_candidate_symlink_is_never_followed(self):
        self.export()
        path = self.destination / "lib/main.dart"
        path.unlink()
        path.symlink_to(self.root / "lib/main.dart")
        report = candidate.verify_candidate(self.destination)
        self.assertEqual(report["status"], "blocked")
        self.assertTrue(any(item["reason"] == "candidate_symlink" for item in report["changes"]))

    def test_required_lock_or_entrypoint_absence_blocks_without_claiming_build_readiness(self):
        (self.root / "pubspec.lock").unlink()
        with self.assertRaises(candidate.ReleaseError) as blocked:
            self.export()
        self.assertEqual(blocked.exception.code, "CANDIDATE_PREREQUISITE_MISSING")
        self.assertIn("pubspec.lock", blocked.exception.paths)
        self.assertFalse(self.destination.exists())

    def test_duplicate_current_migration_versions_block_before_copy(self):
        paths = ["supabase/migrations/20260930230000_first.sql", "supabase/migrations/20260930230000_other.sql"]
        for name in paths:
            self.write(name, "select 1;")
        with self.assertRaises(candidate.ReleaseError) as blocked:
            self.export()
        self.assertEqual(blocked.exception.code, "CANDIDATE_MIGRATION_VERSION_DUPLICATE")
        self.assertEqual(blocked.exception.paths, paths)
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.base.glob(".collect-export-*")), [])

    def test_migration_calendar_time_and_filename_validity_are_prerequisites(self):
        for version in ["20260931000000", "20260930240000", "20260930126000", "20260930000060", "20260930"]:
            name = "supabase/migrations/" + version + "_invalid.sql"
            path = self.write(name, "select 1;")
            with self.assertRaises(candidate.ReleaseError) as blocked:
                self.export()
            self.assertEqual(blocked.exception.code, "CANDIDATE_MIGRATION_VERSION_INVALID")
            self.assertEqual(blocked.exception.paths, [name])
            self.assertFalse(self.destination.exists())
            path.unlink()

    def test_deleted_indexed_migration_does_not_collide_with_current_replacement(self):
        old = self.write("supabase/migrations/20260930230000_old.sql", "select 1;")
        subprocess.run(["git", "add", old.relative_to(self.root).as_posix()], cwd=self.root, check=True)
        old.unlink()
        current = "supabase/migrations/20260930230000_new.sql"
        self.write(current, "select 1;")
        self.export()
        self.assertEqual(self.manifest()["migration_versions"], {"20260930230000": current})
        self.assertIn(old.relative_to(self.root).as_posix(), self.manifest()["absent_indexed_source_paths"])

    def test_only_the_explicit_preserved_legacy_minute_versions_are_accepted(self):
        preserved = "supabase/migrations/202605230017_legacy.sql"
        self.write(preserved, "select 1;")
        self.export()
        self.assertEqual(self.manifest()["migration_versions"], {"202605230017": preserved})
        self.assertEqual(len(self.manifest()["policy"]["migration_versions"]["preserved_legacy_minute_versions"]), 19)
        added = "supabase/migrations/202609302300_new_minute_version.sql"
        self.write(added, "select 1;")
        with self.assertRaises(candidate.ReleaseError) as blocked:
            candidate.source_snapshot(self.root)
        self.assertEqual(blocked.exception.code, "CANDIDATE_MIGRATION_VERSION_INVALID")
        self.assertEqual(blocked.exception.paths, [added])

    def test_pinned_installed_flutter_and_required_runtime_are_checked(self):
        metadata = self.sdk / "bin/cache/flutter.version.json"
        metadata.write_text(json.dumps({"frameworkVersion": "3.44.3"}))
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_FLUTTER_PIN_MISMATCH"):
            self.export()
        metadata.unlink()
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_TOOLCHAIN_REQUIRED"):
            self.export()

    def test_existing_in_checkout_and_parent_symlink_destinations_are_refused(self):
        for path, code in [(self.root / "copy", "CANDIDATE_DESTINATION_NOT_ISOLATED"),
                           (self.root, "CANDIDATE_DESTINATION_NOT_ISOLATED")]:
            with self.assertRaisesRegex(candidate.ReleaseError, code):
                candidate.export_candidate(self.root, path, self.sdk)
        self.destination.mkdir()
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_DESTINATION_EXISTS"):
            self.export()
        link = self.base / "link"
        link.symlink_to(self.destination, target_is_directory=True)
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_DESTINATION_SYMLINK"):
            candidate.export_candidate(self.root, link / "copy", self.sdk)

    def test_source_mutation_during_copy_aborts_and_removes_only_its_own_staging_directory(self):
        original = candidate.regular_bytes
        calls = 0
        def changed(root, name):
            nonlocal calls
            calls += 1
            if calls == len(candidate.REQUIRED) + 1:
                self.write("lib/main.dart", "changed during export")
            return original(root, name)
        with patch.object(candidate, "regular_bytes", side_effect=changed):
            with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_SOURCE_CHANGED"):
                self.export()
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.base.glob(".collect-export-*")), [])

    def test_manifest_binds_all_six_locks_and_installed_runtime_without_copying_toolchains(self):
        self.export()
        manifest = self.manifest()
        self.assertEqual(set(manifest["toolchain"]["lock_sha256"]), set(candidate.LOCKS))
        self.assertEqual(manifest["toolchain"]["flutter"]["installed_version"], "3.44.4")
        self.assertFalse((self.destination / "flutter").exists())

    def test_cli_unknown_arguments_are_sanitized_without_starting_tools(self):
        result = subprocess.run([sys.executable, str(SOURCE), "mcp-offline", "--access-token", "SECRET_ARGUMENT"],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("SECRET_ARGUMENT", result.stdout + result.stderr)
        self.assertIn("RELEASE_ARGUMENTS_INVALID", result.stderr)


    def retain(self):
        return candidate.export_candidate(self.root, self.destination, self.sdk, retain_source_drift=True)

    def mutate_after_capture(self, mutation):
        original = candidate.source_snapshot
        def wrapped(root, copy_into=None):
            result = original(root, copy_into=copy_into)
            if copy_into is not None:
                mutation()
            return result
        return patch.object(candidate, "source_snapshot", side_effect=wrapped)

    def test_opt_in_records_initial_bytes_additions_removals_and_hashes_without_source_acceptance(self):
        original = self.write("lib/changed.dart", "initial bytes")
        removed = self.write("lib/removed.dart", "retain removed bytes")
        def mutation():
            original.write_text("later bytes");removed.unlink();self.write("lib/added.dart", "later addition")
        with self.mutate_after_capture(mutation):
            result = self.retain()
        self.assertEqual(result["status"], "pass")
        self.assertEqual((self.destination / "lib/changed.dart").read_text(), "initial bytes")
        self.assertEqual((self.destination / "lib/removed.dart").read_text(), "retain removed bytes")
        self.assertFalse((self.destination / "lib/added.dart").exists())
        drift = {item["path"]: item for item in result["observed_source_drift"]["selected_files"]}
        self.assertEqual(drift["lib/changed.dart"]["prior"]["sha256"], candidate.sha(b"initial bytes"))
        self.assertEqual(drift["lib/changed.dart"]["current"]["sha256"], candidate.sha(b"later bytes"))
        self.assertIsNone(drift["lib/removed.dart"]["current"])
        self.assertIsNone(drift["lib/added.dart"]["prior"])
        self.assertFalse(result["source_current_tree_accepted"])
        self.assertTrue(all(value is False for value in result["approvals"].values()))
        self.assertEqual(result["capture_classification"], "unapproved_non_atomic_implementation_checkpoint")
        self.assertEqual(candidate.verify_candidate(self.destination, expected_manifest_sha256=result["manifest_sha256"])["status"], "pass")
        self.assertEqual(candidate.verify_candidate(self.destination, self.root)["status"], "blocked")
        self.assertIn("started_at_utc", result["capture_interval"])

    def test_opt_in_copies_same_bytes_it_hashed_even_when_source_changes_immediately_after_read(self):
        path = self.write("lib/changing.dart", "captured exact")
        original = candidate.regular_bytes;changed = False
        def wrapped(root, name):
            nonlocal changed
            data = original(root, name)
            if root == self.root and name == "lib/changing.dart" and not changed:
                changed = True;path.write_text("source changed after read")
            return data
        with patch.object(candidate, "regular_bytes", side_effect=wrapped):
            result = self.retain()
        self.assertEqual((self.destination / "lib/changing.dart").read_text(), "captured exact")
        self.assertEqual(result["observed_source_drift"]["selected_files"][0]["path"], "lib/changing.dart")

    def test_opt_in_refuses_changed_required_locks_after_capture(self):
        with self.mutate_after_capture(lambda: self.write("pubspec.lock", "changed lock")):
            with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_PIN_INPUT_CHANGED"):
                self.retain()
        self.assertFalse(self.destination.exists())

    def test_opt_in_refuses_pin_change_before_copy_even_when_later_source_is_stable(self):
        original = candidate.source_snapshot
        def wrapped(root, copy_into=None):
            if copy_into is not None:
                self.write("android/gradle/wrapper/gradle-wrapper.jar", "changed wrapper")
            return original(root, copy_into=copy_into)
        with patch.object(candidate, "source_snapshot", side_effect=wrapped):
            with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_PIN_INPUT_CHANGED"):
                self.retain()
        self.assertFalse(self.destination.exists())

    def test_opt_in_refuses_changed_sdk_toolchain_after_capture(self):
        with self.mutate_after_capture(lambda: (self.sdk / "bin/flutter").write_text("different launcher")):
            with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_TOOLCHAIN_CHANGED"):
                self.retain()
        self.assertFalse(self.destination.exists())

    def test_opt_in_readback_still_refuses_copy_corruption(self):
        original = candidate.regular_bytes
        def corrupt(root, name):
            if root.name.startswith(".collect-export-") and name == "lib/main.dart":
                (root / name).write_text("corrupted copy")
            return original(root, name)
        with patch.object(candidate, "regular_bytes", side_effect=corrupt):
            with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_COPY_INVALID"):
                self.retain()
        self.assertFalse(self.destination.exists())

    def test_opt_in_cannot_bypass_credential_or_symlink_checks(self):
        private = self.write("lib/private.dart", "ghp_" + "a" * 40)
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_CREDENTIAL_PATTERN"):
            self.retain()
        private.unlink()
        (self.root / "lib/alias.dart").symlink_to(self.root / "lib/main.dart")
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_SYMLINK_REFUSED"):
            self.retain()
        self.assertFalse(self.destination.exists())

    def test_opt_in_manifest_cannot_promote_current_tree_or_mismatch_lock_binding(self):
        result = self.retain();manifest = self.manifest()
        manifest["source_current_tree_accepted"] = True
        (self.destination / candidate.MANIFEST).write_bytes(candidate.canonical(manifest))
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_MANIFEST_INVALID"):
            candidate.verify_candidate(self.destination)
        manifest["source_current_tree_accepted"] = False
        manifest["toolchain"]["lock_sha256"]["pubspec.lock"] = "a" * 64
        (self.destination / candidate.MANIFEST).write_bytes(candidate.canonical(manifest))
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_MANIFEST_INVALID"):
            candidate.verify_candidate(self.destination)

    def test_explicit_cli_opt_in_is_non_atomic_even_without_observed_drift(self):
        result = subprocess.run([sys.executable, str(SOURCE), "--root", str(self.root), "export", "--destination", str(self.destination), "--flutter-sdk", str(self.sdk), "--retain-source-drift"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output["capture_classification"], "unapproved_non_atomic_implementation_checkpoint")
        self.assertFalse(output["source_current_tree_accepted"])


class McpOfflineTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / "repo"
        self.bridge = self.root / "tools/collect-notification-mcp"
        self.bridge.mkdir(parents=True)
        self.node = Path(shutil.which("node")).resolve()
        package = {"dependencies": {"@modelcontextprotocol/server": "2.0.0", "zod": "4.5.4"}}
        (self.bridge / "package.json").write_text(json.dumps(package))
        for name, version in package["dependencies"].items():
            path = self.bridge / "node_modules" / name / "package.json"
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps({"version": version}))
        (self.bridge / "src").mkdir()
        self.record = self.base / "methods.jsonl"
        self.write_server()
        self.config = self.base / "config.toml"
        self.write_config()

    def write_config(self, tools=None, args=None, cwd=None):
        self.config.write_text('[mcp_servers.collect-notifications]\ncommand = ' + json.dumps(str(self.node)) +
            '\nargs = ' + json.dumps(args if args is not None else ["--experimental-strip-types", str(self.bridge / "src/server.ts")]) +
            '\ncwd = ' + json.dumps(str(cwd or self.bridge)) + '\nenabled_tools = ' + json.dumps(tools if tools is not None else sorted(candidate.READ_TOOLS)) +
            '\nstartup_timeout_sec = 15\ntool_timeout_sec = 45\n[mcp_servers.collect-notifications.env]\nCOLLECT_OPERATOR_ACCESS_TOKEN = "SECRET_PROFILE_VALUE"\n')

    def write_server(self, behavior="normal"):
        source = '''import {createInterface} from "node:readline";
import {appendFileSync} from "node:fs";
const methods = RECORD;
const behavior = BEHAVIOR;
const names = NAMES;
createInterface({input:process.stdin}).on("line",line=>{
 const message=JSON.parse(line);
 appendFileSync(methods,JSON.stringify({method:message.method,credentials_seen:Boolean(process.env.COLLECT_OPERATOR_ACCESS_TOKEN)})+"\\n");
 if(!Object.hasOwn(message,"id"))return;
 if(behavior==="hang")return;
 if(behavior==="malformed"){process.stdout.write("SECRET_NON_PROTOCOL\\n");return;}
 if(behavior==="oversized"){process.stdout.write("x".repeat(300000));return;}
 const result=message.method==="initialize"?{protocolVersion:"2025-11-25",serverInfo:{name:"collect-notification-operator"},capabilities:{tools:{}}}:
 {tools:names.map(name=>({name,annotations:{readOnlyHint:true},inputSchema:{type:"object",properties:{},additionalProperties:false}}))};
 process.stdout.write(JSON.stringify({jsonrpc:"2.0",id:message.id,result})+"\\n");
});'''
        (self.bridge / "src/server.ts").write_text(source.replace("RECORD", json.dumps(str(self.record))).replace("BEHAVIOR", json.dumps(behavior)).replace("NAMES", json.dumps(sorted(candidate.READ_TOOLS))))

    def profile(self):
        return candidate.safe_host_profile(self.config, self.root)

    def test_host_profile_outputs_only_safe_metadata_and_enforces_exact_five_reads(self):
        profile = self.profile()
        self.assertEqual(set(profile["enabled_tools"]), candidate.READ_TOOLS)
        self.assertNotIn("SECRET_PROFILE_VALUE", json.dumps(profile))
        self.assertNotIn("env", profile)

    def test_missing_duplicate_or_extra_write_tools_block_before_startup(self):
        for tools in [sorted(candidate.READ_TOOLS)[:-1], sorted(candidate.READ_TOOLS) + ["begin_supervisor_run"],
                      sorted(candidate.READ_TOOLS)[:-1] + [sorted(candidate.READ_TOOLS)[0]]]:
            self.write_config(tools=tools)
            with self.assertRaisesRegex(candidate.ReleaseError, "MCP_FIVE_READ_ALLOWLIST_REQUIRED"):
                self.profile()
        self.assertFalse(self.record.exists())

    def test_missing_dependency_and_version_drift_block_before_protocol(self):
        path = self.bridge / "node_modules/zod/package.json"
        path.write_text(json.dumps({"version": "0.0.0"}))
        with self.assertRaisesRegex(candidate.ReleaseError, "MCP_INSTALLED_DEPENDENCY_MISMATCH"):
            self.profile()
        path.unlink()
        with self.assertRaisesRegex(candidate.ReleaseError, "MCP_LOCAL_PREREQUISITE_MISSING"):
            self.profile()

    def test_command_argument_or_checkout_overrides_are_refused(self):
        for args, cwd in [(["--eval", "SECRET"], None), (None, self.base)]:
            self.write_config(args=args, cwd=cwd)
            with self.assertRaisesRegex(candidate.ReleaseError, "MCP_FIXED_BRIDGE_REQUIRED"):
                self.profile()
        self.assertFalse(self.record.exists())

    def test_actual_stdio_discovers_tools_without_forwarding_credentials_or_invoking_a_tool(self):
        with patch.dict(os.environ, {"COLLECT_OPERATOR_ACCESS_TOKEN": "SECRET_PARENT_VALUE"}):
            report = candidate.discover_mcp(self.profile())
        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["mcp_tool_calls"], 0)
        self.assertEqual(report["backend_reads"], 0)
        self.assertEqual(set(report["enabled_read_schemas"]), candidate.READ_TOOLS)
        records = [json.loads(line) for line in self.record.read_text().splitlines()]
        self.assertEqual([row["method"] for row in records], ["initialize", "notifications/initialized", "tools/list"])
        self.assertTrue(all(row["credentials_seen"] is False for row in records))
        self.assertNotIn("SECRET", json.dumps(report))

    def test_malformed_oversized_and_stalled_stdio_fail_safely(self):
        for behavior, code in [("malformed", "MCP_PROTOCOL_INVALID"), ("oversized", "MCP_RESPONSE_TOO_LARGE"), ("hang", "MCP_DISCOVERY_DEADLINE")]:
            self.write_server(behavior)
            with self.assertRaisesRegex(candidate.ReleaseError, code):
                candidate.discover_mcp(self.profile(), timeout_seconds=0.7 if behavior == "hang" else 5.0)

    def test_malformed_config_never_echoes_config_values(self):
        self.config.write_text('SECRET_CONFIGURATION_VALUE = [')
        with self.assertRaises(candidate.ReleaseError) as blocked:
            self.profile()
        self.assertEqual(str(blocked.exception), "MCP_LOCAL_PREREQUISITE_MISSING")

    def test_candidate_metadata_binding_accepts_exact_source_and_refuses_drift_before_another_start(self):
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        for name in candidate.REQUIRED:
            path = self.root / name
            if not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("synthetic input")
        (self.root / ".fvmrc").write_text(json.dumps({"flutter": "3.44.4"}))
        sdk = self.base / "flutter"
        (sdk / "bin/cache").mkdir(parents=True)
        (sdk / "bin/flutter").write_text("synthetic launcher")
        (sdk / "bin/cache/flutter.version.json").write_text(json.dumps({"frameworkVersion": "3.44.4", "frameworkRevision": "synthetic", "dartSdkVersion": "3.12.2"}))
        export = self.base / "candidate"
        receipt = candidate.export_candidate(self.root, export, sdk)
        report = candidate.offline_mcp(self.root, self.config, export, receipt["manifest_sha256"])
        self.assertEqual(report["candidate_source_bound"], True)
        self.assertEqual(report["candidate_manifest_sha256"], receipt["manifest_sha256"])
        prior = self.record.read_bytes()
        (self.root / "lib/main.dart").write_text("changed after export")
        with self.assertRaisesRegex(candidate.ReleaseError, "MCP_CANDIDATE_SOURCE_STALE"):
            candidate.offline_mcp(self.root, self.config, export, receipt["manifest_sha256"])
        self.assertEqual(self.record.read_bytes(), prior)


if __name__ == "__main__":
    unittest.main()
