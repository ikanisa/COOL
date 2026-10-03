#!/usr/bin/env python3
"""Meaningful compiler-path and generated-source mutation checks."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[1] / "qa/swift_generated_plugin_inputs.py"
SPEC = importlib.util.spec_from_file_location("generated_swift_inputs", TOOL)
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class GeneratedSwiftInputsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name).resolve()
        self.export = self.base / "export"
        self.export.mkdir()
        self.package_dir = self.export / "ios/Flutter/ephemeral/Packages"
        self.aliases = self.package_dir / ".packages"
        self.aliases.mkdir(parents=True)
        self.pod_aliases = self.export / "ios/.symlinks/plugins"
        self.pod_aliases.mkdir(parents=True)
        self.generated = self.package_dir / "FlutterGeneratedPluginSwiftPackage"
        self.generated.mkdir()
        self.framework = self.aliases / "FlutterFramework"
        self.framework.mkdir()
        (self.framework / "Package.swift").write_text("// generated framework\n")
        self.binding = {"packages": {}, "local_roots": {}}
        self.plugins = []
        self.names = {}
        self.add_plugin("core", hosted=True)
        self.add_plugin("messaging", hosted=False, dependency="core")
        self.seal()

    def tearDown(self):
        self.temp.cleanup()

    def add_plugin(self, name, *, hosted, dependency=None, darwin=False, sdk=False):
        original = self.base / ("sdk/" + name if sdk else "cache/" + name + "-1.2.3")
        root = self.export / (".qa_native_dependencies/" + name if hosted else "third_party/" + name)
        if sdk:
            root = original
        suffix = Path("darwin" if darwin else "ios") / name
        manifest = '// swift tools\n' + ('.package(name: "' + dependency + '", path: "../' + dependency + '")\n' if dependency else "")
        for directory in {original / suffix, root / suffix}:
            directory.mkdir(parents=True)
            (directory / "Package.swift").write_text(manifest)
            (directory / "source.swift").write_text("// actual " + name + " implementation\n")
        if hosted or sdk:
            self.binding["packages"][name] = {"original_root": str(original), "build_root": str(root), "role": "sdk" if sdk else "hosted", "files": M.regular_tree(root)}
        else:
            self.binding["local_roots"][name] = str(root)
            original = root
        self.plugins.append({"name": name, "path": str(root) + "/", "shared_darwin_source": darwin, "native_build": True})
        (self.pod_aliases / name).symlink_to(root, target_is_directory=True)
        alias_name = original.name
        target = original / suffix
        if dependency:
            target = self.export / "build/ios/SourcePackages" / alias_name / suffix
            target.mkdir(parents=True)
            (target / "source.swift").write_bytes((root / suffix / "source.swift").read_bytes())
            (target / "Package.swift").write_text(manifest.replace('"../' + dependency + '"', '"../' + self.names[dependency] + '"'))
        (self.aliases / alias_name).symlink_to(target, target_is_directory=True)
        self.names[name] = alias_name

    def seal(self):
        self.declared = {path.relative_to(self.export).as_posix(): M.sha(path)
                         for path in (self.export / "third_party").rglob("*") if path.is_file()}
        plugin_path = self.export / ".flutter-plugins-dependencies"
        plugin_path.write_text(json.dumps({"plugins": {"ios": self.plugins}}))
        self.binding["plugin_binding_sha256"] = M.sha(plugin_path)
        (self.generated / "Package.swift").write_text("\n".join('.package(name: "' + name + '", path: "../.packages/' + alias + '")' for name, alias in {**self.names, "FlutterFramework": "FlutterFramework"}.items()))

    def bind(self):
        return M.bind(self.export, self.binding, self.declared)

    def test_actual_hosted_alias_redirect_and_generated_manifest_binding(self):
        receipt = self.bind()
        row = receipt["packages"]["core"]
        self.assertTrue(Path(row["compiler_root"]).is_relative_to(self.export / ".qa_native_dependencies"))
        self.assertEqual((self.aliases / self.names["core"]).resolve(), Path(row["compiler_root"]))
        self.assertEqual(receipt["packages"]["messaging"]["generated_manifest_rewrites"], [{"original": '"../core"', "replacement": '"../core-1.2.3"'}])
        self.assertEqual(M.verify(receipt, self.export)["status"], "pass")

    def test_darwin_and_explicit_sdk_roots(self):
        self.add_plugin("darwin_plugin", hosted=True, darwin=True)
        self.add_plugin("integration_test", hosted=False, sdk=True)
        self.seal()
        receipt = self.bind()
        self.assertTrue(receipt["packages"]["darwin_plugin"]["compiler_root"].endswith("darwin/darwin_plugin"))
        self.assertTrue(Path(receipt["packages"]["integration_test"]["compiler_root"]).is_relative_to(self.base / "sdk"))

    def test_unknown_generated_alias_refused_before_any_redirect(self):
        before = os.readlink(self.aliases / self.names["core"])
        (self.aliases / "unknown").mkdir()
        with self.assertRaisesRegex(ValueError, "Unknown, duplicate or missing"):
            self.bind()
        self.assertEqual(os.readlink(self.aliases / self.names["core"]), before)

    def test_missing_dependency_fails_closed(self):
        text = (self.generated / "Package.swift").read_text()
        (self.generated / "Package.swift").write_text(text.replace('.package(name: "core", path: "../.packages/core-1.2.3")', ""))
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            self.bind()

    def test_unknown_directive_refused(self):
        with (self.generated / "Package.swift").open("a") as f:
            f.write('\n.package(url: "https://example.invalid/plugin", from: "1.0.0")')
        with self.assertRaisesRegex(ValueError, "Unknown generated"):
            self.bind()

    def test_alias_escape_refused(self):
        alias = self.aliases / self.names["core"]
        alias.unlink()
        alias.symlink_to(self.base)
        with self.assertRaisesRegex(ValueError, "escapes"):
            self.bind()

    def test_manifest_path_escape_refused(self):
        p = self.generated / "Package.swift"
        p.write_text(p.read_text().replace("../.packages/core-1.2.3", "../../cache/core"))
        with self.assertRaisesRegex(ValueError, "escaped"):
            self.bind()

    def test_original_hosted_source_mismatch_refused(self):
        original = Path(self.binding["packages"]["core"]["original_root"])
        (original / "ios/core/source.swift").write_text("// unexpected mutation")
        with self.assertRaisesRegex(ValueError, "bytes differ"):
            self.bind()

    def test_generated_manifest_extra_edit_refused(self):
        target = (self.aliases / self.names["messaging"]).resolve()
        with (target / "Package.swift").open("a") as f:
            f.write("\n// extra unexpected mutation")
        with self.assertRaisesRegex(ValueError, "Unreviewed"):
            self.bind()

    def test_generated_native_source_edit_refused(self):
        target = (self.aliases / self.names["messaging"]).resolve()
        (target / "source.swift").write_text("// unexpected implementation")
        with self.assertRaisesRegex(ValueError, "Unreviewed"):
            self.bind()

    def test_framework_symlink_refused(self):
        import shutil
        shutil.rmtree(self.framework)
        self.framework.symlink_to(self.base)
        with self.assertRaisesRegex(ValueError, "framework alias"):
            self.bind()

    def test_source_alias_inside_native_package_refused(self):
        source = self.export / ".qa_native_dependencies/core/ios/core"
        (source / "hidden.swift").symlink_to(source / "source.swift")
        with self.assertRaisesRegex(ValueError, "Unexpected alias"):
            self.bind()

    def test_postbuild_alias_retargeting_detected(self):
        receipt = self.bind()
        alias = self.aliases / self.names["core"]
        alias.unlink()
        alias.symlink_to(self.base)
        self.assertEqual(M.verify(receipt, self.export)["status"], "fail")

    def test_postbuild_native_source_add_delete_or_change_detected(self):
        receipt = self.bind()
        root = Path(receipt["packages"]["core"]["compiler_root"])
        (root / "source.swift").unlink()
        (root / "new.swift").write_text("// added")
        self.assertEqual(M.verify(receipt, self.export)["status"], "fail")

    def test_postbuild_generated_scaffold_mutation_detected(self):
        receipt = self.bind()
        (self.framework / "new.swift").write_text("// changed generated source")
        self.assertEqual(M.verify(receipt, self.export)["status"], "fail")

    def test_postbuild_alias_addition_detected(self):
        receipt = self.bind()
        (self.aliases / "new_alias").mkdir()
        self.assertEqual(M.verify(receipt, self.export)["status"], "fail")

    def test_changed_resolved_plugin_binding_refused(self):
        (self.export / ".flutter-plugins-dependencies").write_text("{}")
        with self.assertRaisesRegex(ValueError, "binding changed"):
            self.bind()

    def test_compiler_source_resource_bound(self):
        before = M.MAX_FILES
        M.MAX_FILES = 1
        try:
            with self.assertRaisesRegex(ValueError, "resource bound"):
                self.bind()
        finally:
            M.MAX_FILES = before

    def test_copied_native_source_mutation_cannot_be_rebaselined(self):
        root = self.export / ".qa_native_dependencies/core/ios/core"
        (root / "source.swift").write_text("// unexpected new baseline")
        with self.assertRaisesRegex(ValueError, "Declared native source changed"):
            self.bind()

    def test_local_fork_mutation_cannot_be_rebaselined(self):
        root = self.export / "third_party/messaging/ios/messaging"
        (root / "source.swift").write_text("// unexpected new local baseline")
        with self.assertRaisesRegex(ValueError, "Declared native source changed"):
            self.bind()

    def test_read_only_preflight_preserves_actual_generated_aliases(self):
        alias = self.aliases / self.names["core"]
        before = os.readlink(alias)
        receipt = M.bind(self.export, self.binding, self.declared, dry_run=True)
        self.assertEqual(receipt["status"], "pass")
        self.assertTrue(receipt["dry_run"])
        self.assertEqual(os.readlink(alias), before)
        self.assertEqual(len(receipt["planned_redirections"]), 1)

    def test_native_package_alias_redirects_to_bound_copy(self):
        alias = self.pod_aliases / "core"
        alias.unlink()
        alias.symlink_to(Path(self.binding["packages"]["core"]["original_root"]))
        receipt = self.bind()
        self.assertEqual(alias.resolve(), Path(self.binding["packages"]["core"]["build_root"]))
        self.assertEqual(M.verify(receipt, self.export)["status"], "pass")

    def test_unknown_native_alias_refused(self):
        (self.pod_aliases / "unknown").symlink_to(self.base)
        with self.assertRaisesRegex(ValueError, "Unknown or missing"):
            self.bind()

    def test_postbuild_native_alias_retargeting_detected(self):
        receipt = self.bind()
        alias = self.pod_aliases / "core"
        alias.unlink()
        alias.symlink_to(self.base)
        self.assertEqual(M.verify(receipt, self.export)["status"], "fail")


if __name__ == "__main__":
    unittest.main()
