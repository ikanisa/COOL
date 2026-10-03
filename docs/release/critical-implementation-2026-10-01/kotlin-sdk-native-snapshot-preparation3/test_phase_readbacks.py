#!/usr/bin/env python3
"""Synthetic Python readers only; no real SDK, exporter, Flutter or Gradle action."""
import hashlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time
import types
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
ORIGINAL = HERE.parent / 'kotlin-sdk-native-consumer-preparation1'
EVIDENCE = {}


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


controller = module(HERE / 'run_native_consumer.py', 'phase_reader_controller')
fence = module(HERE / 'source_fence.py', 'phase_reader_fence')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    with Path(path).open('x') as output:
        json.dump(value, output, indent=2, sort_keys=True)
        output.write('\n')
        output.flush()
        os.fsync(output.fileno())


READER = '''import json, os, sys
from pathlib import Path
phase = sys.argv[1]
output = Path(sys.argv[sys.argv.index('--output') + 1])
print('synthetic SDK reader', phase, output.name)
if os.environ.get('FAIL_OBSERVATION') and ('-' + os.environ['FAIL_OBSERVATION'] + '-') in output.name:
    print('genuine synthetic reader exit 23', file=sys.stderr)
    raise SystemExit(23)
with output.open('x') as stream:
    json.dump({'synthetic_only': True, 'phase': phase, 'output_name': output.name}, stream)
'''

FENCE_READER = '''import json, sys
from pathlib import Path
output = Path(sys.argv[sys.argv.index('--output') + 1])
with output.open('x') as stream:
    json.dump({'synthetic_source_fence': True}, stream)
print('synthetic source fence')
'''

EXPORTER = '''import sys
from pathlib import Path
app = Path(sys.argv[sys.argv.index('--destination') + 1])
app.mkdir(mode=0o700)
(app / 'pubspec.lock').write_text('synthetic app lock')
print('synthetic app exporter')
'''


class PhaseReadbackTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='COOL-snapshot3-reader-', dir='/private/tmp')).resolve()
        self.assertTrue(str(self.root).startswith('/private/tmp/'))
        self.assertEqual(self.root, self.root.resolve())
        self.fixture = self.root / 'reader'
        self.fixture.mkdir(mode=0o700)
        for name in ('publisher_metadata.py', 'consumer_guards.py'):
            (self.fixture / name).write_bytes((ORIGINAL / name).read_bytes())
        (self.fixture / 'verify_native_consumer_source.py').write_text(READER)
        self.run = self.root / 'direct'
        self.run.mkdir(mode=0o700)
        self.env = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}
        self.here_patch = mock.patch.object(controller, 'HERE', self.fixture)
        self.here_patch.start()

    def tearDown(self):
        self.here_patch.stop()
        shutil.rmtree(self.root)

    def retain(self, directory, **extra):
        records = {path.name: json.loads(path.read_text()) for path in directory.glob('*.json')}
        logs = {path.name: path.read_text() for path in directory.iterdir()
                if path.suffix in ('.stdout', '.stderr')}
        EVIDENCE[self._testMethodName] = dict(records=records, logs=logs,
            synthetic_fixture_root=str(self.root), fixture_removed_after_test=True,
            real_stage_execution=False, **extra)

    def test_same_startup_phase_has_distinct_before_after_artifacts(self):
        before = controller.source_readback(self.run, 'startup', self.env, 'before')
        after = controller.source_readback(self.run, 'startup', self.env, 'after')
        expected = {f'SDK-readback-{point}-startup{suffix}'
                    for point in ('before', 'after') for suffix in ('.json', '.stdout', '.stderr')}
        expected.update(f'SDK-source-{point}-startup.json' for point in ('before', 'after'))
        self.assertEqual({path.name for path in self.run.iterdir()}, expected)
        outputs = []
        for point, result in (('before', before), ('after', after)):
            record = result['process']
            output = self.run / f'SDK-source-{point}-startup.json'
            self.assertEqual(record['argv'], [sys.executable, '-I', '-B',
                str(self.fixture / 'verify_native_consumer_source.py'), 'startup', '--output', str(output)])
            self.assertEqual(record['deadline_seconds'], 300)
            self.assertEqual(record['exit_code'], 0)
            self.assertFalse(record['timed_out'])
            self.assertFalse(record['headroom_failure'])
            self.assertTrue(record['owned_process_group_absent'])
            self.assertEqual(result['output_sha256'], digest(output))
            outputs.append(str(output))
        self.assertNotEqual(outputs[0], outputs[1])
        self.retain(self.run, distinct_paths=sorted(expected), live_floor_bytes=controller.LIVE_FLOOR)

    def test_repeated_before_observation_still_refuses_reuse(self):
        controller.source_readback(self.run, 'startup', self.env, 'before')
        original = (self.run / 'SDK-readback-before-startup.stdout').read_bytes()
        with self.assertRaises(FileExistsError):
            controller.source_readback(self.run, 'startup', self.env, 'before')
        self.assertEqual((self.run / 'SDK-readback-before-startup.stdout').read_bytes(), original)
        self.retain(self.run, repeated_observation_refused=True)

    def test_invalid_observation_refused_without_artifacts(self):
        with self.assertRaisesRegex(ValueError, 'unreviewed SDK source observation'):
            controller.source_readback(self.run, 'startup', self.env, '../after')
        self.assertEqual(list(self.run.iterdir()), [])
        self.retain(self.run, invalid_observation_refused=True)

    def synthetic_main_failure(self, point):
        base = self.root / 'native-consumer'
        base.mkdir(mode=0o700)
        (base / '.control').mkdir(mode=0o700)
        prior = base / '.control/startup'
        prior.mkdir(mode=0o700)
        write_json(prior / 'terminal.json', {'stage_pass': True, 'stage': 'startup'})
        sdk = base / 'flutter'
        lock = sdk / 'packages/flutter_tools/pubspec.lock'
        lock.parent.mkdir(parents=True)
        lock.write_text('synthetic SDK lock')
        app = base / 'app-source'
        proposal = self.root / 'proposal'
        proposal.mkdir(mode=0o700)
        (proposal / 'source_fence.py').write_text(FENCE_READER)
        repo = self.root / 'repo'
        exporter = repo / 'scripts/qa/collect_release_candidate.py'
        exporter.parent.mkdir(parents=True)
        exporter.write_text(EXPORTER)
        auth = self.root / 'review'
        auth.mkdir(mode=0o700)
        source_fence = auth / 'source-fence.json'
        write_json(source_fence, {'synthetic_source_fence': True})
        admission = auth / 'app-export-admission.json'
        write_json(admission, {'required_source_fence_sha256': digest(source_fence)})
        config = json.loads((HERE / 'proposed-commands.json').read_text())
        config.update(Python_executable=str(Path(sys.executable).resolve()), Python_SHA256=digest(sys.executable),
            Node_executable=str(Path(sys.executable).resolve()), Node_SHA256=digest(sys.executable),
            reviewed_exporter_SHA256=digest(exporter), environment_exact=dict(self.env, FAIL_OBSERVATION=point))
        config['commands']['app-export'] = {'argv': [sys.executable, '-I', '-B', str(exporter),
            '--destination', str(app)], 'cwd': str(repo), 'deadline_seconds': 300}
        write_json(proposal / 'proposed-commands.json', config)
        guards = module(self.fixture / 'consumer_guards.py', 'synthetic_terminal_guards_' + point)
        guards.SDK_LOCK = digest(lock)
        actual_load = controller.load
        synthetic_fence = types.SimpleNamespace(validate_commands=lambda *args: None,
            private_destination=fence.private_destination, private_candidate=fence.private_candidate)

        def fixture_load(path, name):
            if name in ('native_stage_guards', 'controller_guards', 'prior_terminal_reader'):
                return guards
            if name == 'strict_snapshot_guard':
                return synthetic_fence
            return actual_load(path, name)

        exported = {'export_manifest_file_sha256': 'a' * 64, 'source_manifest_sha256': 'b' * 64,
            'source_files_exact': {'pubspec.lock': {'sha256': digest(lock)}}}
        argv = [str(HERE / 'run_native_consumer.py'), '--stage', 'app-export',
            '--prepared-manifest-sha256', 'c' * 64, '--root-review-sha256', digest(admission)]
        with mock.patch.multiple(controller, BASE=base, SDK=sdk, APP=app, PROPOSAL=proposal,
                REPO=repo, AUTH_DIR=auth, SOURCE_FENCE=source_fence), \
                mock.patch.object(controller, 'authorization', return_value={}), \
                mock.patch.object(controller, 'protected_metadata', return_value={'synthetic_fixture_only': True}), \
                mock.patch.object(controller, 'load', side_effect=fixture_load), \
                mock.patch.object(guards, 'app_readback', return_value=exported), \
                mock.patch.object(sys, 'argv', argv):
            with self.assertRaisesRegex(ValueError, 'genuine terminal stage failure'):
                controller.main()
        directory = base / '.control/app-export'
        terminal = json.loads((directory / 'terminal.json').read_text())
        self.assertFalse(terminal['stage_pass'])
        self.assertTrue(terminal['partial_failure_preserved'])
        self.assertFalse(terminal['retry_or_next_stage_admitted'])
        self.assertFalse(terminal['candidate_promoted'])
        self.assertFalse(terminal['production_release_approval'])
        self.assertFalse((directory / 'export-source-binding.json').exists())
        failure = json.loads((directory / f'SDK-readback-{point}-startup.json').read_text())
        self.assertEqual(failure['exit_code'], 23)
        self.assertEqual(failure['deadline_seconds'], 300)
        self.assertTrue(failure['owned_process_group_absent'])
        if point == 'before':
            self.assertFalse((directory / 'actual-command.json').exists())
            self.assertFalse(app.exists())
        else:
            self.assertTrue(app.exists())
            self.assertEqual(json.loads((directory / 'SDK-readback-before-startup.json').read_text())['exit_code'], 0)
            self.assertEqual(json.loads((directory / 'actual-command.json').read_text())['exit_code'], 0)
            self.assertEqual(json.loads((directory / 'source-fence-after.json').read_text())['exit_code'], 0)
        self.retain(directory, injected_failure_observation=point,
            synthetic_overrides=['authorization', 'config validation', 'protected metadata',
                'exporter and fence child programs', 'app readback', 'isolated roots/config/SDK lock'],
            actual_original_process_success_guard_used=True,
            actual_run_process_and_exception_terminal_branch_used=True)

    def test_before_reader_failure_is_terminal_before_export(self):
        self.synthetic_main_failure('before')

    def test_after_reader_failure_is_terminal_after_export(self):
        self.synthetic_main_failure('after')


if __name__ == '__main__':
    inputs = [HERE / 'run_native_consumer.py', HERE / 'source_fence.py', HERE / 'proposed-commands.json',
        Path(__file__).resolve(), ORIGINAL / 'publisher_metadata.py', ORIGINAL / 'consumer_guards.py']
    before = {str(path): digest(path) for path in inputs}
    suite = unittest.TestLoader().loadTestsFromTestCase(PhaseReadbackTests)
    if suite.countTestCases() != 5:
        raise ValueError('unexpected focused case count')
    started = time.monotonic()
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    after = {str(path): digest(path) for path in inputs}
    unchanged = before == after
    write_json(HERE / 'phase-readback-test-case-records.json', EVIDENCE)
    write_json(HERE / 'phase-readback-test-result.json', dict(tests_run=result.testsRun,
        failures=len(result.failures), errors=len(result.errors), skips=len(result.skipped),
        actual_seconds=round(time.monotonic() - started, 6), source_hashes_before=before,
        source_hashes_after=after, source_inputs_unchanged=unchanged,
        fixture_parent='/private/tmp', fixtures_removed=True, real_stage_execution=False,
        live_floor_bytes=controller.LIVE_FLOOR, per_reader_deadline_seconds=300))
    raise SystemExit(0 if result.wasSuccessful() and unchanged and result.testsRun == 5 and not result.skipped else 1)
