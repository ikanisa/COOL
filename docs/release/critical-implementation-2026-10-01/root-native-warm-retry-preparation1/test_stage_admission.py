"""Admission failures must refuse before creating controls or launching a stage."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / 'run_stage.py'
EXPECTED = '719ca823862eae447b7b3a297ee0357b1fff4d6deb19a9c3595b7b420ddb1782'
raw = SCRIPT.read_bytes()
assert hashlib.sha256(raw).hexdigest() == EXPECTED
M = types.ModuleType('warm_admission_under_test')
M.__file__ = str(SCRIPT)
exec(compile(raw, str(SCRIPT), 'exec'), M.__dict__)
CONFIG = json.loads((M.PREP / 'proposed-commands.json').read_bytes())


class AdmissionTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='collect-warm-admission-')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.stage = 'app-export'
        self.review = {'stage': self.stage, 'script_sha256': EXPECTED,
            'source_fence_sha256': 'a' * 64, 'predecessor_terminal_sha256': 'b' * 64,
            'export_binding_sha256': None, 'production_release_approval': False}
        self.prior = {'stage': 'startup', 'stage_pass': True}
        self.config = copy.deepcopy(CONFIG)
        self.binding = {'source_fence_sha256': 'a' * 64, 'production_release_approval': False}

    def document(self, path, expected):
        if path.name.endswith('-review.json'): return self.review
        if path.name == 'readback.json':
            return {'actual_sdk_source_diagnostic_pass': True, 'stages': {'native': {'stage_pass': False}}}
        if path.name == 'proposed-commands.json': return self.config
        if path.name == 'terminal.json': return self.prior
        if path.name == 'export-source-binding.json': return self.binding
        raise AssertionError('unexpected admission read')

    def refused_before_controls(self, error):
        with mock.patch.object(M, 'BASE', self.base), mock.patch.object(M, 'pinned_json', self.document), \
             mock.patch.object(M, 'packet'), mock.patch.object(M.controller, 'packet'), \
             mock.patch.object(M.controller, 'run_process') as process, \
             mock.patch.object(M.controller, 'protected_metadata') as protected, \
             mock.patch.object(sys, 'argv', ['run_stage.py', '--stage', self.stage, '--review-sha256', 'c' * 64]):
            with self.assertRaisesRegex(ValueError, error): M.main()
            process.assert_not_called()
            protected.assert_not_called()
        self.assertFalse((self.base / '.control').exists())

    def test_coherent_pinned_other_executable_does_not_authorize_actual_runtime(self):
        candidate = Path('/usr/bin/true')
        self.config['Python_executable'] = str(candidate)
        self.config['Python_SHA256'] = M.reader.stable_read(candidate)[0]['sha256']
        self.refused_before_controls('actual Python runtime differs')

    def test_failed_whole_predecessor_cannot_create_next_stage(self):
        self.prior['stage_pass'] = False
        self.refused_before_controls('whole predecessor did not pass')

    def test_wrong_retry_identity_refuses_even_with_whole_pass(self):
        self.stage = 'app-lock'; self.review['stage'] = self.stage
        self.prior = {'stage': 'app-export', 'stage_pass': True, 'warm_retry_script_sha256': 'd' * 64}
        self.refused_before_controls('different retry')

    def test_different_export_fence_refuses_before_app_reader(self):
        self.stage = 'app-lock'; self.review['stage'] = self.stage
        self.prior = {'stage': 'app-export', 'stage_pass': True, 'warm_retry_script_sha256': EXPECTED}
        self.binding['source_fence_sha256'] = 'e' * 64
        self.refused_before_controls('fresh strict export binding differs')

    def test_production_approval_or_extra_review_fields_refuse(self):
        self.review['production_release_approval'] = True
        self.refused_before_controls('separate root stage review differs')
        self.review['production_release_approval'] = False
        self.review['unexpected'] = True
        self.refused_before_controls('separate root stage review differs')

    def test_inprocess_validation_uses_captured_modules_and_refuses_residue(self):
        with mock.patch.object(M.controller, 'load', side_effect=AssertionError('unexpected path reload')):
            self.assertEqual(M.controller.sha(SCRIPT), EXPECTED)
            self.assertIs(M.controller.reader(), M.reader)
            self.assertIs(M.guards.load_metadata(), M.reader)
            self.assertIs(M.fence.metadata(), M.reader)
            with self.assertRaisesRegex(ValueError, 'genuine terminal stage failure'):
                M.controller.require_pass({'exit_code': 0, 'owned_process_group_absent': False})


if __name__ == '__main__':
    unittest.main(verbosity=2)
