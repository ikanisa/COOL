"""Frozen Admin working-source closure and actual local package resolution."""

import contextlib
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import admin_cloudflare_source as source

MIGRATION = '0012_gateway_receiver_ingress.sql'


def create_source_tree(root):
    """A finite physical source closure with both declared local package forks."""
    root.mkdir(parents=True, exist_ok=True)
    for directory in source.SOURCE_DIRS:
        (root / directory).mkdir(parents=True, exist_ok=True)
        (root / directory / 'source-input.txt').write_text('original input')
    for name in source.SOURCE_FILES:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('required physical input ' + name)
    (root / 'pubspec.yaml').write_text('''name: collect_test
dependencies:
  file_saver:
    path: third_party/file_saver
dependency_overrides:
  synthetic_fork:
    path: third_party/synthetic_fork
''')
    packages = []
    for name in ('file_saver', 'synthetic_fork'):
        folder = root / 'third_party' / name
        (folder / 'lib').mkdir(parents=True)
        (folder / 'lib' / (name + '.dart')).write_text('library ' + name + ';')
        (folder / 'pubspec.yaml').write_text('name: ' + name + '\n')
        (folder / 'README.md').write_text('physical fork ' + name)
        packages.append({'name': name, 'rootUri': '../third_party/' + name, 'packageUri': 'lib/'})
    (root / '.dart_tool').mkdir()
    (root / '.dart_tool/package_config.json').write_text(json.dumps({'configVersion': 2, 'packages': packages}))
    (root / 'deploy/admin-api/migrations' / MIGRATION).write_text('-- real minimum schema fixture')
    return root


def freeze_source(root, manifest_path):
    """Build a valid source receipt without creating Git state or invoking builds."""
    value = source.inputs(root)
    value.update(source_commit='a' * 40, source_dirty=False)
    source.validate_source_manifest(value)
    source.write_json(manifest_path, value)
    return value


class AdminSourceClosureTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='collect-admin-source-test-', dir=Path(tempfile.gettempdir()).resolve())
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.root = create_source_tree(self.directory / 'working-source')
        self.manifest = self.directory / 'source.json'

    def freeze(self):
        return freeze_source(self.root, self.manifest)

    def test_closure_includes_both_forks_and_all_required_release_helpers(self):
        value = self.freeze()
        paths = {row['path'] for row in value['files']}
        for name in ('file_saver', 'synthetic_fork'):
            self.assertIn(f'third_party/{name}/lib/{name}.dart', paths)
            self.assertIn(f'third_party/{name}/pubspec.yaml', paths)
            self.assertIn(f'third_party/{name}/README.md', paths)
        self.assertTrue(set(source.SOURCE_FILES) <= paths)
        self.assertEqual(value, source.verify_source_manifest(self.root, self.manifest))

    def test_file_directory_punctuation_uses_relative_string_order(self):
        (self.root / 'lib/a').mkdir()
        (self.root / 'lib/a/item.dart').write_text('nested source')
        (self.root / 'lib/a-z.dart').write_text('sibling source')
        value = self.freeze()
        paths = [row['path'] for row in value['files']]
        self.assertEqual(sorted(paths), paths)
        self.assertLess(paths.index('lib/a-z.dart'), paths.index('lib/a/item.dart'))

    def test_local_fork_edit_addition_and_removal_invalidate_current_proof(self):
        for mode in ('edit', 'add', 'remove'):
            with self.subTest(mode=mode):
                self.freeze()
                path = self.root / 'third_party/file_saver/lib/file_saver.dart'
                original = path.read_text()
                added = path.with_name('new_web_behavior.dart')
                if mode == 'edit':
                    path.write_text('unreviewed fork edit')
                elif mode == 'add':
                    added.write_text('new compiled fork input')
                else:
                    path.unlink()
                for check_resolution in (True, False):
                    with self.assertRaises(source.SourceError):
                        source.verify_source_manifest(self.root, self.manifest, check_resolution=check_resolution)
                path.write_text(original)
                if added.exists():
                    added.unlink()

    def test_pure_local_preflight_verifier_needs_no_compiler_yaml_subprocess_or_network(self):
        value = self.freeze()
        (self.root / '.dart_tool/package_config.json').unlink()
        with patch.object(source.subprocess, 'run', side_effect=AssertionError('No subprocess in frozen preflight')), patch.object(source.subprocess, 'check_output', side_effect=AssertionError('No Git subprocess in frozen preflight')):
            self.assertEqual(value, source.verify_source_manifest(self.root, self.manifest, check_resolution=False))
        with self.assertRaises(source.SourceError):
            source.verify_source_manifest(self.root, self.manifest)

    def test_record_preserves_cli_shape_and_records_real_git_identity(self):
        def git_result(command, **kwargs):
            self.assertEqual(self.root, kwargs['cwd'])
            return 'b' * 40 + '\n' if command[1] == 'rev-parse' else ' M lib/source-input.txt\n'
        with patch.object(source.subprocess, 'check_output', side_effect=git_result):
            value = source.record_source_manifest(self.root, self.manifest)
        self.assertEqual({'files', 'source_manifest_sha256', 'source_commit', 'source_dirty'}, set(value))
        self.assertEqual('b' * 40, value['source_commit'])
        self.assertTrue(value['source_dirty'])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, source.main(['verify', str(self.manifest)], root=self.root))

    def test_wrong_missing_or_unsafe_actual_package_resolution_is_refused(self):
        config_path = self.root / '.dart_tool/package_config.json'
        original = config_path.read_text()
        alterations = [
            lambda value: value['packages'][0].update(rootUri='../third_party/synthetic_fork'),
            lambda value: value['packages'][0].update(packageUri='../private/'),
            lambda value: value['packages'][0].update(rootUri='https://attacker.invalid/file_saver'),
            lambda value: value['packages'][0].update(rootUri='file://remote/path'),
            lambda value: value['packages'][0].update(rootUri='../third_party/file_saver?alternate=true'),
            lambda value: value['packages'].pop(0),
            lambda value: value['packages'].append(value['packages'][0]),
        ]
        for alteration in alterations:
            with self.subTest(alteration=alteration):
                value = json.loads(original)
                alteration(value)
                config_path.write_text(json.dumps(value))
                with self.assertRaises(source.SourceError):
                    source.inputs(self.root)

    def test_unsafe_missing_and_misnamed_declared_paths_are_refused(self):
        pubspec = self.root / 'pubspec.yaml'
        original = pubspec.read_text()
        for path in ('../outside', '/tmp/outside', 'third_party/%2e%2e/outside', 'third_party\\file_saver', 'third_party/missing'):
            with self.subTest(path=path):
                pubspec.write_text(original.replace('third_party/file_saver', path))
                with self.assertRaises(source.SourceError):
                    source.inputs(self.root)
        pubspec.write_text(original)
        (self.root / 'third_party/file_saver/pubspec.yaml').write_text('name: incorrect_package\n')
        with self.assertRaises(source.SourceError):
            source.inputs(self.root)

    def test_yaml_duplicate_keys_and_aliases_are_not_ambiguous_source_declarations(self):
        for text in ('name: collect_test\ndependencies:\n  file_saver: {path: third_party/file_saver}\n  file_saver: {path: third_party/synthetic_fork}\n', 'name: collect_test\ndependencies: &shared {}\ndependency_overrides: *shared\n'):
            (self.root / 'pubspec.yaml').write_text(text)
            with self.assertRaises(source.SourceError):
                source.inputs(self.root)

    def test_runtime_transitive_path_dependency_is_included_and_resolved(self):
        parent = self.root / 'third_party/file_saver'
        (parent / 'pubspec.yaml').write_text('name: file_saver\ndependencies:\n  local_helper: {path: vendor/local_helper}\n')
        child = parent / 'vendor/local_helper'
        (child / 'lib').mkdir(parents=True)
        (child / 'pubspec.yaml').write_text('name: local_helper\n')
        (child / 'lib/helper.dart').write_text('library helper;')
        config_path = self.root / '.dart_tool/package_config.json'
        config = json.loads(config_path.read_text())
        config['packages'].append({'name': 'local_helper', 'rootUri': '../third_party/file_saver/vendor/local_helper', 'packageUri': 'lib/'})
        config_path.write_text(json.dumps(config))
        frozen = self.freeze()
        self.assertIn('third_party/file_saver/vendor/local_helper/lib/helper.dart', {row['path'] for row in frozen['files']})
        self.assertEqual(frozen, source.verify_source_manifest(self.root, self.manifest, check_resolution=False))

    def test_required_files_directories_and_physical_source_are_fail_closed(self):
        required = self.root / source.SOURCE_FILES[-1]
        content = required.read_bytes()
        required.unlink()
        with self.assertRaises(source.SourceError):
            source.inputs(self.root)
        required.write_bytes(content)
        (self.root / 'lib/source-input.txt').unlink()
        (self.root / 'lib').rmdir()
        with self.assertRaises(source.SourceError):
            source.inputs(self.root)

    def test_source_symlink_files_and_directories_and_hardlinks_are_refused(self):
        target = self.directory / 'unrelated-source'
        target.write_text('outside input retained')
        path = self.root / 'lib/symlink.dart'
        path.symlink_to(target)
        with self.assertRaises(source.SourceError):
            source.inputs(self.root)
        path.unlink()
        (self.root / 'lib/linked-source').symlink_to(self.directory, target_is_directory=True)
        with self.assertRaises(source.SourceError):
            source.inputs(self.root)
        (self.root / 'lib/linked-source').unlink()
        import os
        os.link(target, path)
        with self.assertRaises(source.SourceError):
            source.inputs(self.root)
        self.assertEqual('outside input retained', target.read_text())

    def test_tampered_digest_paths_order_duplicates_and_identity_are_refused(self):
        original = self.freeze()
        alterations = [
            lambda value: value.update(source_manifest_sha256='0' * 64),
            lambda value: value['files'].reverse(),
            lambda value: value['files'].append(value['files'][-1]),
            lambda value: value['files'][0].update(path='../outside'),
            lambda value: value['files'][0].update(sha256='not-a-hash'),
            lambda value: value.update(source_commit='unbound'),
            lambda value: value.update(source_dirty=0),
            lambda value: value.update(hosted_acceptance_verified=True),
        ]
        for alteration in alterations:
            with self.subTest(alteration=alteration):
                value = json.loads(json.dumps(original))
                alteration(value)
                with self.assertRaises(source.SourceError):
                    source.validate_source_manifest(value)

    def test_valid_digest_cannot_hide_changed_inventory_or_bytes(self):
        value = self.freeze()
        value['files'][0]['sha256'] = '0' * 64
        value['source_manifest_sha256'] = hashlib.sha256(source.canonical(value['files'])).hexdigest()
        source.write_json(self.manifest, value)
        with self.assertRaises(source.SourceError):
            source.verify_source_manifest(self.root, self.manifest, check_resolution=False)

    def test_manifest_read_and_write_refuse_duplicate_json_and_output_symlinks(self):
        self.manifest.write_text('{"files":[],"files":[]}')
        with self.assertRaises(source.SourceError):
            source.read_json(self.manifest)
        self.manifest.unlink()
        target = self.directory / 'original-record'
        target.write_text('retained record')
        self.manifest.symlink_to(target)
        with self.assertRaises(source.SourceError):
            source.write_json(self.manifest, {'replacement': True})
        self.assertEqual('retained record', target.read_text())


if __name__ == '__main__':
    unittest.main()
