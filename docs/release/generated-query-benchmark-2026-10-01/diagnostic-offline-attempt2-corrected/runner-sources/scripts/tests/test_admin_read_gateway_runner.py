import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest

MODULE = pathlib.Path(__file__).with_name('admin_read_gateway_gate.py')
SPEC = importlib.util.spec_from_file_location('gate', MODULE)
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


class RunnerTests(unittest.TestCase):
    def test_actual_timeout_retains_stdout_and_stops_its_child(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder)
            pid_file = path / 'child.pid'
            child = "import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print(os.getpid(),flush=True); time.sleep(10)"
            parent = "import subprocess,sys,time; child=subprocess.Popen([sys.executable,'-c',sys.argv[2]],stdout=open(sys.argv[1],'w')); print('retained-before-timeout',flush=True); time.sleep(10)"
            # Leave startup headroom so this probes a running parent/child,
            # rather than timing out before Python reaches its first print.
            result = GATE.run_command([sys.executable, '-c', parent, str(pid_file), child], path, path / 'stdout', 1.5)
            self.assertTrue(result['timed_out'])
            self.assertEqual(result['exit_code'], 124)
            self.assertIn('retained-before-timeout', (path / 'stdout').read_text())
            pid = pid_file.read_text().strip()
            probe = subprocess.run(['ps', '-o', 'stat=', '-p', pid], capture_output=True, text=True)
            self.assertTrue(not probe.stdout.strip() or probe.stdout.strip().startswith('Z'))

    def test_actual_success_retains_log_and_reports_real_status(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder)
            result = GATE.run_command([sys.executable, '-c', "print('actual-success')"], path, path / 'stdout', 2)
            self.assertFalse(result['timed_out'])
            self.assertEqual(result['exit_code'], 0)
            self.assertIn('actual-success', (path / 'stdout').read_text())


if __name__ == '__main__':
    unittest.main()
