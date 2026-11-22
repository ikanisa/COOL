import importlib.util
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
                               "--surface", "member", "--defines", str(self.defines),
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

    def test_retired_admin_surface_is_refused(self):
        result = self.invoke("bind", "--surface", "admin")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
