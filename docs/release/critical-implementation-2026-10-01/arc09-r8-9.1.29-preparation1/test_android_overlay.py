#!/usr/bin/env python3
"""Pure proposed-overlay fixtures; actual APP/SDK/process actions are forbidden."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
PREVIOUS = HERE.parent / 'arc09-aab-driver-preparation1/argv-unavailable-recovery3'

def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value

OVERLAY = loaded(HERE / 'driver/android_build_overlay.py', 'private_overlay_fixture')
DRIVER = loaded(HERE / 'driver/run_selected_aab.py', 'private_derivative_fixture')
FROZEN = json.loads((PREVIOUS / 'captured-fixture.json').read_text())
DELTA = json.loads((HERE / 'source-binding-delta.json').read_text())
PLAN = json.loads((HERE / 'reviewed-verification-plan.json').read_text())
ORIGINAL_PINS = json.loads((PREVIOUS / 'prepared-input-pins.json').read_text())
CURRENT_PINS = json.loads((HERE / 'driver/prepared-input-pins.json').read_text())


def manifest(files):
    return {'kind': 'unapproved_collect_source_export', 'retain_source_drift': False,
            'capture_classification': 'strict_unapproved_source_export',
            'approvals': {name: False for name in ('trusted_source_verified', 'reviewed', 'frozen',
                'owner_approved', 'signed', 'production_release_accepted')},
            'source_files': files, 'file_count': len(files),
            'source_manifest_sha256': hashlib.sha256(OVERLAY.canonical(files)).hexdigest()}


class OverlayFixtures(unittest.TestCase):
    def setUp(self):
        for block in [patch.object(DRIVER.subprocess, 'Popen', side_effect=AssertionError('real process forbidden')),
                      patch.object(DRIVER.os, 'kill', side_effect=AssertionError('real signal/probe forbidden')),
                      patch.object(DRIVER.os, 'killpg', side_effect=AssertionError('real signal/probe forbidden'))]:
            block.start(); self.addCleanup(block.stop)
        self.actual = copy.deepcopy(FROZEN['native_APP_source'])
        self.export = copy.deepcopy(FROZEN['export'])
        self.archived = manifest(OVERLAY.source_rows(self.actual['source_files_exact']))
        files = copy.deepcopy(self.archived['source_files'])
        for name, row in DELTA['three_file_changes'].items(): files[name] = row['proposed_after']
        self.proposed_current = manifest(files)  # Proposed fixture, never an observed current APP claim.

    def validate(self):
        return OVERLAY.validate_manifest_overlay(self.archived, self.proposed_current,
                                                 self.actual, self.export, DELTA)

    def rewrite_current(self):
        self.proposed_current = manifest(self.proposed_current['source_files'])

    def test_actual_archived_native_source_and_exact_proposed_two_rows(self):
        row = self.validate()
        self.assertEqual(row['source_file_count'], 2561)
        self.assertEqual(row['unchanged_source_rows'], 2558)
        self.assertFalse(row['old_whole_APP_unchanged_claimed_for_current_source'])
        self.assertFalse(row['current_native_JVM_execution_claimed'])
        self.assertTrue(row['archived_native_XML_classes_and_unchanged_source_scoped_reuse'])
        self.assertEqual(self.archived['source_manifest_sha256'], self.export['source_manifest_sha256'])
        self.assertEqual(self.proposed_current['source_manifest_sha256'], DELTA['hypothetical_source_manifest_sha256_if_only_these_three_changes'])

    def test_third_authored_source_change_is_refused(self):
        name = next(n for n in self.proposed_current['source_files'] if n not in OVERLAY.EXPECTED_FILES)
        self.proposed_current['source_files'][name]['sha256'] = '0' * 64
        self.rewrite_current()
        with self.assertRaises(ValueError): self.validate()

    def test_one_missing_overlay_change_is_refused(self):
        name = 'android/build.gradle.kts'
        self.proposed_current['source_files'][name] = self.archived['source_files'][name]
        self.rewrite_current()
        with self.assertRaises(ValueError): self.validate()

    def test_archived_native_source_binding_cannot_be_rewritten(self):
        self.actual['source_files_exact']['android/build.gradle.kts']['sha256'] = '0' * 64
        with self.assertRaises(ValueError): self.validate()

    def test_archived_export8_source_binding_cannot_be_replaced(self):
        self.export['source_manifest_sha256'] = self.proposed_current['source_manifest_sha256']
        with self.assertRaises(ValueError): self.validate()

    def test_current_source_member_removal_is_refused(self):
        self.proposed_current['source_files'].pop('android/build.gradle.kts')
        self.rewrite_current()
        with self.assertRaises(ValueError): self.validate()

    def test_claimed_current_manifest_approval_is_refused(self):
        self.proposed_current['approvals']['owner_approved'] = True
        with self.assertRaises(ValueError): self.validate()

    def test_exact_existing42_pin_amendment_is_accepted(self):
        OVERLAY.validate_pin_delta(ORIGINAL_PINS, CURRENT_PINS, DRIVER.ROOT, DELTA)
        self.assertEqual(len(CURRENT_PINS), 42)

    def test_adding_a43rd_pin_instead_of_declared_overlay_is_refused(self):
        changed = dict(CURRENT_PINS)
        changed[str(DRIVER.ROOT / 'android/build.gradle.kts')] = DELTA['three_file_changes']['android/build.gradle.kts']['proposed_after']
        with self.assertRaises(ValueError): OVERLAY.validate_pin_delta(ORIGINAL_PINS, changed, DRIVER.ROOT, DELTA)

    def test_unrelated_prepared_pin_change_is_refused(self):
        changed = copy.deepcopy(CURRENT_PINS); changed['/bin/ps']['sha256'] = '0' * 64
        with self.assertRaises(ValueError): OVERLAY.validate_pin_delta(ORIGINAL_PINS, changed, DRIVER.ROOT, DELTA)

    def test_stale_affected_pin_is_refused(self):
        with self.assertRaises(ValueError): OVERLAY.validate_pin_delta(ORIGINAL_PINS, ORIGINAL_PINS, DRIVER.ROOT, DELTA)

    def test_current_APP_guard_uses_current_hash_and_keeps_archived_export(self):
        current_hash = '1' * 64; old_hash = self.export['export_manifest_file_sha256']
        calls = []
        ctx = types.SimpleNamespace(pins={str(DRIVER.ORIGINAL / 'verify_native_consumer_source.py'): {'sha256':'0'*64}},
            current_app_export={'current_APP_manifest_pin': {'sha256':current_hash}}, export=self.export,
            guards=types.SimpleNamespace(app_readback=lambda phase, expected: calls.append((phase, expected)) or {'fixture':True}),
            controller=types.SimpleNamespace(protected_metadata=lambda: {'fixture':True}))
        captured = {}
        with patch.object(DRIVER, 'module', return_value=types.SimpleNamespace(verify=lambda phase: {'fixture':True})), \
                patch.object(DRIVER, 'save', side_effect=lambda path, value: captured.update({str(path):value})):
            DRIVER.guard_phase(ctx, HERE, 'failure')
        self.assertEqual(calls, [('built', current_hash)])
        self.assertEqual(ctx.export['export_manifest_file_sha256'], old_hash)
        self.assertTrue(captured[str(HERE/'failure-diagnostic-summary.json')]['APP-source']['readback_completed'])

    def test_changed_main_consumers_use_current_fence_and_fresh_graphs(self):
        calls = []; row = self.validate()
        current_fence = {'path':str(HERE/'synthetic-current-fence.json'),'sha256':'2'*64}
        row.update(current_APP_manifest_pin={'sha256':'1'*64},current_repository_source_fence_pin=current_fence)
        matrix = copy.deepcopy(FROZEN['matrix'])
        readback = {'label':'production-default-proguard-readback','argv':PLAN['argv'],
                    'cwd':PLAN['cwd'],'deadline_seconds':300}
        matrix['commands'].append(readback)
        actual_rule = {'sha256':'3'*64,'bytes':10}
        proguard = {'kind':'collect_default_proguard_directory_readback',
            'app_build_directory':str(DRIVER.BASE/'native-build/app'),
            'configured_app_build_directory':str(DRIVER.BASE/'native-build/app'),
            'default_proguard_file':str(DRIVER.BASE/'native-build/app/intermediates/default_proguard_files/global/rules'),
            'release_default_proguard_paths':[str(DRIVER.BASE/'native-build/app/intermediates/default_proguard_files/global/rules')],
            'producer_task':':app:extractProguardFiles','minify_enabled':True,'shrink_resources':True,
            'default_paths_and_producer_verified':True,'r8_execution_verified':False,'package_or_release_acceptance':False,
            'actual_default_file_sha256':actual_rule['sha256'],'actual_default_file_bytes':actual_rule['bytes'], 'actual_R8_compiler_readback':{'fixture':True}}
        class Tracker:
            def __init__(self,*args):pass
            def private_identity(self,row):return None
            def finish(self):return {'owned_daemons_absent':True,'fixture':True}
        def run_process(output,label,argv,seconds,cwd,env):
            calls.append((label,argv,seconds))
            if label == 'production-release-aab': raise RuntimeError('fixture stop before real artifact work')
            text = ''
            if label == readback['label']: text='COLLECT_DEFAULT_PROGUARD_READBACK='+json.dumps(proguard)+'\n'
            if label in ('production-runtime-graph-observation','production-compile-graph-observation'):
                cfg = 'productionRelease'+('Runtime' if 'runtime' in label else 'Compile')+'Classpath'
                text='COLLECT_RUNTIME_GRAPH_BEGIN\n'+json.dumps({'configuration':cfg,'components':[],'edges':[],'artifacts':[]})+'\nCOLLECT_RUNTIME_GRAPH_END\n'
            (output/(label+'.stdout')).write_text(text);(output/(label+'.stderr')).write_text('')
            return {'exit_code':0,'fixture':True}
        with tempfile.TemporaryDirectory(prefix='arc09-pure-consumer-',dir=HERE) as temporary:
            tmp=Path(temporary)
            admission=json.loads((HERE/'root-admission-template.json').read_text());admission['output']=str(tmp/'arc09-fixture-output')
            ctx=types.SimpleNamespace(admission=admission,current_app_export=row,matrix=matrix,
                config=FROZEN['config'],export=self.export,readback_command=readback,overlay=OVERLAY,
                controller=types.SimpleNamespace(subprocess=DRIVER.subprocess,run_process=run_process),
                reader=types.SimpleNamespace(stable_read=lambda path: (actual_rule,b'')),
                guards=types.SimpleNamespace(process_success=lambda record:None,forbid_upgrade_branch=lambda *args:None))
            with patch.object(OVERLAY,'validate_r8_readback',return_value={'fixture':True}), patch.object(OVERLAY,'_R8_EXPECTED',{'fixture':True}), patch.object(DRIVER,'RELEASE',tmp),patch.object(DRIVER,'context',return_value=ctx), \
                    patch.object(DRIVER,'process_table',return_value={}),patch.object(DRIVER,'group_absent',return_value=True), \
                    patch.object(DRIVER,'DaemonTracker',Tracker),patch.object(DRIVER,'reuse_runtime_graph',side_effect=AssertionError('old graphs must not be reused')), \
                    patch.object(DRIVER.sys,'argv',['runner','--admission',str(HERE/'root-admission-template.json'),'--admission-sha256','0'*64]):
                with self.assertRaisesRegex(RuntimeError,'fixture stop'): DRIVER.main()
            self.assertTrue((tmp/'arc09-fixture-output/production-runtime-graph.json').is_file())
            self.assertTrue((tmp/'arc09-fixture-output/production-compile-graph.json').is_file())
        labels=[call[0] for call in calls]
        self.assertEqual(labels[:6],['source-fence-before-command','combined-guard-before-command',readback['label'],
                                    'production-runtime-graph-observation','production-compile-graph-observation','production-release-aab'])
        fence=calls[0][1]
        self.assertEqual(fence[fence.index('--binding')+1],current_fence['path'])
        self.assertEqual(fence[fence.index('--binding-sha256')+1],current_fence['sha256'])
        self.assertEqual(calls[2][2],300);self.assertEqual(calls[5][2],2700)
        self.assertNotIn('native',labels)


if __name__ == '__main__': unittest.main(verbosity=2)
