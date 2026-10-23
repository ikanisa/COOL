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
                 "deploy/.temp/database-url", "docs/release/raw-customer.json", "output/raw.json", "test/payload.xlsx",
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
        for value in ["-----BEGIN PRIVATE KEY-----\n" + "A" * 32, "ghp_" + "a" * 40,
                      "service_secret_" + "x" * 30, "unfamiliar-service-token-" + "b" * 30,
                      "TOKEN_" + "c" * 30, "service_secret_synthetic_" + "d" * 30]:
            self.write("lib/public.dart", value)
            with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_CREDENTIAL_PATTERN"):
                self.export()
            self.assertFalse(self.destination.exists())

    def test_upstream_auth_fixture_tests_are_excluded_but_runtime_provenance_and_app_tests_remain(self):
        self.write("third_party/synthetic_fork/test/client_test.dart", "service_secret_" + "x" * 30)
        retained = ["third_party/synthetic_fork/lib/synthetic_fork.dart", "third_party/synthetic_fork/pubspec.yaml",
                    "third_party/synthetic_fork/LICENSE", "third_party/synthetic_fork/COLLECT_FORK.md",
                    "third_party/synthetic_fork/UPSTREAM-SHA", "test/collect_auth_test.dart"]
        for name in retained:
            self.write(name)
        self.export()
        self.assertFalse((self.destination / "third_party/synthetic_fork/test/client_test.dart").exists())
        self.assertEqual(self.manifest()["excluded_file_counts"]["upstream_qa_fixture_source"], 1)
        recorded = self.manifest()["excluded_upstream_qa_source"]["third_party/synthetic_fork/test/client_test.dart"]
        self.assertEqual(recorded["sha256"], candidate.sha((self.root / "third_party/synthetic_fork/test/client_test.dart").read_bytes()))
        self.assertEqual(recorded["reason"], "upstream_qa_fixture_source")
        self.assertNotIn("service_secret_", json.dumps(self.manifest()))
        for name in retained:
            self.assertEqual((self.destination / name).read_bytes(), (self.root / name).read_bytes())
        self.write("third_party/synthetic_fork/test/client_test.dart", "updated upstream regression fixture")
        self.assertIn({"path": "third_party/synthetic_fork/test/client_test.dart", "reason": "excluded_source_changed"},
                      candidate.verify_candidate(self.destination, self.root)["changes"])

    def test_a_private_key_detection_rule_is_source_code_without_private_key_material(self):
        self.write("scripts/check.py", 'forbidden_header = "-----BEGIN PRIVATE KEY-----"\n')
        self.assertEqual(self.export()["status"], "pass")

    def test_jwt_and_opaque_refresh_tokens_are_excluded(self):
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
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_CREDENTIAL_PATTERN"):
            self.export()

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
        paths = ["supabase/migrations/20261020134445_first.sql", "supabase/migrations/20261020134445_other.sql"]
        for name in paths:
            self.write(name, "select 1;")
        with self.assertRaises(candidate.ReleaseError) as blocked:
            self.export()
        self.assertEqual(blocked.exception.code, "CANDIDATE_MIGRATION_VERSION_DUPLICATE")
        self.assertEqual(blocked.exception.paths, paths)
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.base.glob(".collect-export-*")), [])

    def test_migration_sequence_and_filename_validity_are_prerequisites(self):
        names = ["supabase/migrations/" + version + "_invalid.sql" for version in
                 ["00000000000000", "12", "10000", "abcd", "20260930", "2026102013444", "202610201344444"]]
        names += ["supabase/migrations/20261020134445_.sql", "supabase/migrations/nested/20261020134445_invalid.sql"]
        for name in names:
            path = self.write(name, "select 1;")
            with self.assertRaises(candidate.ReleaseError) as blocked:
                self.export()
            self.assertEqual(blocked.exception.code, "CANDIDATE_MIGRATION_VERSION_INVALID")
            self.assertEqual(blocked.exception.paths, [name])
            self.assertFalse(self.destination.exists())
            path.unlink()

    def test_deleted_indexed_migration_does_not_collide_with_current_replacement(self):
        old = self.write("supabase/migrations/20261020134445_old.sql", "select 1;")
        subprocess.run(["git", "add", old.relative_to(self.root).as_posix()], cwd=self.root, check=True)
        old.unlink()
        current = "supabase/migrations/20261020134445_new.sql"
        self.write(current, "select 1;")
        self.export()
        self.assertEqual(self.manifest()["migration_versions"], {
            "20261020134444": "supabase/migrations/20261020134444_collect_curated_platform_baseline.sql",
            "20261020134445": current,
        })
        self.assertIn(old.relative_to(self.root).as_posix(), self.manifest()["absent_indexed_source_paths"])

    def test_legacy_duplicate_and_invalid_names_are_retained_without_gating_supabase(self):
        legacy = ["deploy/platform-api/migrations/0001_first.sql", "deploy/platform-api/migrations/0001_other.sql",
                  "deploy/platform-api/migrations/not-a-sequence.sql"]
        for name in legacy:
            self.write(name, "select 1;")
        result = self.export()
        self.assertEqual(result["status"], "pass")
        manifest = self.manifest()
        self.assertEqual(manifest["migration_versions"], {
            "20261020134444": "supabase/migrations/20261020134444_collect_curated_platform_baseline.sql",
        })
        for name in legacy:
            self.assertIn(name, manifest["source_files"])
            self.assertEqual((self.destination / name).read_bytes(), (self.root / name).read_bytes())
        self.assertEqual(candidate.verify_candidate(self.destination, self.root, result["manifest_sha256"])["status"], "pass")


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

    def test_manifest_binds_all_required_locks_and_installed_runtime_without_copying_toolchains(self):
        self.export()
        manifest = self.manifest()
        self.assertEqual(set(manifest["toolchain"]["lock_sha256"]), set(candidate.LOCKS))
        self.assertEqual(manifest["toolchain"]["flutter"]["installed_version"], "3.44.4")
        self.assertFalse((self.destination / "flutter").exists())

    def test_cli_unknown_arguments_are_sanitized_without_starting_tools(self):
        result = subprocess.run([sys.executable, str(SOURCE), "export", "--access-token", "SECRET_ARGUMENT"],
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


class CredentialScreenTest(unittest.TestCase):
    def blocked(self, data, name="lib/public.dart"):
        with self.assertRaisesRegex(candidate.ReleaseError, "CANDIDATE_CREDENTIAL_PATTERN"):
            candidate.screen_credentials(data, name)

    def lint_line(self):
        return b"    use_" + b"key_" + b"in_widget_constructors: true"

    def test_reviewed_lint_is_limited_to_its_exact_line_and_path(self):
        data = self.lint_line()
        candidate.screen_credentials(data + b"\n", "analysis_options.yaml")
        candidate.screen_credentials(b"# harmless line before\n" + data + b"\n", "analysis_options.yaml")
        self.blocked(data, "lib/public.dart")
        self.blocked(data + b" # changed context", "analysis_options.yaml")
        self.blocked(data.replace(b"true", b"false"), "analysis_options.yaml")
        self.blocked(data.replace(b"    ", b"  ", 1), "analysis_options.yaml")
        self.blocked(data.replace(b"constructors", b"constructorz"), "analysis_options.yaml")

    def test_reviewed_paths_do_not_exempt_adjacent_or_same_line_candidates(self):
        suspicious = b"service_" + b"secret_" + b"x" * 30
        self.blocked(self.lint_line() + b"\n" + suspicious, "analysis_options.yaml")
        self.blocked(self.lint_line() + b" # " + suspicious, "analysis_options.yaml")
        for name in ["deploy/platform-api/test/support/auth_fixture.mjs", "scripts/tests/atomic_d1_restore_test.mjs", "test/features/privacy/privacy_request_screen_test.dart"]:
            self.blocked(suspicious, name)

    def test_reviewed_play_service_account_helpers_keep_exact_public_context_only(self):
        name = "scripts/google_play_production_upload.sh"
        lines = [b"def token_from_" + b"service_account(path, data = nil)",
                 b"  token, source = token_from_" + b'service_account(nil, ENV["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"])']
        suspicious = b"service_" + b"secret_" + b"x" * 30
        for line in lines:
            with self.subTest(line_sha256=candidate.sha(line)):
                candidate.screen_credentials(line + b"\n", name)
                self.blocked(line, "scripts/other_publisher.sh")
                self.blocked(line + b" # changed context", name)
                self.blocked(line + b"\n" + suspicious, name)
                self.blocked(line + b" # " + suspicious, name)
                self.blocked(line + b"\n" + b"ghp_" + b"z" * 40, name)

    def test_generic_values_keep_no_directory_comment_or_label_bypass(self):
        values = [b"service_" + b"secret_" + b"x" * 30,
                  b"unfamiliar-service-" + b"token-" + b"b" * 30,
                  b"TOKEN_" + b"c" * 30,
                  b"service_" + b"secret_synthetic_" + b"d" * 30]
        for value in values:
            for name in ["lib/public.dart", "test/fixture.dart", "scripts/tests/test_collect_release_candidate.py"]:
                for content in [value, b"// synthetic example " + value, b'const fixture = "' + value + b'";']:
                    self.blocked(content, name)

    def test_every_finitely_reviewed_path_still_refuses_unreviewed_credentials(self):
        suspicious = b"service_" + b"secret_" + b"x" * 30
        names = set(candidate.GENERIC_PUBLIC_SOURCE_LINES) | set(candidate.GENERIC_CONTROLLED_TEST_LINES)
        for name in names:
            with self.subTest(path=name):
                self.blocked(suspicious, name)
                self.blocked(b"// synthetic fixture " + suspicious, name)
                self.blocked(b'const fixture = "' + suspicious + b'";', name)

    def test_current_operator_and_fixture_contexts_keep_exact_paths_and_bytes(self):
        # Optional root is for this private staged test only. The production
        # scanner has no environment override or fixture-directory exemption.
        root = Path(os.environ.get("COLLECT_TEST_CONTEXT_SOURCE_ROOT", SOURCE.parents[2]))
        names = ['scripts/supabase/current-archive/bundle.mjs', 'scripts/supabase/current-archive/operator.mjs', 'scripts/supabase/current-archive/custody.test.mjs', 'scripts/supabase/current-archive/operator.test.mjs', 'scripts/supabase/current-archive/root-curated.fixture.mjs', 'scripts/supabase/current-archive/transport.test.mjs', 'scripts/supabase/jobs_test.mjs', 'scripts/tests/cloudflare_native_build_config_test.py', 'supabase/functions/_shared/tests/momo-provider-adapter.test.ts']
        suspicious = b"service_" + b"secret_" + b"x" * 30
        for name in names:
            data = (root / name).read_bytes()
            candidate.screen_credentials(data, name)
            observed = set()
            for match in candidate.re.finditer(candidate.TOKEN_PATTERNS[6], data):
                self.assertTrue(candidate.reviewed_generic_line(data, name, match))
                start = data.rfind(b"\n", 0, match.start()) + 1
                end = data.find(b"\n", match.end())
                line = data[start:len(data) if end == -1 else end]
                line_sha256 = candidate.sha(line)
                if line_sha256 in observed:
                    continue
                observed.add(line_sha256)
                with self.subTest(path=name, line_sha256=line_sha256):
                    self.blocked(line, "scripts/unreviewed_context.mjs")
                    self.blocked(line + b" // changed context", name)
                    self.blocked(line + b"\n" + suspicious, name)
                    self.blocked(line + b" // " + suspicious, name)
                    self.blocked(line + b"\n" + b"ghp_" + b"z" * 40, name)
            self.assertTrue(observed, name)

    def test_even_an_exact_context_entry_cannot_allow_specific_or_json_credentials(self):
        name = "supabase/functions/_shared/tests/runtime.test.ts"
        header = base64.urlsafe_b64encode(b'{"alg":"HS256"}').rstrip(b"=")
        body = base64.urlsafe_b64encode(b'{"role":"service_role","exp":1234567890}').rstrip(b"=")
        values = [b"-----BEGIN PRIVATE KEY-----\n" + b"A" * 32,
                  b"ghp_" + b"b" * 40, b"github_pat_" + b"c" * 50,
                  b"AKIA" + b"D" * 16, b"sk_live_" + b"e" * 30,
                  b"sk-proj-" + b"f" * 40, header + b"." + body + b"." + b"z" * 32,
                  json.dumps({"nested": [{"secret_key": "opaque_private_value"}]}).encode()]
        for value in values:
            with self.subTest(case_sha256=candidate.sha(value)):
                target = "supabase/jobs/readiness.example.json" if value.startswith(b"{") else name
                with patch.dict(candidate.GENERIC_CONTROLLED_TEST_LINES,
                                {target: frozenset((candidate.sha(value),))}):
                    self.blocked(value, target)

    def test_specific_patterns_never_use_context_relief(self):
        values = [b"-----BEGIN PRIVATE KEY-----\n" + b"A" * 32,
                  b"-----BEGIN RSA PRIVATE KEY-----\n" + b"A" * 32,
                  b"-----BEGIN EC PRIVATE KEY-----\n" + b"A" * 32,
                  b"-----BEGIN OPENSSH PRIVATE KEY-----\n" + b"A" * 32,
                  b"ghp_" + b"a" * 40, b"github_pat_" + b"b" * 50,
                  b"AKIA" + b"C" * 16, b"sk_live_" + b"d" * 30,
                  b"sk_test_" + b"e" * 30, b"sk-proj-" + b"f" * 40]
        for value in values:
            for name in ["analysis_options.yaml", "deploy/platform-api/test/support/auth_fixture.mjs"]:
                self.blocked(self.lint_line() + b"\n" + value, name)

    def test_json_scan_remains_strict_even_under_reviewed_paths(self):
        fields = ["access_token", "refresh_token", "client_secret", "private_key", "secret_key", "service_role_key"]
        for field in fields:
            data = json.dumps({"nested": [{field: "opaque_private_value"}]}).encode()
            self.blocked(data, "contracts/public.json")
        self.blocked(json.dumps({"refresh_token": "opaque_private_value"}).encode(), "analysis_options.yaml.json")

    def test_bearer_claims_remain_denied_in_public_and_fixture_contexts(self):
        header = base64.urlsafe_b64encode(b'{"alg":"HS256"}').rstrip(b"=")
        for role in ["authenticated", "anon", "service_role"]:
            body = base64.urlsafe_b64encode(json.dumps({"role": role, "exp": 1234567890}).encode()).rstrip(b"=")
            value = header + b"." + body + b"." + b"z" * 32
            self.blocked(value, "lib/public.dart")
            self.blocked(value, "deploy/platform-api/test/support/auth_fixture.mjs")


if __name__ == "__main__":
    unittest.main()
