#!/usr/bin/env python3
"""Private captured-metadata fixtures; real process/APP/SDK actions are forbidden."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import types
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


DRIVER = loaded(HERE / 'run_selected_aab.py', 'private_metadata_driver')
FIXTURE = json.loads((HERE / 'captured-fixture.json').read_text())
GUARDS = loaded(DRIVER.PREP / 'consumer_guards.py', 'private_pure_guards')


class OwnershipFixtures(unittest.TestCase):
    def setUp(self):
        # Any unstubbed subprocess or signal is a test failure, not a live action.
        self.blocks = [patch.object(DRIVER.subprocess, 'Popen', side_effect=AssertionError('real subprocess forbidden')),
                       patch.object(DRIVER.os, 'kill', side_effect=AssertionError('real signal/probe forbidden')),
                       patch.object(DRIVER.os, 'killpg', side_effect=AssertionError('real group signal/probe forbidden'))]
        for block in self.blocks:
            block.start(); self.addCleanup(block.stop)
        self.ctx = types.SimpleNamespace(config=FIXTURE['config'], matrix=FIXTURE['matrix'],
            export=FIXTURE['export'], guards=GUARDS,
            records={'APP_source': FIXTURE['native_APP_source'],
                     'SDK_after': FIXTURE['reuse_data']['SDK_source_failure'],
                     'root_readback': FIXTURE['native_root_readback']})
        self.monitor = DRIVER.DaemonTracker.__new__(DRIVER.DaemonTracker)
        self.monitor.context = self.ctx
        self.monitor.label = 'production-runtime-graph-observation'
        self.monitor.root = 87082
        self.monitor.baseline = {}
        self.monitor.family = {}
        self.monitor.daemons = {}
        self.monitor.unproven = {}
        self.monitor.stop = threading.Event()
        self.monitor.cleanup_deadline = None
        self.monitor.error = None
        actual = FIXTURE['daemon_metadata']
        self.wrapper = copy.deepcopy(actual['observed_ancestry'][0])
        self.before = copy.deepcopy(actual['observed_ancestry'][1])
        self.after = copy.deepcopy(actual['unproven_private_home_daemons'][0])
        self.proof = copy.deepcopy(self.after['private_home_evidence'])
        self.monitor.home_identity = tuple(self.proof['home_identity'])

    def wrapper_read(self, path, expected):
        relative = Path(path).relative_to(DRIVER.APP).as_posix()
        record = self.ctx.records['APP_source']['source_files_exact'][relative]
        self.assertEqual(expected, record['sha256'])
        return b'x' * record['bytes']

    def transition(self, changed=None, proof=None):
        current = copy.deepcopy(self.after)
        if changed: current.update(changed)
        own = copy.deepcopy(self.before)
        with patch.object(self.monitor, 'private_identity', return_value=self.proof if proof is None else proof):
            self.monitor.refresh_session(self.before['pid'], own, current)
        return own

    def test_actual_pinned_jar_wrapper_with_unquoted_java_spaces(self):
        with patch.object(DRIVER, 'plain_read', side_effect=self.wrapper_read):
            self.assertTrue(self.monitor.exact_wrapper_java(self.wrapper['command']))

    def test_wrong_java_rejected(self):
        self.assertFalse(self.monitor.exact_wrapper_java(self.wrapper['command'].replace(self.ctx.config['JDK_java_executable'], '/other/java', 1)))

    def test_wrong_jar_rejected(self):
        self.assertFalse(self.monitor.exact_wrapper_java(self.wrapper['command'].replace('gradle-wrapper.jar', 'other.jar', 1)))

    def test_changed_wrapper_args_rejected(self):
        self.assertFalse(self.monitor.exact_wrapper_java(self.wrapper['command'].replace('--offline', '--online', 1)))

    def test_changed_wrapper_jar_hash_fails(self):
        with patch.object(DRIVER, 'plain_read', side_effect=ValueError('pinned input hash differs')):
            with self.assertRaises(ValueError): self.monitor.exact_wrapper_java(self.wrapper['command'])

    def test_observe_preserves_shell_to_exact_jar_exec_history(self):
        owned = copy.deepcopy(self.wrapper)
        owned['command'] = ' '.join(self.ctx.matrix['commands'][0]['argv'])
        self.monitor.family = {owned['pid']: owned}
        with patch.object(DRIVER, 'process_table', return_value={self.wrapper['pid']: self.wrapper}), \
                patch.object(self.monitor, 'private_identity', return_value=None), \
                patch.object(DRIVER, 'plain_read', side_effect=self.wrapper_read):
            self.monitor.observe(finishing=True)
        history = owned['observed_exec_history']
        self.assertEqual(history[-1]['after'], self.wrapper['command'])
        self.assertEqual(owned['pid'], 87082)
        self.assertEqual(owned['pgid'], 87082)

    def test_actual_inherited_group_to_owned_session_positive(self):
        own = self.transition()
        self.assertEqual(own['pgid'], 87105)
        self.assertEqual(own['observed_session_history'][0]['before_pgid'], 87082)
        self.assertEqual(own['observed_session_history'][0]['after_pgid'], 87105)
        self.assertEqual(own['observed_session_history'][0]['private_home_evidence'], self.proof)

    def test_observe_adopts_actual_session_transition_and_keeps_history(self):
        self.monitor.family = {87082: copy.deepcopy(self.wrapper), 87105: copy.deepcopy(self.before)}
        table = {87082: self.wrapper, 87105: self.after}
        def exact_private_identity(row):
            return self.proof if row['pid'] == 87105 else None
        with patch.object(DRIVER, 'process_table', return_value=table), \
                patch.object(self.monitor, 'private_identity', side_effect=exact_private_identity):
            self.monitor.observe(finishing=True)
        adopted = self.monitor.daemons[87105]
        self.assertEqual(adopted['pgid'], 87105)
        self.assertEqual(adopted['observed_session_history'][0]['before_pgid'], 87082)
        self.assertEqual(adopted['private_home_evidence'], self.proof)
        self.assertEqual(self.monitor.unproven, {})
        self.assertIsNone(self.monitor.error)

    def test_changed_pid_rejected(self):
        with self.assertRaises(ValueError): self.transition({'pid': 99999})

    def test_reused_pid_start_rejected(self):
        with self.assertRaises(ValueError): self.transition({'start': 'different process start'})

    def test_changed_daemon_command_rejected(self):
        with self.assertRaises(ValueError): self.transition({'command': self.after['command'] + ' changed'})

    def test_changed_parent_rejected(self):
        with self.assertRaises(ValueError): self.transition({'ppid': 1})

    def test_other_group_transition_rejected(self):
        with self.assertRaises(ValueError): self.transition({'pgid': 99999})

    def test_unrelated_baseline_daemon_rejected(self):
        self.monitor.baseline = {87105: self.before}
        with self.assertRaises(ValueError): self.transition()

    def test_log_inode_changed_after_adoption_rejected(self):
        self.monitor.daemons = {87105: dict(self.before, private_home_evidence=self.proof)}
        proof = copy.deepcopy(self.proof); proof['log_inode'] += 1
        with self.assertRaises(ValueError): self.transition(proof=proof)

    def test_private_home_changed_after_adoption_rejected(self):
        self.monitor.daemons = {87105: dict(self.before, private_home_evidence=self.proof)}
        proof = copy.deepcopy(self.proof); proof['private_gradle_home'] = '/unrelated/private-home'
        with self.assertRaises(ValueError): self.transition(proof=proof)

    def test_missing_private_identity_rejected(self):
        with patch.object(self.monitor, 'private_identity', return_value=None):
            with self.assertRaises(ValueError): self.monitor.refresh_session(87105, self.before, self.after)

    def test_private_identity_wrong_java_has_no_metadata_probe(self):
        changed = dict(self.after, command=self.after['command'].replace(self.ctx.config['JDK_java_executable'], '/other/java', 1))
        self.assertIsNone(self.monitor.private_identity(changed))

    def fake_physical(self, changed_home=False):
        def read(path):
            if path == DRIVER.PRIVATE_GRADLE:
                st = types.SimpleNamespace(st_dev=self.proof['home_identity'][0],
                    st_ino=self.proof['home_identity'][1] + int(changed_home), st_mode=0o40700)
                return types.SimpleNamespace(stat=lambda: st)
            return Path(path)
        return read

    def test_current_private_home_identity_changed_rejected(self):
        with patch.object(DRIVER, 'physical', side_effect=self.fake_physical(True)):
            with self.assertRaises(ValueError): self.monitor.private_identity(self.after)

    def test_wrong_open_log_inode_rejected(self):
        self.check_bad_open_log('i0\nn' + self.proof['opened_log'] + '\n')

    def test_wrong_open_log_path_rejected(self):
        self.check_bad_open_log('i' + str(self.proof['log_inode']) + '\nn/unrelated/daemon.log\n')

    def check_bad_open_log(self, fields):
        st = types.SimpleNamespace(st_mode=0o100600, st_nlink=1,
            st_ino=self.proof['log_inode'], st_dev=self.proof['log_device'])
        with patch.object(DRIVER, 'physical', side_effect=self.fake_physical()), \
                patch.object(Path, 'exists', return_value=True), patch.object(Path, 'lstat', return_value=st), \
                patch.object(DRIVER, 'metadata_command', return_value=(0, ('p87105\n' + fields).encode(), b'')), \
                patch.object(DRIVER, 'process_table', return_value={87105: self.after}):
            with self.assertRaises(ValueError): self.monitor.private_identity(self.after)

    def reuse(self, label=None, updates=None):
        data = copy.deepcopy(FIXTURE['reuse_data'])
        if label: data[label].update(updates)
        return DRIVER.validate_runtime_reuse(self.ctx, data)

    def test_actual_scope_runtime_reuse_positive(self):
        self.assertEqual(self.reuse()['components'], 173)
        self.assertTrue(self.reuse()['old_whole_driver_remains_failed'])

    def test_runtime_command_nonzero_rejected(self):
        with self.assertRaises(ValueError): self.reuse('command', {'exit_code': 1})

    def test_runtime_source_changed_rejected(self):
        with self.assertRaises(ValueError): self.reuse('APP_source_failure', {'strict_source_unchanged': False})

    def test_runtime_sdk_delta_changed_rejected(self):
        with self.assertRaises(ValueError): self.reuse('SDK_source_failure', {'allowed_source_deltas': []})

    def test_runtime_protected_changed_rejected(self):
        with self.assertRaises(ValueError): self.reuse('protected_failure', {'protected_metadata_paths_unchanged': 0})

    def test_missing_group_absence_rejected(self):
        with self.assertRaises(ValueError): self.reuse('root_readback', {'independent_absence': FIXTURE['reuse_data']['root_readback']['independent_absence'][:-1]})

    def test_live_group_absence_rejected(self):
        absence = copy.deepcopy(FIXTURE['reuse_data']['root_readback']['independent_absence'])
        absence[-1]['state'] = 'present'
        with self.assertRaises(ValueError): self.reuse('root_readback', {'independent_absence': absence})

    def test_graph_count_mismatch_rejected(self):
        with self.assertRaises(ValueError): self.reuse('root_readback', {'components': 0})

    def test_failed_whole_driver_promoted_rejected(self):
        with self.assertRaises(ValueError): self.reuse('terminal', {'status': 'pass'})

    def test_full_actual_frozen_reuse_read_and_exclusive_copy(self):
        admission = json.loads((HERE / 'root-admission-template.json').read_text())
        self.ctx.admission = admission
        with tempfile.TemporaryDirectory(prefix='fixture-output-', dir=HERE) as tmp:
            destination = Path(tmp)
            DRIVER.reuse_runtime_graph(self.ctx, destination)
            self.assertEqual(DRIVER.digest((destination / 'production-runtime-graph.json').read_bytes()),
                             admission['runtime_graph_reuse']['graph']['sha256'])
            self.assertTrue(json.loads((destination / 'runtime-graph-reuse.json').read_text())['completed_runtime_graph_reused'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
