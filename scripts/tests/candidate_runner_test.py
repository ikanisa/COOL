#!/usr/bin/env python3
"""Runner orchestration tests using disposable fake SDKs, NOT Flutter tests."""
from pathlib import Path
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('candidate_check_runner', ROOT / 'scripts/qa/verify_candidate.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class CandidateRunnerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='candidate validation ')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'checkout'
        self.root.mkdir()
        self.targets = ['lib/sample.dart', 'test/sample_test.dart']
        for rel in [*self.targets, 'pubspec.lock']:
            self.write(rel, 'fixture only; never compiled\n')
        self.write('pubspec.yaml', 'name: collect_app\n')
        self.write('.fvmrc', json.dumps({'flutter': '3.44.4'}))
        self.write(runner.SCOPE_PATH, json.dumps({
            'schema_version': 1, 'format_targets': self.targets,
            'widget_tests': ['test/sample_test.dart'],
        }))
        self.write('.dart_tool/package_config.json', json.dumps({
            'configVersion': 2, 'packages': [
                {'name': name, 'rootUri': '../'}
                for name in ['collect_app', 'flutter', 'flutter_test']
            ],
        }))
        self.log = Path(self.tmp.name) / 'commands.jsonl'
        self.bin = Path(self.tmp.name) / 'SDK with spaces'
        self.bin.mkdir()
        self.env = dict(SDK_LOG=str(self.log))
        self.flutter = self.fake('flutter')
        self.dart = self.fake('dart')

    def write(self, rel, contents):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    def fake(self, name):
        path = self.bin / name
        path.write_text('#!' + sys.executable + '\n' + '''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
name = Path(sys.argv[0]).name
with open(os.environ['SDK_LOG'], 'a') as out:
    out.write(json.dumps([name, *args]) + '\\n')
if args[:2] == ['--version', '--machine']:
    if os.environ.get('BAD_VERSION_JSON'):
        print('not version JSON')
    else:
        print(json.dumps({'frameworkVersion': os.environ.get('FRAMEWORK_VERSION', '3.44.4'),
                          'dartSdkVersion': '3.12.2'}))
elif args == ['--version']:
    print('Dart SDK version: ' + os.environ.get('DART_VERSION', '3.12.2') + ' (stable)', file=sys.stderr)
if args and args[0] == os.environ.get('MUTATE_STAGE'):
    Path(os.environ.get('MUTATE_FILE', 'pubspec.lock')).write_text('changed by fake tool')
if args and args[0] == os.environ.get('FAIL_STAGE'):
    sys.exit(9)
''')
        path.chmod(0o755)
        return str(path)

    def call(self, run=True, **kwargs):
        with patch.dict(os.environ, self.env):
            return runner.validate(self.root, run=run, flutter=self.flutter,
                                   dart=self.dart, timeout=10, **kwargs)

    def commands(self):
        return [json.loads(s) for s in self.log.read_text().splitlines()] if self.log.exists() else []

    def scope(self, **updates):
        path = self.root / runner.SCOPE_PATH
        data = json.loads(path.read_text())
        data.update(updates)
        path.write_text(json.dumps(data))

    def assertBlocked(self):
        report, code = self.call()
        self.assertEqual(code, 2)
        self.assertEqual(report['status'], 'blocked')
        self.assertFalse(report['application_checks_passed'])
        self.assertEqual(report['application_checks_started'], [])

    def test_check_only_never_runs_application_stages(self):
        report, code = self.call(run=False)
        self.assertEqual(code, 0)
        self.assertEqual(report['status'], 'ready_not_executed')
        self.assertEqual([x[1] for x in self.commands()], ['--version', '--version'])
        self.assertEqual(report['application_checks_started'], [])
        self.assertFalse(report['application_checks_passed'])

    def test_mock_success_is_in_order_without_pub_or_format_writes(self):
        report, code = self.call()
        self.assertEqual(code, 0)
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['application_checks_completed'], ['format', 'analyze', 'test'])
        self.assertFalse(report['release_authorized'])
        self.assertFalse(report['package_resolution_performed'])
        calls = self.commands()
        self.assertEqual([x[1] for x in calls], ['--version', '--version', 'format', 'analyze', 'test'])
        self.assertIn('--output=none', calls[2])
        self.assertIn('--set-exit-if-changed', calls[2])
        self.assertIn('--no-pub', calls[3])
        self.assertIn('--fatal-infos', calls[3])
        self.assertIn('--no-pub', calls[4])

    def test_missing_flutter_blocks(self):
        self.flutter = str(self.bin / 'not-installed')
        self.assertBlocked()
        self.assertEqual(self.commands(), [])

    def test_missing_dart_blocks(self):
        self.dart = str(self.bin / 'not-installed')
        self.assertBlocked()

    def test_wrong_flutter_version_blocks(self):
        self.env['FRAMEWORK_VERSION'] = '3.0.0'
        self.assertBlocked()

    def test_wrong_dart_version_blocks(self):
        self.env['DART_VERSION'] = '3.0.0'
        self.assertBlocked()

    def test_malformed_version_json_blocks(self):
        self.env['BAD_VERSION_JSON'] = '1'
        self.assertBlocked()

    def test_version_probe_error_blocks(self):
        self.env['FAIL_STAGE'] = '--version'
        self.assertBlocked()

    def test_each_application_failure_stops_subsequent_stages(self):
        for stage in ['format', 'analyze', 'test']:
            with self.subTest(stage=stage):
                self.log.unlink(missing_ok=True)
                self.env['FAIL_STAGE'] = stage
                report, code = self.call()
                self.assertEqual(code, 9)
                self.assertEqual(report['status'], 'failed')
                self.assertEqual(self.commands()[-1][1], stage)
                self.assertFalse(report['application_checks_passed'])

    def test_missing_checkout_file_blocks(self):
        for rel in [*runner.CHECKOUT_FILES, *self.targets]:
            with self.subTest(path=rel):
                path = self.root / rel
                old = path.read_bytes()
                path.unlink()
                self.assertBlocked()
                path.write_bytes(old)

    def test_wrong_project_name_blocks(self):
        self.write('pubspec.yaml', 'name: unrelated_project\n')
        self.assertBlocked()

    def test_empty_lockfile_blocks(self):
        self.write('pubspec.lock', '')
        self.assertBlocked()

    def test_non_exact_flutter_pin_blocks(self):
        self.write('.fvmrc', '{"flutter":"stable"}')
        self.assertBlocked()

    def test_invalid_package_config_blocks(self):
        self.write('.dart_tool/package_config.json', '{"configVersion":2,"packages":[]}')
        self.assertBlocked()

    def test_duplicate_package_entries_block(self):
        path = self.root / '.dart_tool/package_config.json'
        data = json.loads(path.read_text())
        data['packages'].append(data['packages'][0])
        path.write_text(json.dumps(data))
        self.assertBlocked()

    def test_other_checkout_package_root_blocks(self):
        path = self.root / '.dart_tool/package_config.json'
        data = json.loads(path.read_text())
        data['packages'][0]['rootUri'] = '../../'
        path.write_text(json.dumps(data))
        self.assertBlocked()

    def test_remote_package_root_blocks_without_fetching(self):
        path = self.root / '.dart_tool/package_config.json'
        data = json.loads(path.read_text())
        data['packages'][0]['rootUri'] = 'https://invalid.example/never-fetch/'
        path.write_text(json.dumps(data))
        self.assertBlocked()
        self.assertEqual(self.commands(), [])

    def test_duplicate_json_keys_block(self):
        self.write('.fvmrc', '{"flutter":"3.44.4","flutter":"3.44.4"}')
        self.assertBlocked()

    def test_duplicate_or_empty_test_scope_blocks(self):
        self.scope(widget_tests=['test/sample_test.dart', 'test/sample_test.dart'])
        self.assertBlocked()
        self.scope(widget_tests=[])
        self.assertBlocked()

    def test_unformatted_test_in_scope_blocks(self):
        self.scope(format_targets=['lib/sample.dart'])
        self.assertBlocked()

    def test_path_traversal_and_non_dart_targets_block(self):
        for path in ['../escape.dart', '/tmp/absolute.dart', 'lib/../outside.dart',
                     'lib\\windows.dart', 'scripts/not-a-test.py']:
            with self.subTest(path=path):
                self.scope(format_targets=[path])
                self.assertBlocked()

    def test_symlink_source_file_blocks(self):
        path = self.root / 'lib/sample.dart'
        path.unlink()
        path.symlink_to(self.root / 'test/sample_test.dart')
        self.assertBlocked()

    def test_input_change_during_version_probe_blocks(self):
        self.env.update(MUTATE_STAGE='--version', MUTATE_FILE='pubspec.lock')
        self.assertBlocked()

    def test_source_or_lock_change_during_format_fails_without_restoring(self):
        for rel in ['pubspec.lock', 'lib/sample.dart', runner.SCOPE_PATH]:
            with self.subTest(path=rel):
                path = self.root / rel
                old = path.read_bytes()
                self.env.update(MUTATE_STAGE='format', MUTATE_FILE=rel)
                report, code = self.call()
                self.assertEqual(code, 2)
                self.assertEqual(report['status'], 'failed')
                self.assertEqual(report['application_checks_started'], ['format'])
                self.assertFalse(report['application_checks_passed'])
                self.assertEqual(path.read_text(), 'changed by fake tool')
                path.write_bytes(old)

    def test_invalid_timeout_blocks_before_processes(self):
        report, code = runner.validate(self.root, timeout=float('nan'))
        self.assertEqual(code, 2)
        self.assertEqual(report['status'], 'blocked')
        self.assertEqual(self.commands(), [])

    def test_scope_lists_existing_tests_and_format_targets(self):
        scope = json.loads((ROOT / runner.SCOPE_PATH).read_text())
        self.assertTrue(set(scope['widget_tests']).issubset(scope['format_targets']))
        self.assertTrue(all((ROOT / rel).is_file() for rel in scope['widget_tests']))
        self.assertIn('test/connection_recovery_screen_test.dart', scope['widget_tests'])
        self.assertIn('test/connection_recovery_screens_test.dart', scope['widget_tests'])
        self.assertIn('test/form_viewport_namespace_test.dart', scope['widget_tests'])

    def test_ci_keeps_full_suite_analysis_and_tooling_checks(self):
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn('run: make qa-tooling-test', ci)
        self.assertIn('flutter test --concurrency=4 --exclude-tags=integration', ci)
        self.assertIn('flutter analyze --fatal-infos', ci)
        self.assertIn('contents: read', ci)


if __name__ == '__main__':
    unittest.main(verbosity=2)
