#!/usr/bin/env python3
"""Mutation controls for actual Swift binary cache binding."""

import copy
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "swift_cached_artifact_inputs", Path(__file__).resolve().parents[1] / "qa/swift_cached_artifact_inputs.py"
)
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)


class CacheBindingTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.prior = self.root / "prior-cache"
        self.export = self.root / "export"
        self.cache = self.export / "build/ios/SourcePackages"
        self.relative = Path("firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework")
        framework = self.prior / "artifacts" / self.relative
        framework.mkdir(parents=True)
        (framework / "Info.plist").write_bytes(b"actual binary manifest")
        (framework / "FirebaseAnalytics").write_bytes(b"actual cached Mach-O fixture")
        (framework / "Current").symlink_to("FirebaseAnalytics")
        state = {"version": 6, "object": {"prebuilts": [], "dependencies": [{
            "packageRef": {"identity": "firebase-ios-sdk", "kind": "remoteSourceControl"},
            "subpath": "firebase-ios-sdk", "state": {"name": "sourceControlCheckout", "checkoutState": {"revision": "a" * 40}},
        }], "artifacts": [{
            "packageRef": {"identity": "firebase-ios-sdk"}, "targetName": "FirebaseAnalytics",
            "path": str(framework), "source": {"type": "remote", "checksum": "b" * 64, "url": "https://dl.google.com/firebase/analytics.zip"},
        }]}}
        (self.prior / "workspace-state.json").write_text(json.dumps(state))
        self.cache.parent.mkdir(parents=True)
        shutil.copytree(self.prior, self.cache, symlinks=True)
        lock = self.export / "ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        lock.parent.mkdir(parents=True)
        lock.write_text(json.dumps({"pins": [{"identity": "firebase-ios-sdk", "state": {"revision": "a" * 40}}]}))

    def tearDown(self):
        self.tmp.cleanup()

    def bind(self):
        return TOOL.bind(self.export, self.prior)

    def update_state(self, callback):
        for path in [self.cache / "workspace-state.json", self.prior / "workspace-state.json"]:
            data = json.loads(path.read_text())
            callback(data)
            path.write_text(json.dumps(data))

    def test_exact_copy_relocated_and_verified(self):
        original = (self.prior / "workspace-state.json").read_bytes()
        binding = self.bind()
        self.assertEqual(1, len(binding["relocations"]))
        self.assertEqual(2, binding["regular_file_count"])
        self.assertEqual(1, binding["symlink_count"])
        self.assertEqual(str(self.cache / "artifacts" / self.relative), binding["workspace_state"]["object"]["artifacts"][0]["path"])
        self.assertEqual(original, (self.prior / "workspace-state.json").read_bytes())
        self.assertTrue(TOOL.verify(binding)["cached_binary_inputs_unchanged"])

    def test_compiler_path_stays_current_after_json_reformat(self):
        binding = self.bind()
        state = self.cache / "workspace-state.json"
        state.write_text(json.dumps(json.loads(state.read_text())))
        result = TOOL.verify(binding)
        self.assertTrue(result["workspace_metadata_unchanged"])
        self.assertFalse(result["workspace_bytes_unchanged"])

    def test_mutated_copied_binary_refused_before_binding(self):
        (self.cache / "artifacts" / self.relative / "FirebaseAnalytics").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "differ from the preserved cache"):
            self.bind()

    def test_late_binary_mutation_refused(self):
        binding = self.bind()
        (self.cache / "artifacts" / self.relative / "FirebaseAnalytics").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "changed, appeared or disappeared"):
            TOOL.verify(binding)

    def test_late_added_binary_refused(self):
        binding = self.bind()
        (self.cache / "artifacts" / self.relative / "extra").write_bytes(b"added")
        with self.assertRaisesRegex(ValueError, "changed, appeared or disappeared"):
            TOOL.verify(binding)

    def test_late_removed_binary_refused(self):
        binding = self.bind()
        (self.cache / "artifacts" / self.relative / "Info.plist").unlink()
        with self.assertRaisesRegex(ValueError, "changed, appeared or disappeared"):
            TOOL.verify(binding)

    def test_late_mode_change_refused(self):
        binding = self.bind()
        file = self.cache / "artifacts" / self.relative / "FirebaseAnalytics"
        file.chmod(file.stat().st_mode ^ 0o100)
        with self.assertRaisesRegex(ValueError, "changed, appeared or disappeared"):
            TOOL.verify(binding)

    def test_escaping_symlink_refused(self):
        outside = self.root / "outside"
        outside.write_bytes(b"outside")
        (self.cache / "artifacts" / self.relative / "escape").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "escapes"):
            self.bind()

    def test_other_old_export_path_refused(self):
        self.update_state(lambda state: state["object"]["artifacts"][0].update(path=str(self.root / "other-cache" / "artifacts" / self.relative)))
        with self.assertRaisesRegex(ValueError, "Unexpected prior artifact path"):
            self.bind()

    def test_late_old_export_retarget_refused(self):
        binding = self.bind()
        path = self.cache / "workspace-state.json"
        state = json.loads(path.read_text())
        state["object"]["artifacts"][0]["path"] = str(self.prior / "artifacts" / self.relative)
        path.write_text(json.dumps(state))
        with self.assertRaisesRegex(ValueError, "outside this export"):
            TOOL.verify(binding)

    def test_unlocked_binary_identity_refused(self):
        self.update_state(lambda state: state["object"]["artifacts"][0]["packageRef"].update(identity="unknown"))
        with self.assertRaisesRegex(ValueError, "Unknown binary package"):
            self.bind()

    def test_unlocked_dependency_revision_refused(self):
        self.update_state(lambda state: state["object"]["dependencies"][0]["state"]["checkoutState"].update(revision="c" * 40))
        with self.assertRaisesRegex(ValueError, "differs from lock"):
            self.bind()

    def test_unbound_prebuilt_refused(self):
        self.update_state(lambda state: state["object"].update(prebuilts=[{"path": "unknown"}]))
        with self.assertRaisesRegex(ValueError, "Unbound Swift prebuilt"):
            self.bind()

    def test_duplicate_artifact_refused(self):
        self.update_state(lambda state: state["object"]["artifacts"].append(copy.deepcopy(state["object"]["artifacts"][0])))
        with self.assertRaisesRegex(ValueError, "Duplicate binary artifact"):
            self.bind()

    def test_unknown_artifact_root_refused(self):
        (self.cache / "artifacts/unknown").mkdir()
        with self.assertRaisesRegex(ValueError, "Unknown cached artifact root"):
            self.bind()

    def test_workspace_input_changed_before_relocation_refused(self):
        path = self.cache / "workspace-state.json"
        data = json.loads(path.read_text())
        data["version"] = 99
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "differs before relocation"):
            self.bind()

    def test_late_new_workspace_metadata_refused(self):
        binding = self.bind()
        path = self.cache / "workspace-state.json"
        data = json.loads(path.read_text())
        data["object"]["extra"] = "unknown"
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "metadata changed"):
            TOOL.verify(binding)


if __name__ == "__main__":
    unittest.main()
