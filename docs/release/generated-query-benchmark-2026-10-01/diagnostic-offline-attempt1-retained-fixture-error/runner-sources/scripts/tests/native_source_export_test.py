#!/usr/bin/env python3
"""Check source-only export boundaries using a real temporary Git checkout."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("native_export", Path(__file__).resolve().parents[1] / "qa/native_source_export.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NativeSourceExportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        for name in ["pubspec.yaml", "pubspec.lock", "lib/main.dart", "android/app/build.gradle.kts", "ios/Runner.xcodeproj/project.pbxproj"]:
            self.write(name)

    def write(self, name, text="synthetic input"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_ignored_provider_keys_and_caches_excluded_even_if_private_file_indexed(self):
        self.write(".gitignore", "android/generated-cache/\n")
        self.write("android/generated-cache/private.txt")
        key = self.write("android/key.properties")
        subprocess.run(["git", "add", str(key)], cwd=self.root, check=True)
        for name in ["android/app/google-services.json", "ios/Runner/GoogleService-Info.plist", "android/upload.jks",
                     "ios/Runner/AuthKey.p8", "third_party/gotrue/test/private.pem", "android/private.key"]:
            self.write(name)
        result = module.export(self.root, Path(self.temp.name) / "output")
        self.assertEqual(len(result["source_sha256"]), 5)
        self.assertFalse(result["private_provider_signing_inputs_copied"])

    def test_local_auth_fork_runtime_license_and_original_provenance_are_exported_exactly(self):
        names = ["third_party/gotrue/lib/gotrue.dart", "third_party/gotrue/LICENSE",
                 "third_party/gotrue/pubspec.yaml", "third_party/gotrue/COLLECT_FORK.md", "third_party/gotrue/UPSTREAM-SHA256.json"]
        for name in names:
            self.write(name, "Synthetic public fork input: " + name)
        output = Path(self.temp.name) / "output"
        result = module.export(self.root, output)
        for name in names:
            self.assertEqual((output / name).read_bytes(), (self.root / name).read_bytes())
            self.assertEqual(result["source_sha256"][name], module.digest(self.root / name))

    def test_checkout_output_existing_output_and_external_symlink_rejected(self):
        with self.assertRaises(ValueError):
            module.export(self.root, self.root / "export")
        destination = Path(self.temp.name) / "existing"
        destination.mkdir()
        with self.assertRaises(ValueError):
            module.export(self.root, destination)
        outside = Path(self.temp.name) / "outside.dart"
        outside.write_text("outside")
        (self.root / "lib/escape.dart").symlink_to(outside)
        with self.assertRaises(ValueError):
            module.export(self.root, Path(self.temp.name) / "output")

    def test_authority_and_actual_production_build_callers_are_hash_bound(self):
        names = ["AGENTS.md", "scripts/qa/native_build_provenance.rb",
                 "scripts/android_play_store_build.sh", "scripts/android_release_signing_preflight.sh",
                 "scripts/ios_app_store_build.sh", "scripts/qa/native_source_export.py",
                 "scripts/supply_chain/gradle_runtime_inventory.init.gradle"]
        for name in names:
            self.write(name, "Synthetic public build caller: " + name)
        first = module.export(self.root, Path(self.temp.name) / "output-before")
        for name in names:
            self.assertEqual(first["source_sha256"][name], module.digest(self.root / name))
        self.write("scripts/qa/native_build_provenance.rb", "Changed public build caller")
        second = module.export(self.root, Path(self.temp.name) / "output-after")
        self.assertNotEqual(first["source_sha256"]["scripts/qa/native_build_provenance.rb"],
                            second["source_sha256"]["scripts/qa/native_build_provenance.rb"])

    def test_internal_source_symlink_refuses_ambiguous_source_identity(self):
        target = self.write("lib/real.dart", "Synthetic regular runtime source")
        (self.root / "lib/alias.dart").symlink_to(target)
        with self.assertRaisesRegex(ValueError, "must be a regular file"):
            module.export(self.root, Path(self.temp.name) / "output")


if __name__ == "__main__":
    unittest.main()
