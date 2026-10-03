#!/usr/bin/env python3
"""Original31 fixtures plus actual macOS terminal-state and compile-reuse cases."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('original_ownership_fixtures', HERE / 'test_owned_metadata.py')
ORIGINAL = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ORIGINAL)
DRIVER = ORIGINAL.DRIVER
CAPTURE = json.loads((HERE / 'captured-lifecycle-fixture.json').read_text())


class LifecycleFixtures(unittest.TestCase):
    def setUp(self):
        self.base = ORIGINAL.OwnershipFixtures()
        self.base.setUp()
        self.addCleanup(self.base.doCleanups)
        self.monitor = self.base.monitor
        self.ctx = self.base.ctx
        self.ctx.admission = json.loads((HERE / 'root-admission-template.json').read_text())

    def captured_terminal(self):
        observation = CAPTURE['probe']; row = observation['observed_row']
        current = {'pid': int(row['pid']), 'ppid': int(row['ppid']), 'pgid': int(row['pgid']),
                   'start': ' '.join(row[k] for k in ['weekday', 'month', 'day', 'clock', 'year']),
                   'state': row['state'], 'command': row['command']}
        before = dict(current, command=' '.join(observation['argv']), state='previous-state-not-captured',
                      ancestry=[current['pid']])
        self.monitor.root = current['pid']
        self.monitor.family = {current['pid']: before}
        return before, current

    def terminal_observe(self, updates=None):
        before, current = self.captured_terminal()
        if updates: current.update(updates)
        with patch.object(DRIVER, 'process_table', return_value={self.monitor.root: current}):
            self.monitor.observe(finishing=True)
        return before, current

    def test_actual_ps_terminal_Z_parser_retains_state_and_command(self):
        with patch.object(DRIVER, 'metadata_command', return_value=(0, CAPTURE['probe_raw_ps'].encode(), b'')):
            table = DRIVER.process_table()
        row = table[94043]
        self.assertEqual(row['state'], 'Z')
        self.assertEqual(row['command'], '<defunct>')
        self.assertEqual(row['start'], 'Fri Oct 2 14:59:45 2026')

    def test_actual_terminal_Z_rewrite_preserves_established_command_and_history(self):
        before, current = self.terminal_observe()
        self.assertEqual(before['command'], ' '.join(CAPTURE['probe']['argv']))
        self.assertEqual(before['last_observed_state'], 'Z')
        history = before['observed_terminal_history'][-1]
        self.assertEqual(history['actual_current'], current)
        self.assertFalse(history['zombie_is_absence'])
        self.assertFalse(history['signal_authorized_by_terminal_state'])
        self.assertEqual(self.monitor.last_owned_rows[94043]['command'], '<defunct>')

    def check_terminal_refusal(self, updates):
        with self.assertRaises(ValueError): self.terminal_observe(updates)
        refused = self.monitor.refused_transitions[-1]
        self.assertEqual(refused['before']['pid'], 94043)
        self.assertEqual(refused['current']['state'], 'Z')
        for k, v in updates.items(): self.assertEqual(refused['current'][k], v)

    def test_Z_wrong_PID_is_refused_with_current_metadata(self):
        self.check_terminal_refusal({'pid': 94044})

    def test_Z_wrong_start_is_refused_with_current_metadata(self):
        self.check_terminal_refusal({'start': 'reused PID start'})

    def test_Z_wrong_group_is_refused_with_current_metadata(self):
        self.check_terminal_refusal({'pgid': 99999})

    def test_unknown_live_command_is_refused_and_retained(self):
        with self.assertRaises(ValueError): self.terminal_observe({'state': 'S', 'command': '/unrelated/live-command'})
        current = self.monitor.refused_transitions[-1]['current']
        self.assertEqual(current['state'], 'S')
        self.assertEqual(current['command'], '/unrelated/live-command')

    def test_Z_does_not_supply_private_identity_or_metadata_probe(self):
        row = dict(self.base.after, state='Z')
        with patch.object(DRIVER, 'metadata_command', side_effect=AssertionError('Z must not probe open files')):
            self.assertIsNone(self.monitor.private_identity(row))

    def test_Z_daemon_is_neither_absence_nor_signal_authority(self):
        row = dict(self.base.after, state='Z', command='<defunct>')
        owned = dict(self.base.after, ancestry=[87082, 87105], private_home_evidence=self.base.proof)
        self.monitor.family = {87105: owned}
        self.monitor.daemons = {87105: owned}
        self.monitor.thread = None
        table = {87105: row}
        tick = iter(range(0, 200))
        with tempfile.TemporaryDirectory(prefix='terminal-fixture-', dir=HERE) as tmp:
            self.monitor.output = Path(tmp)
            with patch.object(DRIVER, 'process_table', return_value=table), \
                    patch.object(DRIVER.time, 'monotonic', side_effect=lambda: next(tick)), \
                    patch.object(DRIVER.time, 'sleep', return_value=None), \
                    patch.object(DRIVER.os, 'kill') as signals, patch.object(DRIVER.os, 'killpg') as groups:
                result = self.monitor.finish()
            signals.assert_not_called(); groups.assert_not_called()
            self.assertFalse(result['owned_daemons_absent'])
            self.assertTrue(result['terminal_Z_is_not_absence_or_signal_authority'])
            self.assertEqual(result['refused_transitions'][-1]['current']['state'], 'Z')

    def test_Z_then_actual_absent_table_is_retained_without_rewrite(self):
        before, current = self.captured_terminal()
        with patch.object(DRIVER, 'process_table', side_effect=[{94043: current}, {}]):
            self.monitor.observe(finishing=True)
            self.monitor.observe(finishing=True)
        self.assertEqual(before['observed_terminal_history'][-1]['actual_current']['state'], 'Z')
        self.assertEqual(self.monitor.last_owned_rows, {})
        self.assertEqual(CAPTURE['probe']['independent_absence'],
                         [{'kind': 'PID', 'id': 94043, 'state': 'ESRCH_absent'},
                          {'kind': 'PGID', 'id': 94043, 'state': 'ESRCH_absent'}])

    def test_actual_compile_scope_reuse_positive_preserves_failed_driver(self):
        result = DRIVER.validate_runtime_reuse(self.ctx, CAPTURE['compile_data'], 'compile')
        self.assertTrue(result['completed_compile_graph_reused'])
        self.assertTrue(result['old_whole_driver_remains_failed'])
        self.assertEqual(result['components'], 64)

    def test_compile_missing_independent_absence_rejected(self):
        data = copy.deepcopy(CAPTURE['compile_data'])
        data['root_readback']['independent_absence'] = []
        with self.assertRaises(ValueError): DRIVER.validate_runtime_reuse(self.ctx, data, 'compile')

    def test_full_actual_both_graph_reuse_no_graph_execution(self):
        with tempfile.TemporaryDirectory(prefix='both-graph-fixture-', dir=HERE) as tmp:
            destination = Path(tmp)
            DRIVER.reuse_runtime_graph(self.ctx, destination)
            DRIVER.reuse_runtime_graph(self.ctx, destination, 'compile')
            for kind in ['runtime', 'compile']:
                expected = self.ctx.admission[kind + '_graph_reuse']['graph']['sha256']
                self.assertEqual(DRIVER.digest((destination / ('production-' + kind + '-graph.json')).read_bytes()), expected)
            self.assertTrue(json.loads((destination / 'compile-graph-reuse.json').read_text())['completed_compile_graph_reused'])


if __name__ == '__main__':
    suite = unittest.TestSuite([
        unittest.defaultTestLoader.loadTestsFromTestCase(ORIGINAL.OwnershipFixtures),
        unittest.defaultTestLoader.loadTestsFromTestCase(LifecycleFixtures),
    ])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())
