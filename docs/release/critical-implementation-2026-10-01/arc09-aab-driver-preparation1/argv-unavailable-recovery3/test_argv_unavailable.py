#!/usr/bin/env python3
"""Preserved43 fixtures plus captured macOS ucomm-only wrapper observations."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('previous_lifecycle_fixtures', HERE / 'test_lifecycle_metadata.py')
PREVIOUS = importlib.util.module_from_spec(spec)
spec.loader.exec_module(PREVIOUS)
DRIVER = PREVIOUS.DRIVER
CAPTURE = json.loads((HERE / 'captured-stage3-production-release-aab.daemon-readback.json').read_text())
COMMAND = json.loads((HERE / 'captured-stage3-production-release-aab.json').read_text())


class ArgvUnavailableFixtures(unittest.TestCase):
    def setUp(self):
        self.base = PREVIOUS.ORIGINAL.OwnershipFixtures()
        self.base.setUp()
        self.addCleanup(self.base.doCleanups)
        self.monitor = self.base.monitor
        self.ctx = self.base.ctx
        self.monitor.label = 'production-release-aab'
        self.ctx.admission = json.loads((HERE / 'root-admission-template.json').read_text())
        refused = CAPTURE['refused_transitions'][0]
        self.before = copy.deepcopy(refused['before'])
        self.current = copy.deepcopy(refused['current'])
        self.monitor.root = self.before['pid']
        self.monitor.family = {self.before['pid']: self.before}

    def observed(self, updates=None, extra=None):
        if updates: self.current.update(updates)
        table = {self.monitor.root: self.current}
        if extra: table.update(extra)
        with patch.object(DRIVER, 'process_table', return_value=table), \
                patch.object(DRIVER, 'plain_read', side_effect=self.base.wrapper_read):
            self.monitor.observe(finishing=True)
        return table

    def refusal(self, updates):
        with self.assertRaises(ValueError): self.observed(updates)
        event = self.monitor.refused_transitions[-1]
        self.assertEqual(event['current'], self.current)
        for key, value in updates.items(): self.assertEqual(event['current'][key], value)

    def test_actual_captured_live_java_fallback_is_observation_only(self):
        self.assertEqual(self.before['state'], 'Rs')
        self.assertEqual(self.current['state'], 'Ss')
        self.assertEqual(self.current['command'], '(java)')
        established = self.before['command']
        self.observed()
        self.assertEqual(self.before['command'], established)
        self.assertEqual(self.before['last_observed_state'], 'Ss')
        history = self.before['observed_argv_unavailable_history'][-1]
        self.assertEqual(history['actual_current'], self.current)
        self.assertFalse(history['argv_unavailable_is_absence'])
        self.assertFalse(history['new_ownership_authorized'])
        self.assertFalse(history['signal_authorized_by_unavailable_argv'])
        self.assertEqual(self.monitor.last_owned_rows[95283], self.current)
        self.assertEqual(self.monitor.daemons, {})
        self.assertNotIn('observed_exec_history', self.before)

    def test_actual_parenthesized_java_row_parser_preserves_state(self):
        row = self.current
        raw = ('%s %s %s %s %s %s\n' % (row['pid'], row['ppid'], row['pgid'],
               row['start'], row['state'], row['command'])).encode()
        with patch.object(DRIVER, 'metadata_command', return_value=(0, raw, b'')):
            self.assertEqual(DRIVER.process_table()[95283], row)

    def test_restored_identical_full_argv_does_not_create_an_exec(self):
        self.observed()
        self.current['command'] = self.before['command']
        self.current['state'] = 'S'
        self.observed()
        self.assertNotIn('observed_exec_history', self.before)
        self.assertEqual(len(self.before['observed_argv_unavailable_history']), 1)

    def test_wrong_parenthesized_name_is_refused_and_retained(self):
        self.refusal({'command': '(python)'})

    def test_fallback_wrong_PID_is_refused_and_retained(self):
        self.refusal({'pid': 99999})

    def test_fallback_reused_start_is_refused_and_retained(self):
        self.refusal({'start': 'different reused PID start'})

    def test_fallback_other_group_is_refused_and_retained(self):
        self.refusal({'pgid': 99999})

    def test_unknown_full_live_command_is_still_refused(self):
        self.refusal({'command': self.before['command'] + ' unexpected-live-argument'})

    def test_fallback_after_unverified_wrapper_command_is_refused(self):
        self.before['command'] = '/unrelated/java'
        self.refusal({})

    def test_fallback_changed_wrapper_JAR_binding_is_refused(self):
        with patch.object(DRIVER, 'process_table', return_value={95283: self.current}), \
                patch.object(DRIVER, 'plain_read', side_effect=ValueError('wrapper source hash changed')):
            with self.assertRaises(ValueError): self.monitor.observe(finishing=True)
        self.assertEqual(self.monitor.refused_transitions[-1]['current'], self.current)

    def test_fallback_cannot_establish_a_new_wrapper(self):
        self.monitor.family = {}
        self.current['ppid'] = DRIVER.os.getpid()
        self.refusal({})
        self.assertEqual(self.monitor.family, {})

    def test_unrelated_baseline_fallback_cannot_be_owned(self):
        self.monitor.family = {}
        self.monitor.baseline = {95283: self.current}
        self.current['ppid'] = DRIVER.os.getpid()
        self.refusal({})
        self.assertEqual(self.monitor.family, {})

    def test_fallback_parent_cannot_adopt_a_new_daemon(self):
        row = copy.deepcopy(CAPTURE['observed_new_daemons'][0]['daemon'])
        row.pop('private_home_evidence', None)
        row.pop('observed_session_history', None)
        with patch.object(self.monitor, 'private_identity', side_effect=lambda current:
                          self.base.proof if current['pid'] == row['pid'] else None):
            self.observed(extra={row['pid']: row})
        self.assertNotIn(row['pid'], self.monitor.family)
        self.assertNotIn(row['pid'], self.monitor.daemons)
        self.assertIn(row['pid'], self.monitor.unproven)

    def test_fallback_daemon_cannot_supply_signal_identity_or_absence(self):
        row = dict(self.base.after, command='(java)', state='Ss')
        owned = dict(self.base.after, ancestry=[87082, 87105], private_home_evidence=self.base.proof)
        self.monitor.family = {87105: owned}
        self.monitor.daemons = {87105: owned}
        self.monitor.thread = None
        tick = iter(range(0, 200))
        with tempfile.TemporaryDirectory(prefix='unavailable-fixture-', dir=HERE) as tmp:
            self.monitor.output = Path(tmp)
            with patch.object(DRIVER, 'process_table', return_value={87105: row}), \
                    patch.object(DRIVER.time, 'monotonic', side_effect=lambda: next(tick)), \
                    patch.object(DRIVER.time, 'sleep', return_value=None), \
                    patch.object(DRIVER.os, 'kill') as signals, patch.object(DRIVER.os, 'killpg') as groups:
                result = self.monitor.finish()
            signals.assert_not_called(); groups.assert_not_called()
            self.assertFalse(result['owned_daemons_absent'])
            self.assertTrue(result['unavailable_argv_is_not_absence_ownership_or_signal_authority'])
            self.assertEqual(result['refused_transitions'][-1]['current']['command'], '(java)')

    def test_genuine_failed_offline_AAB_remains_a_failure(self):
        self.assertEqual(COMMAND['exit_code'], 1)
        with self.assertRaises(ValueError): self.ctx.guards.process_success(COMMAND)


if __name__ == '__main__':
    suite = unittest.TestSuite([
        unittest.defaultTestLoader.loadTestsFromTestCase(PREVIOUS.ORIGINAL.OwnershipFixtures),
        unittest.defaultTestLoader.loadTestsFromTestCase(PREVIOUS.LifecycleFixtures),
        unittest.defaultTestLoader.loadTestsFromTestCase(ArgvUnavailableFixtures),
    ])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())
