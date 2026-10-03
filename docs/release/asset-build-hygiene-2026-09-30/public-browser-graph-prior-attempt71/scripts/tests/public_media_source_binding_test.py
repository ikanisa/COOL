#!/usr/bin/env python3
"""Actual file mutation checks for isolated Public capture source bindings."""
import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "publication", Path(__file__).resolve().parents[1] / "assets/publish_public_app_media.py")
PUBLICATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUBLICATION)


class BrowserSourceBindingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / "repo"
        self.export = Path(self.temp.name).resolve() / "export"
        self.root.mkdir()
        self.export.mkdir()
        original_root = PUBLICATION.ROOT
        PUBLICATION.ROOT = self.root
        self.addCleanup(setattr, PUBLICATION, "ROOT", original_root)
        for relative in ["lib/main.dart", "scripts/qa/public_browser_app_media.mjs",
                         "scripts/public_app_media.rb", "scripts/qa/asset_manifest_integrity.rb"]:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("Synthetic declared source: " + relative)
        for relative in ["lib/main.dart", "scripts/public_app_media.rb",
                         "scripts/qa/asset_manifest_integrity.rb"]:
            path = self.export / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("Synthetic declared source: " + relative)
        roots = {"collect_app": self.export, **{name: self.export / "third_party" / name for name in
                 ["file_saver", "gotrue", "firebase_messaging"]}}
        for path in roots.values():
            path.mkdir(parents=True, exist_ok=True)
        (self.export / ".dart_tool").mkdir()
        (self.export / ".dart_tool/package_config.json").write_text(json.dumps({
            "packages": [{"name": name, "rootUri": str(path.as_uri())} for name, path in roots.items()]}))
        (self.export / ".flutter-plugins-dependencies").write_text(json.dumps({"plugins": {"ios": [
            {"name": name, "path": str(roots[name])} for name in ["file_saver", "firebase_messaging"]]}}))
        self.runtime = "a" * 64
        bindings = {relative: PUBLICATION.sha(self.export / relative) for relative in
                    [".dart_tool/package_config.json", ".flutter-plugins-dependencies"]}
        self.report = {
            "isolated_source_export": True, "source_root": str(self.export),
            "checkout_runtime_before_sha256": self.runtime,
            "checkout_runtime_after_sha256": self.runtime,
            "capture_recorder_sha256": PUBLICATION.sha(
                self.root / "scripts/qa/public_browser_app_media.mjs"),
            "generated_bindings_unchanged": True,
            "generated_bindings_before": bindings,
            "generated_bindings_after": copy.deepcopy(bindings),
            "resolved_local_bindings_before": {name: str(path) for name, path in roots.items()},
            "resolved_local_bindings_after": {name: str(path) for name, path in roots.items()},
            "sources_after": {relative: PUBLICATION.sha(self.export / relative) for relative in
                              ["lib/main.dart", "scripts/public_app_media.rb", "scripts/qa/asset_manifest_integrity.rb"]},
        }

    def verify(self):
        PUBLICATION.validate_browser_source_binding(self.report, self.runtime)

    def test_actual_unchanged_export_and_bindings_pass(self):
        self.verify()

    def test_actual_export_runtime_mutation_is_rejected(self):
        (self.export / "lib/main.dart").write_text("Mutated runtime after capture")
        with self.assertRaisesRegex(ValueError, "captured source differs"):
            self.verify()

    def test_actual_generated_binding_mutation_is_rejected(self):
        (self.export / ".dart_tool/package_config.json").write_text("New binding")
        with self.assertRaisesRegex(ValueError, "binding differs"):
            self.verify()

    def test_checkout_drift_and_fabricated_binding_inventory_are_rejected(self):
        self.report["checkout_runtime_after_sha256"] = "b" * 64
        with self.assertRaisesRegex(ValueError, "checkout does not match"):
            self.verify()
        self.report["checkout_runtime_after_sha256"] = self.runtime
        self.report["generated_bindings_after"] = {}
        with self.assertRaisesRegex(ValueError, "bindings changed or are incomplete"):
            self.verify()

    def test_actual_recorder_mutation_is_rejected(self):
        (self.root / "scripts/qa/public_browser_app_media.mjs").write_text("Changed recorder")
        with self.assertRaisesRegex(ValueError, "recorder changed"):
            self.verify()

    def test_stable_manifests_with_external_local_package_or_plugin_target_are_rejected(self):
        for relative, message in [(".dart_tool/package_config.json", "package points outside"),
                                  (".flutter-plugins-dependencies", "plugin points outside")]:
            path = self.export / relative
            original = path.read_text()
            data = json.loads(original)
            if "packages" in data:
                data["packages"][1]["rootUri"] = self.root.as_uri()
            else:
                data["plugins"]["ios"][0]["path"] = str(self.root)
            path.write_text(json.dumps(data))
            self.report["generated_bindings_before"][relative] = PUBLICATION.sha(path)
            self.report["generated_bindings_after"][relative] = PUBLICATION.sha(path)
            with self.assertRaisesRegex(ValueError, message):
                self.verify()
            path.write_text(original)
            self.report["generated_bindings_before"][relative] = PUBLICATION.sha(path)
            self.report["generated_bindings_after"][relative] = PUBLICATION.sha(path)

    def test_actual_required_ruby_helper_dependency_mutation_is_rejected(self):
        (self.root / "scripts/qa/asset_manifest_integrity.rb").write_text("Changed helper dependency")
        with self.assertRaisesRegex(ValueError, "helper closure"):
            self.verify()

    def test_in_checkout_export_and_source_symlink_are_rejected(self):
        self.report["source_root"] = str(self.root / "export")
        with self.assertRaisesRegex(ValueError, "outside the checkout"):
            self.verify()
        self.report["source_root"] = str(self.export)
        target = self.export / "lib/main.dart"
        target.unlink()
        target.symlink_to(self.root / "lib/main.dart")
        with self.assertRaisesRegex(ValueError, "captured source differs"):
            self.verify()


if __name__ == "__main__":
    unittest.main()
