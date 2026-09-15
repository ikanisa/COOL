#!/usr/bin/env python3
"""Failure-path tests; all Deno execution is replaced with local test doubles."""
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock

MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / 'qa/run_edge_http_uat.py'
SPEC = importlib.util.spec_from_file_location('edge_http_launcher', MODULE_PATH)
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)


class EdgeHTTPLauncherTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name).resolve()
        for path in ['supabase/functions/example/index.ts', 'supabase/config.toml',
                     'scripts/qa/edge_http_runtime_uat.ts', 'scripts/qa/run_edge_http_uat.py',
                     'Makefile', '.github/workflows/ci.yml']:
            file = self.root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('synthetic source\n')
        (self.root / '.dvmrc').write_text('2.5.6\n')
        self.binary = self.root / 'fake-deno'
        self.binary.write_text('not executable; no real runtime is launched\n')
        self.output = self.root / '.cache/evidence'
        for patch in [mock.patch.object(launcher, 'ROOT', self.root),
                      mock.patch.object(launcher.sys, 'argv', ['launcher', str(self.output)]),
                      mock.patch.dict(os.environ, {'DENO_BIN': str(self.binary),
                                                  'SUPABASE_SERVICE_ROLE_KEY': 'must-not-inherit'}, clear=True)]:
            patch.start()
            self.addCleanup(patch.stop)

    def run_launcher(self, response=None, *, info=None):
        metadata = info or {'denoVersion': '2.5.6', 'denoDir': str(self.root / 'deno-cache')}
        if response is None:
            response = self.completed()
        with mock.patch.object(launcher.subprocess, 'check_output', return_value=json.dumps(metadata)), \
             mock.patch.object(launcher.subprocess, 'run') as child, \
             contextlib.redirect_stdout(io.StringIO()):
            if isinstance(response, BaseException) or callable(response):
                child.side_effect = response
            else:
                child.return_value = response
            code = launcher.main()
        return code, json.loads((self.output / 'report.json').read_text()), child

    @staticmethod
    def completed(code=0, result=None):
        payload = result if result is not None else {
            'status': 'pass', 'checks': [{'label': 'synthetic check', 'status': 'pass'}]}
        return subprocess.CompletedProcess([], code, 'QA_EDGE_REPORT=' + json.dumps(payload) + '\n', '')

    def test_missing_runtime_preserves_failure_report(self):
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch.object(launcher.shutil, 'which', return_value=None):
            code, report, child = self.run_launcher()
        self.assertEqual(code, 1)
        self.assertIn('Deno unavailable', report['error'])
        self.assertTrue(report['source_inputs_unchanged'])
        child.assert_not_called()

    def test_wrong_pin_does_not_execute_handlers(self):
        code, report, child = self.run_launcher(info={'denoVersion': '2.5.7'})
        self.assertEqual(code, 1)
        self.assertIn('exactly match', report['error'])
        child.assert_not_called()

    def test_timeout_retains_complete_progress_and_truncated_tail(self):
        partial = b'QA_EDGE_PROGRESS={"label":"first","status":"pass"}\nQA_EDGE_PROGRESS={"label":'
        code, report, _ = self.run_launcher(subprocess.TimeoutExpired([], 60, output=partial, stderr=b'partial error'))
        self.assertEqual(code, 1)
        self.assertEqual(len(report['partial_progress']), 1)
        self.assertTrue(report['partial_progress_truncated'])
        self.assertEqual((self.output / 'stdout.log').read_bytes(), partial)
        self.assertEqual((self.output / 'stderr.log').read_text(), 'partial error')

    def test_successful_exit_without_completed_report_is_failure(self):
        code, report, _ = self.run_launcher(subprocess.CompletedProcess([], 0, 'QA_EDGE_CLOSING={}\n', ''))
        self.assertEqual(code, 1)
        self.assertIn('Exactly one', report['error'])

    def test_nonzero_exit_cannot_pass_using_success_payload(self):
        code, report, _ = self.run_launcher(self.completed(3))
        self.assertEqual(code, 1)
        self.assertEqual(report['exit_code'], 3)
        self.assertEqual(report['status'], 'fail')

    def test_empty_or_malformed_checks_cannot_pass(self):
        for index, result in enumerate([{'status': 'pass', 'checks': []}, [],
                                        {'status': 'pass', 'checks': [None]}]):
            with self.subTest(result=result), mock.patch.object(
                    launcher.sys, 'argv', ['launcher', str(self.output.with_name(f'empty-{index}'))]):
                with mock.patch.object(launcher.subprocess, 'check_output', return_value=json.dumps(
                        {'denoVersion': '2.5.6', 'denoDir': str(self.root)})), \
                     mock.patch.object(launcher.subprocess, 'run', return_value=self.completed(result=result)), \
                     contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(launcher.main(), 1)

    def test_changed_or_deleted_source_invalidates_completed_run(self):
        source = self.root / 'supabase/functions/example/index.ts'

        def remove_source(*_args, **_kwargs):
            source.unlink()
            return self.completed()

        code, report, _ = self.run_launcher(remove_source)
        self.assertEqual(code, 1)
        self.assertFalse(report['source_inputs_unchanged'])
        self.assertIn('source_verification_error', report)
        self.assertTrue((self.output / 'source-snapshots/supabase/functions/example/index.ts').is_file())

    def test_child_is_loopback_only_and_does_not_inherit_credentials(self):
        code, report, child = self.run_launcher()
        self.assertEqual(code, 0)
        self.assertEqual(report['status'], 'pass')
        command = child.call_args.args[0]
        self.assertIn('--allow-net=127.0.0.1', command)
        self.assertIn('--cached-only', command)
        self.assertIn('--no-prompt', command)
        self.assertTrue(any(flag.startswith('--deny-net=graph.facebook.com') for flag in command))
        self.assertNotIn('SUPABASE_SERVICE_ROLE_KEY', child.call_args.kwargs['env'])
        self.assertFalse(report['final_acceptance'])

    def test_existing_or_external_output_is_rejected_before_execution(self):
        self.output.mkdir(parents=True)
        for candidate in [self.output, self.root / 'outside-cache']:
            with self.subTest(path=candidate), mock.patch.object(launcher.sys, 'argv', ['launcher', str(candidate)]), \
                 mock.patch.object(launcher.subprocess, 'run') as child, self.assertRaises(SystemExit):
                launcher.main()
            child.assert_not_called()


if __name__ == '__main__':
    unittest.main()
