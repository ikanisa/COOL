#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

PATH = Path(__file__).resolve().parents[1] / 'qa/resolved_native_package_inputs.py'
SPEC = importlib.util.spec_from_file_location('actual_native_packages', PATH)
INPUTS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INPUTS)


class NativePackageInputsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.export, self.sdk, self.cache = (self.root / name for name in ['export', 'sdk', 'pub_cache'])
        for path in [self.export, self.sdk, self.cache]:
            path.mkdir()
        self.hosted = self.cache / 'hosted/pub.dev/demo_plugin-1.0.0'
        self.sdk_package = self.sdk / 'packages/flutter'
        self.write(self.hosted / 'lib/demo_plugin.dart', 'original dependency source')
        self.write(self.hosted / 'android/src/Plugin.kt', 'original native plugin source')
        self.write(self.hosted / 'LICENSE', 'retained licence')
        self.write(self.sdk_package / 'lib/material.dart', 'actual SDK source')
        self.packages = []
        for name, relative in INPUTS.LOCAL_PACKAGES.items():
            path = self.export / relative
            path.mkdir(parents=True, exist_ok=True)
            self.write(path / 'lib/source.dart', 'controlled source ' + name)
            self.packages.append({'name': name, 'rootUri': path.as_uri() + '/', 'packageUri': 'lib/'})
        self.packages += [{'name': 'flutter', 'rootUri': self.sdk_package.as_uri() + '/', 'packageUri': 'lib/'},
                          {'name': 'demo_plugin', 'rootUri': self.hosted.as_uri() + '/', 'packageUri': 'lib/'}]
        self.plugins = {'plugins': {'android': [{'name': 'file_saver', 'path': str(self.export / 'third_party/file_saver') + '/'},
                                                {'name': 'demo_plugin', 'path': str(self.hosted) + '/'}]}}
        self.save_bindings()

    def write(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def save_bindings(self):
        self.write(self.export / '.dart_tool/package_config.json', json.dumps({'configVersion': 2, 'packages': self.packages}))
        self.write(self.export / '.flutter-plugins-dependencies', json.dumps(self.plugins))

    def bind(self):
        return INPUTS.bind(self.export, self.sdk, self.cache)

    def test_actual_hosted_dart_native_and_licence_files_are_copied_and_rebound(self):
        result = self.bind()
        clone = self.export / '.qa_native_dependencies/demo_plugin'
        self.assertEqual(INPUTS.source_files(clone), INPUTS.source_files(self.hosted))
        self.assertEqual(INPUTS.verify(result, self.export)['status'], 'pass')
        config = json.loads((self.export / '.dart_tool/package_config.json').read_text())
        roots = {row['name']: row['rootUri'] for row in config['packages']}
        self.assertEqual(roots['demo_plugin'], clone.as_uri() + '/')
        self.assertEqual(roots['flutter'], self.sdk_package.as_uri() + '/')
        plugin = json.loads((self.export / '.flutter-plugins-dependencies').read_text())['plugins']['android'][1]
        self.assertEqual(plugin['path'], str(clone) + '/')

    def test_later_mutation_of_original_pub_cache_does_not_change_compiled_copy(self):
        result = self.bind()
        self.write(self.hosted / 'lib/demo_plugin.dart', 'later unrelated cache mutation')
        self.assertEqual(INPUTS.verify(result, self.export)['status'], 'pass')
        self.assertEqual((self.export / '.qa_native_dependencies/demo_plugin/lib/demo_plugin.dart').read_text(), 'original dependency source')

    def test_actual_copied_addition_deletion_and_byte_changes_fail(self):
        result = self.bind()
        clone = self.export / '.qa_native_dependencies/demo_plugin'
        self.write(clone / 'lib/addition.dart', 'new dependency input')
        (clone / 'LICENSE').unlink()
        self.write(clone / 'android/src/Plugin.kt', 'modified native input')
        observed = INPUTS.verify(result, self.export)
        self.assertEqual(observed['status'], 'fail')
        self.assertEqual(set(observed['changes']['demo_plugin']), {'LICENSE', 'lib/addition.dart', 'android/src/Plugin.kt'})

    def test_actual_sdk_source_mutation_fails(self):
        result = self.bind()
        self.write(self.sdk_package / 'lib/material.dart', 'changed SDK code')
        self.assertEqual(INPUTS.verify(result, self.export)['status'], 'fail')

    def test_changed_generated_binding_fails(self):
        result = self.bind()
        self.write(self.export / '.flutter-plugins-dependencies', '{}')
        self.assertIn('generated_bindings', INPUTS.verify(result, self.export)['changes'])

    def test_external_uri_unknown_cache_root_and_wrong_sdk_are_rejected(self):
        for uri in ['https://example.invalid/source', self.export.as_uri(), (self.sdk / 'packages').as_uri()]:
            self.packages[-1]['rootUri'] = uri
            self.save_bindings()
            with self.assertRaises(ValueError):
                self.bind()
            self.assertFalse((self.export / '.qa_native_dependencies').exists())

    def test_missing_duplicate_and_unsafe_packages_rejected(self):
        original = list(self.packages)
        for invalid in [original[1:], original + [original[-1]], original + [{'name': '../escape', 'rootUri': self.hosted.as_uri()}]]:
            self.packages = invalid
            self.save_bindings()
            with self.assertRaises(ValueError):
                self.bind()
            self.assertFalse((self.export / '.qa_native_dependencies').exists())

    def test_plugin_mismatch_or_unknown_plugin_fails_before_copy(self):
        for entry in [{'name': 'unknown', 'path': str(self.hosted)}, {'name': 'demo_plugin', 'path': str(self.export)}]:
            self.plugins['plugins']['android'] = [entry]
            self.save_bindings()
            with self.assertRaises(ValueError):
                self.bind()
            self.assertFalse((self.export / '.qa_native_dependencies').exists())

    def test_actual_package_symlink_and_private_configuration_fail(self):
        link = self.hosted / 'lib/escape.dart'
        link.symlink_to(self.sdk_package / 'lib/material.dart')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.bind()
        link.unlink()
        self.write(self.hosted / '.env', 'must never be copied or printed')
        with self.assertRaisesRegex(ValueError, 'Private configuration'):
            self.bind()
        self.assertFalse((self.export / '.qa_native_dependencies').exists())

    def test_root_qa_and_generated_directories_are_explicitly_excluded(self):
        self.write(self.hosted / 'example/.env', 'excluded example configuration')
        self.write(self.hosted / 'test/fixture.dart', 'excluded QA input')
        self.write(self.hosted / 'build/generated.bin', 'excluded generated output')
        self.write(self.hosted / 'lib/build/actual.dart', 'real source directory named build')
        result = self.bind()
        self.assertIn('lib/build/actual.dart', result['packages']['demo_plugin']['files'])
        self.assertEqual(len(result['packages']['demo_plugin']['files']), 4)

    def test_resource_bounds_fail_before_copy_and_fresh_destination_is_required(self):
        with patch.object(INPUTS, 'MAX_FILES', 1):
            with self.assertRaisesRegex(ValueError, 'resource bounds'):
                self.bind()
        self.assertFalse((self.export / '.qa_native_dependencies').exists())
        self.bind()
        with self.assertRaisesRegex(ValueError, 'Fresh native dependency destination'):
            self.bind()


if __name__ == '__main__':
    unittest.main()
