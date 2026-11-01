#!/usr/bin/env python3
"""Actual file mutation checks for isolated Public capture source bindings."""
import copy
import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
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
                         "scripts/qa/collect_diagnostic_observer.mjs",
                         "scripts/public_app_media.rb", "scripts/qa/asset_manifest_integrity.rb"]:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("Synthetic declared source: " + relative)
        for relative in ["lib/main.dart", "scripts/public_app_media.rb",
                         "scripts/qa/public_browser_app_media.mjs", "scripts/qa/collect_diagnostic_observer.mjs",
                         "scripts/qa/asset_manifest_integrity.rb"]:
            path = self.export / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("Synthetic declared source: " + relative)
        roots = {"collect_app": self.export, **{name: self.export / "third_party" / name for name in
                 ["file_saver", "synthetic_fork", "firebase_messaging"]}}
        (self.root / "pubspec.yaml").write_text(json.dumps({"name": "collect_app",
            "dependency_overrides": {name: {"path": "third_party/" + name}
                for name in roots if name != "collect_app"}}))
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
        observers = {relative: PUBLICATION.sha(self.root / relative)
                     for relative in PUBLICATION.BROWSER_DIAGNOSTIC_INPUTS}
        self.report.update(diagnostic_observer_sources_before=observers,
                           diagnostic_observer_sources_after=copy.deepcopy(observers))

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

    def test_observer_omission_extra_hash_and_actual_helper_mutation_are_rejected(self):
        original = copy.deepcopy(self.report['diagnostic_observer_sources_before'])
        for invalid in [None, {}, {**original, 'scripts/foreign.mjs': 'a' * 64}]:
            self.report['diagnostic_observer_sources_before'] = invalid
            self.report['diagnostic_observer_sources_after'] = invalid
            with self.assertRaisesRegex(ValueError, 'diagnostic observer binding'):
                self.verify()
        self.report['diagnostic_observer_sources_before'] = original
        self.report['diagnostic_observer_sources_after'] = copy.deepcopy(original)
        (self.root / 'scripts/qa/collect_diagnostic_observer.mjs').write_text('Changed observer')
        with self.assertRaisesRegex(ValueError, 'diagnostic observer binding'):
            self.verify()

    def test_observer_after_snapshot_and_symlink_are_independently_rejected(self):
        self.report['diagnostic_observer_sources_after'] = {}
        with self.assertRaisesRegex(ValueError, 'diagnostic observer binding'):
            self.verify()
        self.report['diagnostic_observer_sources_after'] = copy.deepcopy(
            self.report['diagnostic_observer_sources_before'])
        helper = self.root / 'scripts/qa/collect_diagnostic_observer.mjs'
        moved = self.root / 'same-bytes.mjs'
        helper.rename(moved)
        helper.symlink_to(moved)
        with self.assertRaisesRegex(ValueError, 'Repository-local regular evidence'):
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


class GraphScopedBrowserSourceBindingTest(unittest.TestCase):
    """Actual Ruby graph observations participate in Python publication checks."""
    def setUp(self):
        source_root = Path(__file__).resolve().parents[2]
        base = BrowserSourceBindingTest()
        base.setUp()
        self.addCleanup(base.doCleanups)
        self.root, self.export, self.report = base.root, base.export, base.report
        for directory in (self.root, self.export):
            for relative in ("scripts/public_app_media.rb", "scripts/qa/asset_manifest_integrity.rb"):
                (directory / relative).write_bytes((source_root / relative).read_bytes())
            files = {
                "pubspec.yaml": "name: collect_app\ndependency_overrides:\n  file_saver:\n    path: third_party/file_saver\n  synthetic_fork:\n    path: third_party/synthetic_fork\n  firebase_messaging:\n    path: third_party/firebase_messaging\n",
                "pubspec.lock": "bound package versions", ".fvmrc": '{"flutter":"3.44.4"}', ".metadata": "project metadata",
                "analysis_options.yaml": "fixture options", "web/index.html": "web scaffold",
                "tool/public_app_media_capture.dart": "import 'package:collect_app/main.dart';\n",
            }
            for package in ("file_saver", "synthetic_fork", "firebase_messaging"):
                files.update({f"third_party/{package}/{relative}": "bound local package source" for relative in
                              ("lib/runtime.dart", "pubspec.yaml", "LICENSE", "COLLECT_FORK.md")})
            for relative, value in files.items():
                path = directory / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value)
        snapshot = json.loads(PUBLICATION.subprocess.check_output([
            "ruby", "-r", "./scripts/public_app_media", "-e",
            "puts JSON.generate(PublicAppMedia.new(Dir.pwd).browser_source_snapshot)"],
            cwd=self.export, text=True))
        self.runtime = PUBLICATION.hashlib.sha256("".join(
            name + "\0" + digest + "\n" for name, digest in snapshot.items()).encode()).hexdigest()
        self.report.update({"runtime_fingerprint_version": 4,
                            "browser_entrypoint": "tool/public_app_media_capture.dart",
                            "checkout_runtime_before_sha256": self.runtime,
                            "checkout_runtime_after_sha256": self.runtime,
                            "sources_before": copy.deepcopy(snapshot), "sources_after": snapshot,
                            "checkout_browser_sources_before": copy.deepcopy(snapshot),
                            "checkout_browser_sources_after": copy.deepcopy(snapshot)})

    def verify(self):
        PUBLICATION.validate_browser_source_binding(self.report, self.runtime)

    def test_actual_complete_graph_survives_only_unrelated_admin_native_changes(self):
        self.verify()
        for name in ("lib/admin/new_control.dart", "android/app/src/new_callback.kt"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("new unrelated source")
        self.verify()

    def test_actual_reachable_checkout_mutation_is_rejected(self):
        (self.root / "lib/main.dart").write_text("changed reachable source")
        with self.assertRaisesRegex(ValueError, "reachable source closure differs"):
            self.verify()

    def test_omitting_a_bound_input_from_the_report_is_rejected(self):
        self.report["sources_after"].pop("lib/main.dart")
        with self.assertRaisesRegex(ValueError, "reachable source closure differs"):
            self.verify()

    def test_new_actual_reachable_import_is_rejected_without_recapture(self):
        (self.root / "lib/new.dart").write_text("new reachable source")
        with (self.root / "lib/main.dart").open("a") as stream:
            stream.write("\nimport 'new.dart';\n")
        with self.assertRaisesRegex(ValueError, "reachable source closure differs"):
            self.verify()


class AndroidCaptureBoundaryTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which('java'), 'Android fixture boundary requires Java')
    def test_manifest_transform_removes_only_implicit_storage_and_rejects_invalid_inputs(self):
        source = Path(__file__).resolve().parents[2] / 'android/qa/CollectFixtureManifest.java'
        xmlns = 'http://schemas.android.com/apk/res/android'
        valid = (
            '<manifest xmlns:android="' + xmlns + '" package="app.cool.mobile.mediafixture">'
            '<uses-permission android:name="android.permission.INTERNET"/>'
            '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>'
            '<uses-permission-sdk-23 android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>'
            '<application android:debuggable="true" android:allowBackup="false"/>'
            '</manifest>'
        )
        cases = {
            'accepted': valid,
            'wrong_package': valid.replace('app.cool.mobile.mediafixture', 'app.cool.mobile'),
            'extra_permission': valid.replace('</manifest>', '<uses-permission android:name="android.permission.RECEIVE_SMS"/></manifest>'),
            'external_entity': '<!DOCTYPE manifest [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>' + valid,
        }
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            for name, xml in cases.items():
                with self.subTest(name=name):
                    original, result = directory / (name + '.xml'), directory / (name + '-out.xml')
                    original.write_text(xml)
                    run = subprocess.run(['java', '--source', '17', str(source), str(original), str(result)],
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
                    if name != 'accepted':
                        self.assertNotEqual(run.returncode, 0)
                        self.assertFalse(result.exists())
                        continue
                    self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
                    root = ET.parse(result).getroot()
                    permissions = [node.get('{' + xmlns + '}name') for node in root
                                   if node.tag in ('uses-permission', 'uses-permission-sdk-23')]
                    self.assertEqual(permissions, ['android.permission.INTERNET'])

    def test_media_flavor_manifest_and_producer_are_bound_native_inputs(self):
        self.assertTrue(PUBLICATION.native_input("android/app/src/media_capture/AndroidManifest.xml"))
        self.assertTrue(PUBLICATION.native_input("android/app/build.gradle.kts"))
        self.assertTrue(PUBLICATION.native_input("tool/native_public_app_media_capture.dart"))
        self.assertIn("scripts/qa/native_android_public_app_media.py", PUBLICATION.ANDROID_CAPTURE_CONTROLS)

    def test_publisher_and_reader_agree_on_privacy_fixture_input(self):
        root = Path(__file__).resolve().parents[2]
        fixture = 'test/features/privacy/privacy_test_support.dart'
        self.assertTrue(PUBLICATION.native_input(fixture))
        result = subprocess.run(
            ['ruby', '-r', './scripts/public_app_media', '-e',
             'exit(PublicAppMedia.new(Dir.pwd).send(:native_capture_input?, ARGV.fetch(0)) ? 0 : 1)', fixture],
            cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))

    def test_prepare_refuses_canonical_workspace_before_any_build(self):
        import argparse
        from unittest.mock import patch
        path = Path(__file__).resolve().parents[1] / 'qa/native_android_public_app_media.py'
        spec = importlib.util.spec_from_file_location('synthetic_android_boundary', path)
        recorder = importlib.util.module_from_spec(spec); spec.loader.exec_module(recorder)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            args = argparse.Namespace(checkout=root, source=root, output=root / '.cache/test')
            with patch.object(recorder, 'command') as execute:
                with self.assertRaisesRegex(ValueError, 'isolated source export'): recorder.prepare(args)
                execute.assert_not_called()


if __name__ == "__main__":
    unittest.main()
