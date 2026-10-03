#!/usr/bin/env python3
"""Admission fixtures only; no real APP/control/SDK reads or native execution."""
import contextlib
import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value


C = module(HERE / 'run_native_consumer.py', 'native_admission_controller')
F = module(HERE / 'source_fence.py', 'native_config_contract')


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


class NativeAdmissionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='collect-native-admission-', dir='/private/tmp')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.auth = self.root / 'auth'; self.auth.mkdir()
        self.base = self.root / 'base'; self.app = self.base / 'app-source'; self.app.mkdir(parents=True)
        self.lock_terminal = self.base / '.control/app-lock/terminal.json'
        self.export_terminal = self.base / '.control/app-export/terminal.json'
        self.binding_path = self.base / '.control/app-export/export-source-binding.json'
        self.fence = self.auth / 'source-fence.json'; self.fence.write_text('{}\n')
        for path in (self.lock_terminal, self.export_terminal): path.parent.mkdir(parents=True, exist_ok=True)
        self.write(self.binding_path, dict(kind='actual_strict_unapproved_export_binding', export_stage_actual_pass=True,
            source_root=str(self.app), production_release_approval=False, export_manifest_file_sha256='b'*64,
            root_pinned_source_fence_sha256=sha(self.fence),
            source_manifest_sha256='c'*64, original_app_lock_sha256='d'*64))
        self.lock = dict(stage='app-lock', stage_pass=True, prepared_manifest_sha256=C.GUARD2_MANIFEST)
        self.export = dict(stage='app-export', stage_pass=True, prepared_manifest_sha256=C.GUARD2_MANIFEST,
            actual_export_binding_sha256=sha(self.binding_path))
        self.document = dict(errors=[], packet_manifest_sha256='a'*64, checked_packet_leaves=1,
            execution_stage_admissions={stage:stage=='native' for stage in C.STAGES},
            required_guard2_preparation_manifest_sha256=C.GUARD2_MANIFEST,
            required_reviewed_guard_sha256=C.GUARD2_SHA256,
            current_source_export_authorized=True, strict_current_source_comparison_required=True,
            private_snapshot_exclusive=True, source_scope_held_for_strict_export=False,
            source_lock_attested=False, transient_write_and_restore_absence_attested=False,
            required_source_fence_sha256=sha(self.fence), required_app_export_binding_sha256=sha(self.binding_path))
        self.receipt = self.auth / 'native-admission.json'
        self.guard2_packet = json.loads((C.GUARD2 / 'packet-files.json').read_text())
        def packet(directory, expected):
            if directory == C.GUARD2:
                self.assertEqual(expected, C.GUARD2_MANIFEST); return self.guard2_packet
            return {'files':{'fixture':'a'*64}}
        for name, value in [('BASE', self.base), ('APP', self.app), ('AUTH_DIR', self.auth),
                            ('SOURCE_FENCE', self.fence), ('packet', packet)]:
            patch = mock.patch.object(C, name, value); patch.start(); self.addCleanup(patch.stop)

    @staticmethod
    def write(path, value): path.write_text(json.dumps(value, sort_keys=True)+'\n')

    def args(self):
        self.write(self.lock_terminal, self.lock); self.write(self.export_terminal, self.export)
        self.document['required_predecessor_terminal_sha256'] = sha(self.lock_terminal)
        self.document['required_app_export_terminal_sha256'] = sha(self.export_terminal)
        self.write(self.receipt, self.document)
        return type('Args', (), dict(stage='native', foundation_child=False,
            prepared_manifest_sha256='a'*64, root_review_sha256=sha(self.receipt)))()

    def test_only_genuine_guard2_whole_pass_and_fresh_export_fixture_admits(self):
        self.assertEqual(C.authorization(self.args())['files'], {'fixture':'a'*64})
    def test_failed_app_lock_predecessor_refused(self):
        self.lock['stage_pass'] = False
        with self.assertRaisesRegex(ValueError, 'actual predecessor terminal'): C.authorization(self.args())
    def test_foreign_or_old_app_lock_predecessor_refused(self):
        for value in ('f'*64, None):
            self.lock['prepared_manifest_sha256'] = value
            with self.assertRaisesRegex(ValueError, 'whole app-lock PASS from exact preparation2'): C.authorization(self.args())
    def test_multiple_stage_receipt_refused(self):
        self.document['execution_stage_admissions']['app-lock'] = True
        with self.assertRaisesRegex(ValueError, 'not separately authorized'): C.authorization(self.args())
    def test_old_foreign_export_binding_producer_refused(self):
        self.export['prepared_manifest_sha256'] = 'f'*64
        with self.assertRaisesRegex(ValueError, 'fresh whole preparation2 export'): C.authorization(self.args())
    def test_export_binding_foreign_source_fence_refused(self):
        value=json.loads(self.binding_path.read_text());value['root_pinned_source_fence_sha256']='f'*64
        self.write(self.binding_path,value)
        self.export['actual_export_binding_sha256']=sha(self.binding_path)
        self.document['required_app_export_binding_sha256']=sha(self.binding_path)
        with self.assertRaisesRegex(ValueError,'strict app export binding malformed'):C.authorization(self.args())
    def test_other_stage_and_foundation_child_refused_before_packet_reads(self):
        with mock.patch.object(C, 'packet', side_effect=AssertionError('packet must not be read')):
            for stage, child in (('app-export',False), ('app-lock',False), ('native',True)):
                with self.assertRaisesRegex(ValueError, 'only native'): C.authorization(type('Args',(),dict(stage=stage,foundation_child=child))())
    def test_parser_only_native_and_original_full_native_contract_unchanged(self):
        with mock.patch.object(C.sys, 'argv', ['controller','--stage','app-lock']), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error: C.main()
            self.assertEqual(error.exception.code, 2)
        config = json.loads((HERE / 'proposed-commands.json').read_text())
        # Restore actual configured root names for the contract check; no directory is read there.
        F.validate_commands(config, C.HERE, HERE, C.REPO,
            Path(config['base']), Path(config['SDK']), Path(config['app']),
            Path(config['immutable_root_stage_admission_directory']))
        original = json.loads((C.HERE / 'proposed-commands.json').read_text())
        self.assertEqual(config['commands'], original['commands'])
        self.assertEqual(config['environment_exact'], original['environment_exact'])
        self.assertEqual(config['commands']['native']['deadline_seconds'], 2700)


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(NativeAdmissionTests))
    value = {'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),
             'skips':len(result.skipped),'fixture_parent':'/private/tmp',
             'guard2_test42_and_original31_proofs_reused':True,
             'real_APP_control_SDK_reads_or_writes':False,'actual_native_execution':False}
    with (HERE / 'tests-result.json').open('x') as output:
        json.dump(value, output, indent=2, sort_keys=True); output.write('\n')
    raise SystemExit(0 if result.wasSuccessful() and result.testsRun==8 and not result.skipped else 1)
