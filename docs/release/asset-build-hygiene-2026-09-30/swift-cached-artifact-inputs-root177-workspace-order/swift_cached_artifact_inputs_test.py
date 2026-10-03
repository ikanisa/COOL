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

    def add_artifact(self):
        relative = Path("firebase-ios-sdk/FirebaseFirestoreInternal/FirebaseFirestoreInternal.xcframework")
        prior = self.prior / "artifacts" / relative
        shutil.copytree(self.prior / "artifacts" / self.relative, prior, symlinks=True)
        shutil.copytree(prior, self.cache / "artifacts" / relative, symlinks=True)
        def append(state):
            row = copy.deepcopy(state["object"]["artifacts"][0])
            row.update(targetName="FirebaseFirestoreInternal", path=str(prior))
            state["object"]["artifacts"].append(row)
        self.update_state(append)

    def reverse_artifacts(self):
        path = self.cache / "workspace-state.json"
        state = json.loads(path.read_text())
        state["object"]["artifacts"].reverse()
        path.write_text(json.dumps(state))
        return path, state

    def test_artifact_row_order_preserves_exact_metadata_and_bytes(self):
        self.add_artifact()
        binding = self.bind()
        self.reverse_artifacts()
        result = TOOL.verify(binding)
        self.assertTrue(result["workspace_metadata_unchanged"])
        self.assertTrue(result["workspace_entry_order_changed"])
        self.assertTrue(result["cached_binary_inputs_unchanged"])
        self.assertFalse(result["workspace_bytes_unchanged"])

    def test_dependency_row_order_preserves_exact_locked_metadata(self):
        def append(state):
            row = copy.deepcopy(state["object"]["dependencies"][0])
            row["packageRef"]["identity"] = "app-check"
            row["subpath"] = "app-check"
            state["object"]["dependencies"].append(row)
        self.update_state(append)
        lock_path = self.export / "ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        lock = json.loads(lock_path.read_text())
        lock["pins"].append({"identity": "app-check", "state": {"revision": "a" * 40}})
        lock_path.write_text(json.dumps(lock))
        binding = self.bind()
        path = self.cache / "workspace-state.json"
        state = json.loads(path.read_text())
        state["object"]["dependencies"].reverse()
        path.write_text(json.dumps(state))
        self.assertTrue(TOOL.verify(binding)["workspace_entry_order_changed"])

    def test_reordered_artifact_checksum_change_is_refused(self):
        self.add_artifact()
        binding = self.bind()
        path, state = self.reverse_artifacts()
        state["object"]["artifacts"][0]["source"]["checksum"] = "c" * 64
        path.write_text(json.dumps(state))
        with self.assertRaisesRegex(ValueError, "metadata changed"):
            TOOL.verify(binding)

    def test_reordered_artifact_omission_is_refused(self):
        self.add_artifact()
        binding = self.bind()
        path, state = self.reverse_artifacts()
        state["object"]["artifacts"].pop()
        path.write_text(json.dumps(state))
        with self.assertRaisesRegex(ValueError, "metadata changed"):
            TOOL.verify(binding)

    def test_reordered_duplicate_artifact_is_refused(self):
        self.add_artifact()
        binding = self.bind()
        path, state = self.reverse_artifacts()
        state["object"]["artifacts"].append(copy.deepcopy(state["object"]["artifacts"][0]))
        path.write_text(json.dumps(state))
        with self.assertRaisesRegex(ValueError, "Duplicate binary artifact"):
            TOOL.verify(binding)

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

    def local_fixture(self, legacy_alias=False):
        aliases = self.export / 'ios/Flutter/ephemeral/Packages/.packages'
        aliases.mkdir(parents=True)
        compiler = self.export / '.qa_native_dependencies/example/ios/example'
        compiler.mkdir(parents=True)
        (compiler / 'Package.swift').write_bytes(b'current bound plugin')
        alias = aliases / 'example'
        alias.symlink_to(compiler)
        framework = aliases / 'FlutterFramework'
        framework.mkdir()
        (framework / 'Package.swift').write_bytes(b'current framework manifest')
        generated = {'status': 'pass', 'kind': 'actual_generated_swift_compiler_input_binding',
            'alias_root': str(aliases), 'alias_names': sorted(p.name for p in aliases.iterdir()),
            'packages': {'example': {'alias': str(alias), 'bound_link': str(compiler),
                'compiler_root': str(compiler), 'files': {'Package.swift': TOOL.digest(compiler / 'Package.swift')}}},
            'framework_root': str(framework), 'framework_files': {'Package.swift': TOOL.digest(framework / 'Package.swift')}}
        prior_root = self.prior.parents[2]
        def add_local(state):
            for name, filename in [('example', 'example-1.2.3' if legacy_alias else 'example'), ('FlutterFramework', 'FlutterFramework')]:
                path = prior_root / aliases.relative_to(self.export) / filename
                state['object']['dependencies'].append({'basedOn': None, 'packageRef': {
                    'identity': filename.lower(), 'kind': 'fileSystem', 'location': str(path), 'name': name},
                    'state': {'name': 'fileSystem', 'path': str(path)}, 'subpath': filename})
        self.update_state(add_local)
        return generated, compiler

    def test_exact_local_compiler_aliases_relocated_and_verified(self):
        generated, _ = self.local_fixture()
        binding = TOOL.bind(self.export, self.prior, generated)
        self.assertEqual(2, binding['local_package_count'])
        self.assertEqual(3, len(binding['relocations']))
        self.assertTrue(TOOL.verify(binding)['cached_binary_inputs_unchanged'])

    def test_versioned_cache_alias_uses_bound_current_compiler_identity(self):
        generated, _ = self.local_fixture(legacy_alias=True)
        binding = TOOL.bind(self.export, self.prior, generated)
        row = next(r for r in binding['workspace_state']['object']['dependencies'] if r['packageRef'].get('name') == 'example')
        self.assertEqual('example', row['packageRef']['identity'])
        self.assertEqual('example', row['subpath'])
        self.assertTrue(TOOL.verify(binding)['workspace_metadata_unchanged'])

    def test_local_metadata_without_generated_proof_refused(self):
        self.local_fixture()
        with self.assertRaisesRegex(ValueError, 'Unbound local workspace dependency'):
            self.bind()

    def test_unexpected_local_package_refused(self):
        generated, _ = self.local_fixture()
        self.update_state(lambda state: state['object']['dependencies'][1]['packageRef'].update(name='unbound'))
        with self.assertRaisesRegex(ValueError, 'Unbound local workspace dependency'):
            TOOL.bind(self.export, self.prior, generated)

    def test_wrong_local_prior_root_refused(self):
        generated, _ = self.local_fixture()
        self.update_state(lambda state: state['object']['dependencies'][1]['packageRef'].update(location='/other/export/example'))
        with self.assertRaisesRegex(ValueError, 'Unknown prior local package alias'):
            TOOL.bind(self.export, self.prior, generated)

    def test_missing_generated_local_dependency_refused(self):
        generated, _ = self.local_fixture()
        self.update_state(lambda state: state['object']['dependencies'].pop())
        with self.assertRaisesRegex(ValueError, 'local dependency set differs'):
            TOOL.bind(self.export, self.prior, generated)

    def test_duplicate_local_dependency_refused(self):
        generated, _ = self.local_fixture()
        self.update_state(lambda state: state['object']['dependencies'].append(copy.deepcopy(state['object']['dependencies'][1])))
        with self.assertRaisesRegex(ValueError, 'local dependency set differs'):
            TOOL.bind(self.export, self.prior, generated)

    def test_mutated_current_local_compiler_refused(self):
        generated, compiler = self.local_fixture()
        (compiler / 'Package.swift').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'local compiler files changed'):
            TOOL.bind(self.export, self.prior, generated)

    def test_late_current_local_compiler_mutation_refused(self):
        generated, compiler = self.local_fixture()
        binding = TOOL.bind(self.export, self.prior, generated)
        (compiler / 'Package.swift').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'local compiler files changed'):
            TOOL.verify(binding)

    def test_local_alias_retarget_refused(self):
        generated, _ = self.local_fixture()
        binding = TOOL.bind(self.export, self.prior, generated)
        alias = Path(generated['packages']['example']['alias'])
        alias.unlink(); alias.symlink_to(self.root)
        with self.assertRaisesRegex(ValueError, 'Local compiler alias changed'):
            TOOL.verify(binding)

    def test_case_preserved_remote_checkout_basename_matches_identity(self):
        self.update_state(lambda state: state['object']['dependencies'][0].update(subpath='Firebase-Ios-Sdk'))
        self.assertTrue(TOOL.verify(self.bind())['workspace_metadata_unchanged'])

    def test_other_remote_checkout_basename_refused(self):
        self.update_state(lambda state: state['object']['dependencies'][0].update(subpath='another-checkout'))
        with self.assertRaisesRegex(ValueError, 'Unexpected dependency identity/path'):
            self.bind()

    def test_remote_checkout_path_escape_refused(self):
        self.update_state(lambda state: state['object']['dependencies'][0].update(subpath='../firebase-ios-sdk'))
        with self.assertRaisesRegex(ValueError, 'Unexpected dependency identity/path'):
            self.bind()


if __name__ == "__main__":
    unittest.main()
