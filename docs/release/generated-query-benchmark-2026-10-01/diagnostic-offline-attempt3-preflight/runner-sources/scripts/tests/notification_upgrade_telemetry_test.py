"""Offline guard tests only. Every helper subprocess is forbidden/mocked."""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('telemetry', Path(__file__).with_name('notification_upgrade_telemetry.py'))
telemetry = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(telemetry)


class TelemetryGuardTests(unittest.TestCase):
    def setUp(self):
        self.no_process = patch.object(telemetry.subprocess, 'run', side_effect=AssertionError('No subprocess permitted in offline tests'))
        self.no_process.start()
        self.addCleanup(self.no_process.stop)
        self.expected = {'public.app_realtime_events': {'rows': 1, 'sha256': 'a'*64},
                         'public.payments': {'rows': 1, 'sha256': 'b'*64}}
        self.old = {'id': '99820000-0000-4000-8000-000000000001', 'area': 'profiles', 'created_at': '2026-09-29T00:00:00+00:00'}
        self.snapshot = {'backup_fingerprint': self.expected['public.app_realtime_events'],
                         'baseline_rows': [self.old], 'events': [{'row': self.old, 'xmin': '100'}],
                         'catalog': sorted(self.expected), 'fingerprints': copy.deepcopy(self.expected)}

    def test_original_rows_are_preserved_and_delta_is_only_described(self):
        added = dict(self.old, id='99720000-0000-4000-8000-000000000002', area='notifications')
        self.snapshot['events'].append({'row': added, 'xmin': '101'})
        rows, groups = telemetry.describe_delta(self.expected, self.snapshot)
        self.assertEqual(rows, [{'row': added, 'xmin': '101'}])
        self.assertEqual(groups[0]['areas'], {'notifications': 1})
        self.assertNotIn('proven', groups[0])

    def test_modified_original_row_refuses_cleanup(self):
        self.snapshot['events'] = [{'row': dict(self.old, area='audit'), 'xmin': '102'}]
        with self.assertRaisesRegex(RuntimeError, 'baseline telemetry row'):
            telemetry.describe_delta(self.expected, self.snapshot)

    def test_missing_original_row_refuses_cleanup(self):
        self.snapshot['events'] = []
        with self.assertRaisesRegex(RuntimeError, 'baseline telemetry row'):
            telemetry.describe_delta(self.expected, self.snapshot)

    def test_changed_financial_rows_refuse_disposition(self):
        self.snapshot['fingerprints']['public.payments']['sha256'] = 'c'*64
        with self.assertRaisesRegex(RuntimeError, 'Non-telemetry changes'):
            telemetry.describe_delta(self.expected, self.snapshot)

    def test_backup_fingerprint_must_match_saved_evidence(self):
        self.snapshot['backup_fingerprint'] = {'rows': 1, 'sha256': 'f'*64}
        with self.assertRaisesRegex(RuntimeError, 'backup rows'):
            telemetry.describe_delta(self.expected, self.snapshot)

    def test_unknown_table_refuses_disposition(self):
        self.snapshot['catalog'].append('public.unknown_table')
        with self.assertRaisesRegex(RuntimeError, 'catalog'):
            telemetry.describe_delta(self.expected, self.snapshot)

    def test_dump_parser_accepts_only_one_exact560_row_copy(self):
        rows = '\n'.join(f'99820000-0000-4000-8000-{n:012d}\tprofiles\t2026-09-29 00:00:00+00' for n in range(560))
        dump = ('COPY public.app_realtime_events (id, area, created_at) FROM stdin;\n'+rows+'\n\\.\n').encode()
        with patch.object(telemetry, 'command', return_value=dump):
            self.assertEqual(len(telemetry.export_backup()), 560)
        with patch.object(telemetry, 'command', return_value=dump+dump):
            with self.assertRaisesRegex(RuntimeError, 'one known COPY'):
                telemetry.export_backup()
        with patch.object(telemetry, 'command', return_value=dump.replace(b'000000000001', b'000000000000')):
            with self.assertRaisesRegex(RuntimeError, '560 unique'):
                telemetry.export_backup()

    def test_existing_evidence_output_fails_before_any_fixture_access(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'prior.json'; path.write_text('preserve me')
            args = types.SimpleNamespace(output=str(path))
            with patch.dict(os.environ, {'COLLECT_NOTIFICATION_TELEMETRY_QA': 'reviewed_isolated_trace'}):
                with self.assertRaisesRegex(RuntimeError, 'destination exists'):
                    telemetry.apply_trace(args)
            self.assertEqual(path.read_text(), 'preserve me')

    def test_unreviewed_trace_hash_fails_before_any_fixture_access(self):
        with tempfile.TemporaryDirectory() as directory:
            trace = Path(directory)/'trace.json'; trace.write_text('{}')
            args = types.SimpleNamespace(output=str(Path(directory)/'result.json'), trace=str(trace), trace_sha256='0'*64)
            with patch.dict(os.environ, {'COLLECT_NOTIFICATION_TELEMETRY_QA': 'reviewed_isolated_trace'}):
                with self.assertRaisesRegex(RuntimeError, 'digest mismatch'):
                    telemetry.apply_trace(args)


if __name__ == '__main__':
    unittest.main()
