#!/usr/bin/env python3
"""Failure-boundary tests for the native public-defaults export wrapper."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'cloudflare/export_public_configuration.py'
SPEC = importlib.util.spec_from_file_location('collect_public_defaults_export', SCRIPT)
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)


def document():
    return {'schema_version': 1, 'kind': 'collect_mobile_public_configuration_defaults',
            'source_inputs': {path: {'sha256': 'a'*64, 'bytes': 1} for path in TOOL.SOURCES},
            'values': {key: [] if key == 'list_account_request_reasons' else {} for key in TOOL.VALUE_KEYS}}


def events(payload=None):
    raw = json.dumps(document(), separators=(',', ':')).encode() if payload is None else payload
    return [
        {'type':'start','protocolVersion':'0.1.1'},
        {'type':'testStart','test':{'id':1,'name':'loading producer','metadata':{'skip':False}}},
        {'type':'testDone','testID':1,'result':'success','skipped':False,'hidden':True},
        {'type':'testStart','test':{'id':3,'name':'actual producer','metadata':{'skip':False}}},
        {'type':'print','testID':3,'messageType':'print','message':TOOL.MARKER+base64.b64encode(raw).decode()},
        {'type':'testDone','testID':3,'result':'success','skipped':False,'hidden':False},
        {'type':'done','success':True},
    ]


def encoded(value):
    return b'\n'.join(json.dumps(row).encode() for row in value)+b'\n'


class PayloadAdmission(unittest.TestCase):
    def test_success_preserves_exact_payload_and_excludes_loader(self):
        payload = (json.dumps(document(), ensure_ascii=False, indent=2)+'\n').encode()
        actual, value, counts = TOOL.parse_machine_log(encoded(events(payload)), 0)
        self.assertEqual(actual, payload)
        self.assertEqual(value, document())
        self.assertEqual(counts, {'actual_producer_tests':1,'hidden_loaders_excluded':1,
                                  'payload_frames':1,'skipped':0,'failed':0,
                                  'flutter_process_start_frames':0})

    def test_actual_flutter_process_start_is_not_a_test_or_payload(self):
        value = events()
        value.insert(2, [{'event':'test.startedProcess','params':{'vmServiceUri':None}}])
        payload, actual, counts = TOOL.parse_machine_log(encoded(value), 0)
        self.assertEqual(actual, document())
        self.assertEqual(json.loads(payload), document())
        self.assertEqual(counts, {'actual_producer_tests':1,'hidden_loaders_excluded':1,
                                  'payload_frames':1,'skipped':0,'failed':0,
                                  'flutter_process_start_frames':1})

    def test_process_start_arrays_cannot_hide_results_errors_or_extra_events(self):
        startup = [{'event':'test.startedProcess','params':{'vmServiceUri':None}}]
        cases = []
        for frame in [[], startup*2, [{'type':'error','error':'hidden'}],
                      [{'event':'test.startedProcess','params':{'vmServiceUri':'unqualified'}}],
                      [{'event':'test.startedProcess','params':{'vmServiceUri':None,'extra':True}}]]:
            value = events(); value.insert(2, frame); cases.append(value)
        value = events(); value.insert(2, startup); value.insert(3, startup); cases.append(value)
        value = events(); value.insert(0, startup); cases.append(value)
        value = events(); value.insert(4, startup); cases.append(value)
        value = events(); value.append(startup); cases.append(value)
        for index, value in enumerate(cases):
            with self.subTest(case=index), self.assertRaisesRegex(ValueError, 'process-start frame'):
                TOOL.parse_machine_log(encoded(value), 0)

    def test_process_failure_cannot_be_relabelled_by_successful_events(self):
        with self.assertRaisesRegex(ValueError, 'process failed'):
            TOOL.parse_machine_log(encoded(events()), 1)

    def test_failed_missing_or_nonfinal_overall_result(self):
        cases = []
        value = events(); value[-1]['success'] = False; cases.append(value)
        cases.append(events()[:-1])
        value = events(); value.append({'type':'print','message':'late'}); cases.append(value)
        value = events(); value.append({'type':'done','success':True}); cases.append(value)
        for value in cases:
            with self.subTest(value=value[-1]):
                with self.assertRaisesRegex(ValueError, 'final Flutter result'):
                    TOOL.parse_machine_log(encoded(value), 0)

    def test_failed_skipped_unmatched_duplicate_and_unfinished_tests(self):
        cases = []
        value = events(); value[-2]['result'] = 'failure'; cases.append(value)
        value = events(); value[-2]['skipped'] = True; cases.append(value)
        value = events(); value[3]['test']['metadata']['skip'] = True; cases.append(value)
        value = events(); value[-2]['testID'] = 9; cases.append(value)
        value = events(); value.insert(-1, value[-2].copy()); cases.append(value)
        value = events(); del value[-2]; cases.append(value)
        value = events(); value.insert(-1, {'type':'error','error':'fixture failure'}); cases.append(value)
        for index, value in enumerate(cases):
            with self.subTest(case=index), self.assertRaises(ValueError):
                TOOL.parse_machine_log(encoded(value), 0)

    def test_missing_duplicate_malformed_or_loader_owned_frame(self):
        cases = []
        value = events(); del value[4]; cases.append(value)
        value = events(); value.insert(5,value[4].copy()); cases.append(value)
        value = events(); value[4]['message'] = 'prefix '+value[4]['message']; cases.append(value)
        value = events(); value[4]['messageType'] = 'debug'; cases.append(value)
        value = events(); value[4]['testID'] = 1; cases.append(value)
        for index, value in enumerate(cases):
            with self.subTest(case=index), self.assertRaises(ValueError):
                TOOL.parse_machine_log(encoded(value), 0)

    def test_base64_utf8_duplicate_json_and_nonfinite_rejected(self):
        cases = [b'\xff', b'{"kind":1,"kind":2}', b'{"number":NaN}', b'{}\n{}']
        for raw in cases:
            with self.subTest(payload=raw), self.assertRaises((ValueError,UnicodeError)):
                TOOL.parse_machine_log(encoded(events(raw)), 0)
        value = events(); value[4]['message'] = TOOL.MARKER+'!not-base64'
        with self.assertRaisesRegex(ValueError, 'base64'):
            TOOL.parse_machine_log(encoded(value), 0)

    def test_wrong_export_scope_and_source_claims_rejected(self):
        cases = []
        value = document(); value['schema_version'] = True; cases.append(value)
        value = document(); value['source_inputs']['../outside'] = {'bytes':1,'sha256':'a'*64}; cases.append(value)
        value = document(); value['values']['extra_rpc'] = {}; cases.append(value)
        value = document(); value['source_inputs'][next(iter(TOOL.SOURCES))]['bytes'] = True; cases.append(value)
        value = document(); value['source_inputs'][next(iter(TOOL.SOURCES))]['sha256'] = 'no'; cases.append(value)
        for index, value in enumerate(cases):
            with self.subTest(case=index), self.assertRaises(ValueError):
                TOOL.parse_machine_log(encoded(events(json.dumps(value).encode())), 0)

    def test_bounded_stream_and_payload(self):
        with self.assertRaisesRegex(ValueError, 'log exceeds'):
            TOOL.parse_machine_log(b' '*(TOOL.MAX_LOG+1), 0)
        with self.assertRaisesRegex(ValueError, '(frame|payload) exceeds'):
            TOOL.parse_machine_log(encoded(events(b' '*(TOOL.MAX_PAYLOAD+1))), 0)


class SourceAndOutputBoundaries(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def sources(self, root):
        for role in TOOL.SOURCES | {TOOL.PRODUCER,'.fvmrc'}:
            path = root/role
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{"flutter":"3.44.4"}' if role == '.fvmrc' else 'public fixture source\n')

    def package_map(self, root, change=None):
        (root/'lib').mkdir(exist_ok=True)
        value = {'configVersion':2,'packages':[
            {'name':'collect_app','rootUri':'../','packageUri':'lib/','languageVersion':'3.12'}]}
        if change:
            change(value)
        path = root/'.dart_tool/package_config.json'
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps(value))
        return path

    def test_package_map_binds_the_exact_physical_execution_sources(self):
        root = self.root/'execution'; self.sources(root)
        path = self.package_map(root)
        value = TOOL.package_config_snapshot(root)
        self.assertEqual(value['path'], str(path))
        self.assertEqual(value['root'], str(root))
        self.assertEqual(value['package_uri'], 'lib/')
        self.assertEqual(value['sha256'], TOOL.describe(path.read_bytes())['sha256'])

    def test_wrong_ambiguous_nonlocal_or_aliased_package_maps_are_refused(self):
        root = self.root/'execution'; self.sources(root)
        changes = [lambda x:x.update(configVersion=True),
                   lambda x:x.update(configVersion=1),
                   lambda x:x['packages'].append(x['packages'][0].copy()),
                   lambda x:x['packages'][0].update(name='different_app'),
                   lambda x:x['packages'][0].update(rootUri='https://example.invalid/'),
                   lambda x:x['packages'][0].update(rootUri='../../'),
                   lambda x:x['packages'][0].update(packageUri='../lib/')]
        for change in changes:
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.package_map(root, change)
                TOOL.package_config_snapshot(root)
        path = self.package_map(root)
        path.rename(path.with_name('retained.json'))
        path.symlink_to(path.with_name('retained.json'))
        with self.assertRaisesRegex(ValueError, 'Physical path required'):
            TOOL.package_config_snapshot(root)

    def test_hardlinked_package_map_is_refused(self):
        root = self.root/'execution'; self.sources(root)
        path = self.package_map(root)
        os.link(path, path.with_name('alias.json'))
        with self.assertRaisesRegex(ValueError, 'independent'):
            TOOL.package_config_snapshot(root)

    def export_fixture(self, *, mutate_map=False):
        project = self.root/'execution'; custody = self.root/'custody'
        self.sources(project); self.sources(custody)
        package = self.package_map(project)
        launcher = self.root/'flutter'; launcher.write_text('unexecuted test launcher')
        output = self.root/'new-export'
        snapshot = TOOL.source_snapshot(project,custody)
        value = document(); value['source_inputs'] = {key:snapshot[key] for key in TOOL.SOURCES}
        seen = []
        def capture(out, label, argv, working, env, timeout=180):
            seen.append((label,argv,working,env.copy()))
            if label == 'flutter-version':
                raw = b'{"frameworkVersion":"3.44.4"}\n'
            else:
                stream = events(json.dumps(value).encode())
                stream.insert(2,[{'event':'test.startedProcess','params':{'vmServiceUri':None}}])
                raw = encoded(stream)
                if mutate_map:
                    changed = json.loads(package.read_text()); changed['generatorVersion'] = 'changed'
                    package.write_text(json.dumps(changed))
            out.write(label+'.stdout.jsonl',raw)
            out.write(label+'.stderr.txt',b'')
            return 0,0.01
        with patch.object(TOOL,'capture',side_effect=capture):
            result = TOOL.main(['--flutter',str(launcher),'--project-root',str(project),
                                '--custody-root',str(custody),'--out',str(output)])
        return result,seen,json.loads((output/'result.json').read_text()),output,package

    def test_compiler_and_producer_receive_the_same_pinned_map(self):
        code, seen, result, output, package = self.export_fixture()
        self.assertEqual(code,0)
        self.assertTrue(result['all_pass'])
        self.assertEqual(seen[1][1][1], '--packages='+str(package))
        self.assertEqual(seen[1][3]['COLLECT_PUBLIC_DEFAULTS_PACKAGE_CONFIG'], str(package))
        self.assertEqual(seen[1][3]['COLLECT_PUBLIC_DEFAULTS_PACKAGE_CONFIG_SHA256'],
                         TOOL.describe(package.read_bytes())['sha256'])
        self.assertEqual(result['counts']['flutter_process_start_frames'],1)
        self.assertTrue((output/'mobile-defaults.json').is_file())

    def test_package_map_change_during_compilation_cannot_publish_payload(self):
        code, _, result, output, _ = self.export_fixture(mutate_map=True)
        self.assertEqual(code,1)
        self.assertFalse(result['all_pass'])
        self.assertIn('package map changed',result['error'])
        self.assertFalse((output/'mobile-defaults.json').exists())

    def test_source_snapshot_and_changed_consumer(self):
        a = self.root/'execution'; b = self.root/'custody'
        self.sources(a); self.sources(b)
        self.assertEqual(len(TOOL.source_snapshot(a,b)), 12)
        (b/'pubspec.yaml').write_text('changed consumer\n')
        with self.assertRaisesRegex(ValueError, 'differs from custody'):
            TOOL.source_snapshot(a,b)

    def test_symlink_component_and_outside_role_refused(self):
        a = self.root/'execution'; self.sources(a)
        original = a/'pubspec.lock'; original.rename(a/'retained.lock')
        original.symlink_to(a/'retained.lock')
        with self.assertRaisesRegex(ValueError, 'Physical path required'):
            TOOL.source_bytes(a,'pubspec.lock')
        with self.assertRaisesRegex(ValueError, 'Unexpected public source'):
            TOOL.source_bytes(a,'../retained.lock')

    def test_output_is_private_exclusive_and_preserves_existing_bytes(self):
        output = TOOL.PrivateOutput(self.root/'new')
        self.addCleanup(output.close)
        output.write('payload.json', b'first')
        with self.assertRaises(FileExistsError):
            output.write('payload.json', b'replacement')
        self.assertEqual(output.read('payload.json'), b'first')
        self.assertEqual((self.root/'new').stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.root/'new/payload.json').stat().st_mode & 0o777, 0o600)
        with self.assertRaises(FileExistsError):
            TOOL.PrivateOutput(self.root/'new')

    def test_symlinked_output_or_child_cannot_replace_target(self):
        target = self.root/'retained'; target.mkdir()
        alias = self.root/'alias'; alias.symlink_to(target, target_is_directory=True)
        with self.assertRaises(FileExistsError):
            TOOL.PrivateOutput(alias)
        output = TOOL.PrivateOutput(self.root/'new'); self.addCleanup(output.close)
        secret = self.root/'untouched'; secret.write_bytes(b'unchanged')
        (output.path/'payload.json').symlink_to(secret)
        with self.assertRaises(FileExistsError):
            output.write('payload.json', b'replacement')
        self.assertEqual(secret.read_bytes(), b'unchanged')

    def test_held_directory_survives_rename_but_changed_visible_path_is_refused(self):
        output = TOOL.PrivateOutput(self.root/'new'); self.addCleanup(output.close)
        output.path.rename(self.root/'owned-moved')
        output.path.mkdir()
        output.write('retained.txt', b'owned descriptor')
        self.assertTrue((self.root/'owned-moved/retained.txt').exists())
        self.assertFalse((output.path/'retained.txt').exists())
        with self.assertRaisesRegex(ValueError, 'path changed'):
            output.verify()


if __name__ == '__main__':
    unittest.main()
