import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import json

SPEC = importlib.util.spec_from_file_location('roster_gate', Path(__file__).with_name('roster_fresh_auth_gate.py'))
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


class RunnerTests(unittest.TestCase):
    def test_named_sql149_success_ignores_unrelated_skip_but_rejects_missing_failed_skipped_duplicate(self):
        named = {'type': 'testStart', 'test': {'id': 1, 'name': 'actual149 fresh recovery receipts agree with every client decoder'}}
        unrelated = {'type': 'testStart', 'test': {'id': 2, 'name': 'historical SQL fixture'}}
        def summary(events):
            with tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'events.jsonl'
                path.write_text(''.join(json.dumps(e) + '\n' for e in events))
                return GATE.machine_summary(path)
        passed = {'type': 'testDone', 'testID': 1, 'result': 'success', 'skipped': False, 'hidden': False}
        done = {'type': 'done', 'success': True}
        self.assertTrue(GATE.actual_sql149_test_passed(summary([named, passed, unrelated,
            {'type': 'testDone', 'testID': 2, 'result': 'success', 'skipped': True, 'hidden': False}, done])))
        for events in [[], [named, done], [named, {**passed, 'result': 'failure'}, done],
                       [named, {**passed, 'skipped': True}, done], [named, passed, passed, done]]:
            self.assertFalse(GATE.actual_sql149_test_passed(summary(events)))

    def test_actual_timeout_preserves_phase_and_stops_owned_child(self):
        with tempfile.TemporaryDirectory() as folder:
            packet = Path(folder)
            pid_file = packet / 'child.pid'
            child = "import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print(os.getpid(),flush=True); time.sleep(10)"
            parent = "import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',sys.argv[2]],stdout=open(sys.argv[1],'w')); print('last-exact-phase',flush=True); print('retained-error',file=sys.stderr,flush=True); time.sleep(10)"
            result = GATE.command('probe', [sys.executable, '-c', parent, str(pid_file), child], packet, packet, timeout=1.5)
            self.assertEqual(result['exit_code'], 124)
            self.assertTrue(result['timed_out'])
            self.assertTrue(result['parent_exit_confirmed'])
            self.assertIn('last-exact-phase', (packet / 'probe.stdout').read_text())
            self.assertIn('retained-error', (packet / 'probe.stderr').read_text())
            probe = subprocess.run(['ps', '-o', 'stat=', '-p', pid_file.read_text().strip()], capture_output=True, text=True)
            self.assertTrue(not probe.stdout.strip() or probe.stdout.strip().startswith('Z'))

    def test_success_and_nonzero_results_preserve_actual_status(self):
        with tempfile.TemporaryDirectory() as folder:
            packet = Path(folder)
            for code in [0, 3]:
                result = GATE.command(str(code), [sys.executable, '-c', f"print('actual-{code}'); raise SystemExit({code})"], packet, packet, timeout=2)
                self.assertEqual(result['exit_code'], code)
                self.assertFalse(result['timed_out'])
                self.assertIn(f'actual-{code}', (packet / f'{code}.stdout').read_text())


if __name__ == '__main__':
    unittest.main()
