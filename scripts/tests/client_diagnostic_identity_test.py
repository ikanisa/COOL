import importlib.util
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / "qa/client_diagnostic_identity.py"
spec = importlib.util.spec_from_file_location("diagnostic_identity", HELPER)
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)


class DiagnosticSourceIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="collect-diagnostic-identity-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        (self.root / "lib").mkdir()
        (self.root / "lib/main.dart").write_text("void main() {}\n")
        (self.root / "pubspec.yaml").write_text("name: fixture\nversion: 1.2.4+23\n")
        (self.root / "pubspec.lock").write_text("packages: {}\n")
        self.profile = {"APP_ENVIRONMENT": "production", "COLLECT_BACKEND": "supabase"}
        self.defines = self.root / "defines.json"
        self.defines.write_text(json.dumps(self.profile))
        self.manifest = self.root / "manifest.json"
        self.metadata = self.root / "metadata.json"
        self.metadata.write_text('{"backend":"supabase"}')

    def invoke(self, action, *extra):
        return subprocess.run([sys.executable, str(HELPER), action, "--root", str(self.root),
                               "--surface", "admin", "--defines", str(self.defines),
                               "--manifest", str(self.manifest), "--metadata", str(self.metadata), *extra],
                              capture_output=True, text=True)

    def test_roundtrip_binds_profile_version_metadata_and_actual_bytes(self):
        self.assertEqual(self.invoke("bind").returncode, 0)
        self.assertEqual(self.invoke("verify").returncode, 0)
        manifest = json.loads(self.manifest.read_text())
        profile = json.loads(self.defines.read_text())
        self.assertEqual(profile["COLLECT_BUILD_VERSION"], "1.2.4+23")
        self.assertEqual(profile["COLLECT_BUILD_SOURCE_ID"], manifest["source_revision"])
        self.assertFalse(manifest["signing_or_deployment_acceptance"])
        self.assertNotIn("public_profile", manifest)
        self.assertEqual(json.loads(self.metadata.read_text())["diagnostics_source_revision"], manifest["source_revision"])

    def test_changed_new_and_vendored_source_change_identity(self):
        before = identity.identity(self.root, "member", self.profile)[0]["source_revision"]
        (self.root / "lib/added.dart").write_text("const additional = true;\n")
        self.assertNotEqual(before, identity.identity(self.root, "member", self.profile)[0]["source_revision"])
        (self.root / "third_party/plugin").mkdir(parents=True)
        (self.root / "third_party/plugin/plugin.dart").write_text("const plugin = true;\n")
        self.assertEqual(self.invoke("bind").returncode, 0)
        (self.root / "third_party/plugin/plugin.dart").write_text("const plugin = false;\n")
        self.assertNotEqual(self.invoke("verify").returncode, 0)

    def test_changed_profile_and_existing_wrong_label_are_refused(self):
        self.assertEqual(self.invoke("bind").returncode, 0)
        value = json.loads(self.defines.read_text());value["APP_ENVIRONMENT"] = "staging"
        self.defines.write_text(json.dumps(value))
        self.assertNotEqual(self.invoke("verify").returncode, 0)
        self.assertNotEqual(self.invoke("bind").returncode, 0)

    def test_source_version_mismatch_or_unknown_is_not_a_release_label(self):
        for version in ("unknown", "1.2.4+24", "PRIVATE_CALLER_TEXT"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                identity.identity(self.root, "member", self.profile | {"COLLECT_BUILD_VERSION": version})

    def test_source_links_are_refused_without_reading_outside_the_tree(self):
        (self.root / "lib/linked.dart").symlink_to(self.root / "pubspec.yaml")
        with self.assertRaises(ValueError):
            identity.identity(self.root, "member", self.profile)

    def test_invalid_input_is_not_echoed_to_terminal(self):
        self.defines.write_text(json.dumps({"PRIVATE_CALLER_TEXT": {"secret": "PRIVATE_CALLER_TEXT"}}))
        result = self.invoke("bind")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("PRIVATE_CALLER_TEXT", result.stdout + result.stderr)

    def test_compiled_javascript_has_exact_labels_and_reports_only_presence_evidence(self):
        self.assertEqual(self.invoke("bind").returncode, 0)
        manifest = json.loads(self.manifest.read_text())
        path = self.root / "main.dart.js"
        for quote in ('"', "'"):
            data = (f"const source={quote}{manifest['source_revision']}{quote};"
                    f"const version={quote}{manifest['build_version']}{quote};").encode()
            path.write_bytes(data)
            original = {item: item.read_bytes() for item in
                        (path, self.manifest, self.defines, self.metadata)}
            result = self.invoke("verify", "--javascript", str(path))
            self.assertEqual(result.returncode, 0, result.stderr)
            proof = json.loads(result.stdout)
            self.assertEqual(proof["sha256"], hashlib.sha256(data).hexdigest())
            self.assertEqual(proof["bytes"], len(data))
            self.assertEqual(proof["source_revision"], manifest["source_revision"])
            self.assertEqual(proof["build_version"], "1.2.4+23")
            self.assertEqual(proof["verification_scope"], "quoted_label_bytes_present")
            self.assertIs(proof["signing_or_deployment_acceptance"], False)
            self.assertEqual(original, {item: item.read_bytes() for item in original})

    def test_missing_wrong_or_partial_compiled_labels_are_refused(self):
        path = self.root / "main.dart.js"
        source, version = "a" * 64, "1.2.4+23"
        for actual_source, actual_version in (
                (None, version), (source, None), ("b" * 64, version),
                (source, "1.2.4+24"), ("prefix" + source, version),
                (source, version + "suffix")):
            path.write_text("const labels=" + json.dumps([actual_source, actual_version]) + ";")
            with self.subTest(source=actual_source, version=actual_version), self.assertRaises(ValueError):
                identity.javascript_identity(path, source, version)

    def test_compiled_inspection_refuses_empty_oversized_linked_and_invalid_expectations(self):
        path = self.root / "main.dart.js"
        source, version = "a" * 64, "1.2.4+23"
        path.write_bytes(b"")
        with self.assertRaises(ValueError):
            identity.javascript_identity(path, source, version)
        with path.open("wb") as handle:
            handle.truncate(identity.MAX_JAVASCRIPT_BYTES + 1)
        with self.assertRaises(ValueError):
            identity.javascript_identity(path, source, version)
        path.unlink()
        path.symlink_to(self.metadata)
        with self.assertRaises(ValueError):
            identity.javascript_identity(path, source, version)
        path.unlink()
        path.write_text(json.dumps([source, version]))
        directory = self.root / "linked-output"
        directory.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            identity.javascript_identity(directory / "main.dart.js", source, version)
        for expected_source, expected_version in ((None, version), (source, None),
                                                  (source, "unknown"), ("a" * 40, version)):
            with self.subTest(source=expected_source, version=expected_version), self.assertRaises(ValueError):
                identity.javascript_identity(path, expected_source, expected_version)

    def test_compiled_inspection_is_verification_only_and_admin_only(self):
        path = self.root / "main.dart.js"
        path.write_text('const labels="fixture";')
        result = self.invoke("bind", "--javascript", str(path))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.manifest.exists())
        self.assertEqual(self.invoke("bind").returncode, 0)
        result = self.invoke("verify", "--surface", "member", "--javascript", str(path))
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
