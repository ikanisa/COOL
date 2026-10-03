import importlib.util
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

MODULE = pathlib.Path(__file__).with_name('admin_read_gateway_gate.py')
SPEC = importlib.util.spec_from_file_location('gate', MODULE)
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)

def load_tool(name):
    path = MODULE.with_name(name + '.py')
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MATRIX = load_tool('admin_matrix_report')
ACCEPTANCE = load_tool('admin_matrix_acceptance')


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


class InventoryBindingTests(unittest.TestCase):
    def test_new_required_runtime_is_not_hidden_by_matching_intersection(self):
        sources = {'lib/admin/existing.dart': 'same',
                   'lib/admin/new_enabled.dart': 'new',
                   'test/admin_new_enabled_test.dart': 'test',
                   'supabase/migrations/dated.sql': 'sql'}
        result = MATRIX.compare_inventory_to_bound_sources(
            sources, {'lib/admin/existing.dart': 'same'})
        self.assertFalse(result['matches'])
        self.assertEqual(result['changed_shared_inputs'], [])
        self.assertEqual(result['missing_required_client_inputs'],
                         ['lib/admin/new_enabled.dart', 'test/admin_new_enabled_test.dart'])
        self.assertEqual(result['non_client_inputs_outside_export'],
                         ['supabase/migrations/dated.sql'])

    def test_matched_client_inputs_do_not_imply_sql_execution(self):
        result = MATRIX.compare_inventory_to_bound_sources(
            {'lib/admin/current.dart': 'same', 'supabase/migrations/dated.sql': 'sql'},
            {'lib/admin/current.dart': 'same'})
        self.assertTrue(result['matches'])
        self.assertEqual(result['non_client_inputs_outside_export'],
                         ['supabase/migrations/dated.sql'])

    def test_changed_shared_input_and_missing_consumed_config_both_fail_closed(self):
        result = MATRIX.compare_inventory_to_bound_sources(
            {'test/admin_current_test.dart': 'current', 'pubspec.lock': 'lock'},
            {'test/admin_current_test.dart': 'old'})
        self.assertFalse(result['matches'])
        self.assertEqual(result['changed_shared_inputs'], ['test/admin_current_test.dart'])
        self.assertEqual(result['missing_required_client_inputs'], ['pubspec.lock'])

    def test_actual_report_rejects_runtime_missing_from_export(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder)
            (path / 'acceptance').mkdir()
            export = path / 'export'
            export.mkdir()
            (path / 'acceptance/validation.json').write_text(json.dumps({'machine_summary': {}}))
            (path / 'validation.json').write_text(json.dumps({
                'source_export': str(export), 'passed': True,
                'export_source_unchanged': True, 'receipt_sha256': 'synthetic-not-SQL'}))
            (path / 'export-before.json').write_text('{}')
            (path / 'acceptance/tests.machine.jsonl').write_text('')
            source = 'lib/admin/new_enabled_provider.dart'
            inventory = path / 'inventory.json'
            inventory.write_text(json.dumps({'sources': {source: 'missing'},
                'routes': [], 'endpoints': [], 'providers': []}))
            result = subprocess.run([sys.executable, str(MODULE.with_name('admin_matrix_report.py')),
                '--packet', str(path), '--inventory', str(inventory),
                '--output', str(path / 'report')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((path / 'report/matrix.json').read_text())
            self.assertFalse(report['inventory_source_matches_tested_shared_inputs'])
            self.assertEqual(report['inventory_required_client_inputs_missing'], [source])
            self.assertFalse(report['full_Admin_acceptance'])

    def test_missing_decoder_input_stops_export_and_complete_inputs_are_hashed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            names = ACCEPTANCE.CURRENT_ADMIN_DECODER_INPUTS
            data = b'{"synthetic_decoder_input":true}\n'
            for name in names[:-1]:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            with self.assertRaisesRegex(FileNotFoundError, 'Required Admin decoder inputs missing'):
                ACCEPTANCE.inventory(root)
            last = root / names[-1]
            last.parent.mkdir(parents=True, exist_ok=True)
            last.write_bytes(data)
            bound = ACCEPTANCE.inventory(root)
            self.assertEqual({name: bound[name] for name in names},
                             {name: hashlib.sha256(data).hexdigest() for name in names})


if __name__ == '__main__':
    unittest.main()
