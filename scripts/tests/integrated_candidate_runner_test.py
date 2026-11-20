#!/usr/bin/env python3
"""Test validation-runner orchestration with fake SDKs; never compile Dart."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / 'scripts/qa/run_integrated_candidate_checks.sh'
COMPACT_RUNNER = ROOT / 'scripts/qa/run_compact_ui_checks.sh'

class IntegratedRunnerTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.runner = self.root / 'scripts/qa/run_integrated_candidate_checks.sh'
        self.runner.parent.mkdir(parents=True)
        shutil.copyfile(RUNNER, self.runner)
        self.compact_runner = self.runner.with_name(COMPACT_RUNNER.name)
        shutil.copyfile(COMPACT_RUNNER, self.compact_runner)
        target_block = RUNNER.read_text().split('TARGETS=(\n', 1)[1].split('\n)', 1)[0]
        self.targets = [line.strip() for line in target_block.splitlines()]
        for rel in ['pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json',
                    'admin-web/package.json', 'admin-web/package-lock.json', *self.targets]:
            path = self.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('isolated uncompiled test fixture\n')
        (self.root / '.fvmrc').write_text(json.dumps({'flutter': '3.44.4'}))
        self.log = self.root / 'sdk_calls.jsonl'
        # Scrub overrides rather than depending on the executor's environment.
        self.env = {k:v for k,v in os.environ.items() if not k.startswith(('FAKE_', 'FAIL_'))}
        self.env['SDK_LOG'] = str(self.log)
        self.env['FLUTTER_BIN'] = self.fake_sdk('flutter')
        self.env['DART_BIN'] = self.fake_sdk('dart')
        self.env['NODE_BIN'] = self.fake_sdk('node')
        self.env['NPM_BIN'] = self.fake_sdk('npm')

    def fake_sdk(self, name):
        p = self.root / name
        p.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
name = Path(sys.argv[0]).name
with open(os.environ['SDK_LOG'], 'a') as stream:
    stream.write(json.dumps([name, *args]) + '\\n')
stage = os.environ.get('FAIL_STAGE')
if (args and args[0] == stage or
    (name == 'flutter' and '--platform' in args and stage == 'browser') or
    (name in {'npm', 'node'} and args[-1] == stage)):
    sys.exit(int(os.environ.get('FAIL_CODE', '4')))
if args == ['--version', '--machine']:
    if os.environ.get('FAKE_MALFORMED'):
        print('not JSON')
    else:
        print(json.dumps({'frameworkVersion': os.environ.get('FAKE_FLUTTER', '3.44.4'),
                          'dartSdkVersion': os.environ.get('FAKE_BUNDLED_DART', '3.12.0')}))
elif name == 'dart' and args == ['--version']:
    print('Dart SDK version: ' + os.environ.get('FAKE_DART', '3.12.0') + ' (stable) on "linux_x64"')
''')
        p.chmod(0o755)
        return str(p)

    def run_gate(self, runner=None):
        return subprocess.run(['bash', str(runner or self.runner)], cwd=self.root, env=self.env,
                              text=True, capture_output=True, timeout=15)

    def calls(self):
        return [json.loads(s) for s in self.log.read_text().splitlines()] if self.log.exists() else []

    def assert_blocked(self):
        result = self.run_gate()
        self.assertEqual(result.returncode, 2, result.stdout+result.stderr)
        self.assertNotIn('PASS:', result.stdout)
        self.assertIn('BLOCKED:', result.stderr)

    def test_missing_flutter(self):
        self.env['FLUTTER_BIN'] = str(self.root/'absent')
        self.assert_blocked()
        self.assertEqual(self.calls(), [])

    def test_missing_dart(self):
        self.env['DART_BIN'] = str(self.root/'absent')
        self.assert_blocked()
        self.assertEqual(self.calls(), [])

    def test_missing_full_checkout_inputs(self):
        for rel in ['pubspec.yaml', 'pubspec.lock', '.fvmrc', '.dart_tool/package_config.json',
                    'admin-web/package.json', 'admin-web/package-lock.json']:
            with self.subTest(rel=rel):
                p=self.root/rel; data=p.read_bytes();p.unlink()
                self.assert_blocked();self.assertEqual(self.calls(), [])
                p.write_bytes(data)

    def test_missing_each_branch_regression_suite(self):
        for rel in ['test/connection_recovery_screen_test.dart','test/connection_recovery_screens_test.dart',
                    'test/collect_lazy_group_list_test.dart','test/form_viewport_namespace_test.dart',
                    'test/collect_disabled_action_regression_test.dart',
                    'test/features/member_roster_screen_test.dart',
                    'test/features/contribution_amount_accessibility_test.dart',
                    'test/features/contribution_command_recovery_test.dart']:
            with self.subTest(rel=rel):
                p=self.root/rel;data=p.read_bytes();p.unlink()
                self.assert_blocked();self.assertEqual(self.calls(), [])
                p.write_bytes(data)

    def test_bad_flutter_pin(self):
        self.env['FAKE_FLUTTER']='0.0.0'
        self.assert_blocked()

    def test_malformed_version_output(self):
        self.env['FAKE_MALFORMED']='1'
        self.assert_blocked()

    def test_malformed_pin(self):
        (self.root/'.fvmrc').write_text('[]')
        self.assert_blocked()

    def test_blank_pin(self):
        (self.root/'.fvmrc').write_text('{"flutter":""}')
        self.assert_blocked()

    def test_mismatched_dart(self):
        self.env['FAKE_DART']='3.0.0'
        self.assert_blocked()

    def test_absent_bundled_dart_version(self):
        self.env['FAKE_BUNDLED_DART']=''
        self.assert_blocked()

    def test_failed_version_command(self):
        self.env.update(FAIL_STAGE='--version',FAIL_CODE='7')
        self.assert_blocked()

    def test_failed_format_does_not_analyze(self):
        self.env.update(FAIL_STAGE='format',FAIL_CODE='4')
        result=self.run_gate()
        self.assertEqual(result.returncode,4)
        self.assertNotIn('PASS:',result.stdout)
        self.assertEqual([r[1] for r in self.calls()],['--version','--version','format'])

    def test_failed_analysis_does_not_run_tests(self):
        self.env.update(FAIL_STAGE='analyze',FAIL_CODE='5')
        result=self.run_gate()
        self.assertEqual(result.returncode,5)
        self.assertNotIn('PASS:',result.stdout)
        self.assertNotIn('test',[r[1] for r in self.calls()])

    def test_failed_test_does_not_pass(self):
        self.env.update(FAIL_STAGE='test',FAIL_CODE='6')
        result=self.run_gate()
        self.assertEqual(result.returncode,6)
        self.assertNotIn('PASS:',result.stdout)

    def test_mock_success_checks_whole_checkout_without_pub(self):
        result=self.run_gate()
        self.assertEqual(result.returncode,0,result.stderr)
        calls = [['--dart-define-from-file=<original>' if argument.startswith('--dart-define-from-file=') else argument
                  for argument in call] for call in self.calls()[3:]]
        self.assertEqual(calls, [
            ['flutter', 'analyze', '--no-pub', '--fatal-infos'],
            ['flutter', 'test', '--no-pub', '--concurrency=1', '--exclude-tags=integration', '--reporter=expanded'],
            ['npm', '--prefix', 'admin-web', 'run', 'typecheck'],
            ['npm', '--prefix', 'admin-web', 'run', 'lint'],
            ['npm', '--prefix', 'admin-web', 'test'],
            ['node', '--test', 'admin-web/tests/pwa/package-pwa.test.mjs'],
            ['node', 'scripts/tests/admin_pwa_worker_cache_test.mjs'],
        ])
        self.assertIn('--output=none',self.calls()[2])
        self.assertIn('--set-exit-if-changed',self.calls()[2])
        self.assertIn('PASS:',result.stdout)

    def test_declared_flutter_targets_exist_in_the_checkout(self):
        for rel in self.targets:
            with self.subTest(target=rel):
                self.assertTrue((ROOT / rel).is_file())

    def test_admin_failure_stops_before_the_package_checks(self):
        self.env.update(FAIL_STAGE='lint', FAIL_CODE='9')
        result = self.run_gate()
        self.assertEqual(result.returncode, 9)
        self.assertNotIn('PASS:', result.stdout)
        self.assertEqual(self.calls()[-1], ['npm', '--prefix', 'admin-web', 'run', 'lint'])

    def test_compact_checks_use_member_and_react_ui_fixtures(self):
        result = self.run_gate(self.compact_runner)
        self.assertEqual(result.returncode, 0, result.stderr)
        member = ['test/collect_form_viewport_test.dart', 'test/features/member_roster_screen_test.dart',
                  'test/features/contribution_amount_accessibility_test.dart']
        admin = ['tests/foundation/shell.test.tsx', 'tests/core/transaction-reverse.test.tsx']
        self.assertEqual(self.calls()[-2:], [
            ['flutter', 'test', '--no-pub', '--reporter', 'expanded', *member],
            ['npm', '--prefix', 'admin-web', 'test', '--', *admin],
        ])
        for path in [*(ROOT / item for item in member), *(ROOT / 'admin-web' / item for item in admin)]:
            self.assertTrue(path.is_file(), str(path))

    def test_version_suffix_is_supported(self):
        self.env['FAKE_BUNDLED_DART']='3.12.0 (stable)'
        self.assertEqual(self.run_gate().returncode,0)

    def test_prerelease_identity_must_match_exactly(self):
        self.env.update(FAKE_BUNDLED_DART='3.12.0-1.2.beta',FAKE_DART='3.12.0-1.2.beta')
        self.assertEqual(self.run_gate().returncode,0)
        self.env['FAKE_DART']='3.12.0'
        self.assert_blocked()

if __name__ == '__main__':
    unittest.main(verbosity=2)
