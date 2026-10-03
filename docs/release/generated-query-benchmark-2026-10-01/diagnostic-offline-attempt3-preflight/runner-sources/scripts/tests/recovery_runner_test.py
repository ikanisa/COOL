#!/usr/bin/env python3
"""Tests the shell runner's fail-closed orchestration, NOT Flutter or Dart.

Only local disposable fake SDK executables are used. They do not compile code.
"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest

SOURCE_ROOT = Path(__file__).resolve().parents[2]
RUNNER = SOURCE_ROOT / 'scripts/qa/run_recovery_checks.sh'
TARGETS = [
    'lib/features/status/connection_recovery_screens.dart',
    'test/connection_recovery_screen_test.dart',
    'test/collect_disabled_action_regression_test.dart',
]

class RecoveryRunnerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        runner = self.root / 'scripts/qa/run_recovery_checks.sh'
        runner.parent.mkdir(parents=True)
        shutil.copyfile(RUNNER, runner)
        for rel in ['pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json', *TARGETS]:
            path = self.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('test stub; never compiled\n')
        (self.root / '.fvmrc').write_text(json.dumps({'flutter': '3.44.4'}))
        self.log = self.root / 'commands.jsonl'
        self.env = dict(os.environ, SDK_LOG=str(self.log))
        self.env['FLUTTER_BIN'] = self.fake('flutter')
        self.env['DART_BIN'] = self.fake('dart')
        self.runner = runner

    def fake(self, name):
        path = self.root / name
        path.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['SDK_LOG'], 'a') as stream:
    stream.write(json.dumps([Path(sys.argv[0]).name, *args]) + '\\n')
if args[:2] == ['--version', '--machine']:
    print(json.dumps({'frameworkVersion': os.environ.get('FAKE_VERSION', '3.44.4')}))
if args and args[0] == os.environ.get('FAIL_STAGE'):
    sys.exit(int(os.environ.get('FAIL_CODE', '4')))
''')
        path.chmod(0o755)
        return str(path)

    def run_runner(self):
        return subprocess.run(['bash', str(self.runner)], env=self.env,
                              text=True, capture_output=True, timeout=15)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_missing_flutter_blocks(self):
        self.env['FLUTTER_BIN'] = str(self.root / 'absent')
        result = self.run_runner()
        self.assertEqual(result.returncode, 2)
        self.assertIn('BLOCKED:', result.stderr)
        self.assertEqual(self.commands(), [])

    def test_missing_dart_blocks(self):
        self.env['DART_BIN'] = str(self.root / 'absent')
        self.assertEqual(self.run_runner().returncode, 2)
        self.assertEqual(self.commands(), [])

    def test_missing_checkout_inputs_block(self):
        for rel in ['pubspec.lock', '.dart_tool/package_config.json', TARGETS[1]]:
            with self.subTest(path=rel):
                path = self.root / rel
                original = path.read_bytes()
                path.unlink()
                self.assertEqual(self.run_runner().returncode, 2)
                self.assertEqual(self.commands(), [])
                path.write_bytes(original)

    def test_sdk_pin_mismatch_blocks(self):
        self.env['FAKE_VERSION'] = '0.0.0-wrong'
        self.assertEqual(self.run_runner().returncode, 2)
        self.assertEqual(len(self.commands()), 1)

    def test_formatter_failure_stops_before_analysis(self):
        self.env.update(FAIL_STAGE='format', FAIL_CODE='4')
        result = self.run_runner()
        self.assertEqual(result.returncode, 4)
        self.assertNotIn('PASS:', result.stdout)
        self.assertEqual([row[1] for row in self.commands()], ['--version', 'format'])

    def test_analyzer_failure_stops_before_tests(self):
        self.env.update(FAIL_STAGE='analyze', FAIL_CODE='5')
        result = self.run_runner()
        self.assertEqual(result.returncode, 5)
        self.assertNotIn('PASS:', result.stdout)
        self.assertNotIn('test', [row[1] for row in self.commands()])

    def test_widget_test_failure_is_not_reported_as_pass(self):
        self.env.update(FAIL_STAGE='test', FAIL_CODE='6')
        result = self.run_runner()
        self.assertEqual(result.returncode, 6)
        self.assertNotIn('PASS:', result.stdout)

    def test_successful_mock_orchestration_uses_no_pub(self):
        result = self.run_runner()
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        self.assertEqual([row[1] for row in commands], ['--version', 'format', 'analyze', 'test'])
        self.assertIn('--no-pub', commands[2])
        self.assertIn('--no-pub', commands[3])
        self.assertIn('PASS:', result.stdout)

if __name__ == '__main__':
    unittest.main()
