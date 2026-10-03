#!/usr/bin/env python3
"""Offline diagnostic admission tests. Docker/database/provider never execute."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import current_generated_query_benchmark_uat as Q


class DiagnosticTransportTest(unittest.TestCase):
    def test_pinned_container_and_database_are_arguments_sql_is_stdin(self):
        db = 'qa_clone; do-not-execute $(hostname)'
        with patch.object(Q.U, 'command', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            Q.diagnostic_query(db, 'select synthetic_local_diagnostic();')
        args, body = run.call_args.args
        self.assertEqual(args[:5], [Q.U.DOCKER, 'exec', '-i', Q.U.CONTAINER, 'sh'])
        self.assertEqual(args[-1], db)
        self.assertNotIn(db, args[6])
        self.assertEqual(body, 'select synthetic_local_diagnostic();')
        self.assertNotIn(body, args)
        self.assertEqual(run.call_args.kwargs, {'check': False})

    def test_actual_shell_expansion_uses_synthetic_secret_without_copy_or_injection(self):
        # Only the shell segment executes, with a fake psql. The real Docker
        # executable and all PostgreSQL transports remain mocked.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            recorder = root / 'psql'
            recorder.write_text("""#!/usr/bin/env python3
import hashlib,json,os,sys
assert os.environ.get('PGPASSWORD') == os.environ['SYNTHETIC_EXPECTED_PASSWORD']
body=sys.stdin.read()
print(json.dumps({'argv':sys.argv[1:],'stdin_sha256':hashlib.sha256(body.encode()).hexdigest(),'credential_checked':True}))
""")
            recorder.chmod(0o700)
            marker = root / 'must-not-exist'
            db = 'qa_clone; touch ' + str(marker) + '; $(echo injected)'
            sentinel = 'SYNTHETIC-OFFLINE-TRANSPORT-SENTINEL'
            environment = {'PATH': str(root) + os.pathsep + os.environ['PATH'],
                           'POSTGRES_PASSWORD': sentinel, 'SYNTHETIC_EXPECTED_PASSWORD': sentinel}
            def offline_run(args, stdin, check):
                return subprocess.run(args[4:], input=stdin, text=True,
                                      capture_output=True, env=environment, check=check)
            with patch.object(Q.U, 'command', side_effect=offline_run) as run:
                result = Q.diagnostic_query(db, 'select synthetic_local_diagnostic();')
            self.assertEqual(result.returncode, 0, result.stderr)
            observed = json.loads(result.stdout)
            self.assertTrue(observed['credential_checked'])
            self.assertEqual(observed['argv'], ['-XqAt', '-U', 'supabase_admin', '-d', db,
                                               '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'])
            self.assertEqual(observed['stdin_sha256'], hashlib.sha256(b'select synthetic_local_diagnostic();').hexdigest())
            self.assertFalse(marker.exists())
            self.assertNotIn(sentinel, result.stdout + result.stderr + repr(run.call_args))

    def test_diagnostic_failure_is_retained_and_never_retried(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(Q.D, 'scalar', return_value={'synthetic': True}) as read, \
                 patch.object(Q.U, 'command', return_value=subprocess.CompletedProcess([], 2, '', 'FATAL synthetic diagnostic denied')) as diagnostic:
                with self.assertRaises(AssertionError):
                    Q.measured('qa_clone', 'select synthetic_api();', root, 'denied')
            self.assertEqual(read.call_count, 3)
            self.assertEqual(diagnostic.call_count, 1)
            self.assertEqual((root / 'denied.stderr').read_text(), 'FATAL synthetic diagnostic denied')
            sql = diagnostic.call_args.args[1]
            self.assertLess(sql.index("load 'auto_explain'"), sql.index('set session authorization postgres'))
            self.assertLess(sql.index('set session authorization postgres'), sql.index('set local role authenticated'))
            # The exact submitted statement already includes a semicolon;
            # the transport appends its own rollback separator unchanged.
            self.assertTrue(sql.endswith('select synthetic_api();;rollback;'))

    def test_diagnostic_preflight_failure_stops_before_any_dataset_posting(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(Q.B, 'seed_schema_clone_permission_catalog'), \
             patch.object(Q.D, 'seed'), patch.object(Q.P, 'seed_authority'), \
             patch.object(Q.P, 'seed_notification_catalog'), patch.object(Q.U, 'psql'), \
             patch.object(Q.D, 'scalar', return_value={'ok': True, 'mode': 'email', 'replay': False}), \
             patch.object(Q, 'rows_for') as rows, \
             patch.object(Q, 'diagnostic_query', return_value=subprocess.CompletedProcess([], 2, '', 'FATAL synthetic diagnostic denied')) as probe:
            root = Path(directory)
            with self.assertRaises(AssertionError):
                Q.seed('qa_clone', 1000, root, {}, [])
            rows.assert_not_called()
            self.assertEqual(probe.call_count, 1)
            self.assertEqual((root / 'diagnostic-preflight.stderr').read_text(), 'FATAL synthetic diagnostic denied')
            body = probe.call_args.args[1]
            self.assertLess(body.index("load 'auto_explain'"), body.index('set session authorization postgres'))
            self.assertLess(body.index('set session authorization postgres'), body.index('set local role authenticated'))
            self.assertIn('session_user', body)
            self.assertIn("auth.jwt()->>'session_id'", body)

    def test_diagnostic_preflight_checks_actual_role_and_session_echo(self):
        valid = {'preflight': True, 'session_user': 'postgres', 'api_role': 'authenticated',
                 'actor': Q.D.ACTOR, 'session': Q.D.SESSION}
        for mutation in ({}, {'api_role': 'supabase_admin'}, {'session': 'departed-synthetic-session'}):
            actual = dict(valid, **mutation)
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory, \
                 patch.object(Q, 'diagnostic_query', return_value=subprocess.CompletedProcess([], 0, json.dumps(actual) + '\n', '')):
                if mutation:
                    with self.assertRaises(AssertionError):
                        Q.diagnostic_preflight('qa_clone', Path(directory))
                else:
                    receipt = Q.diagnostic_preflight('qa_clone', Path(directory))
                    self.assertEqual(receipt['actual'], valid)
                    self.assertTrue(receipt['attempted_before_dataset_posting'])
                    self.assertFalse(receipt['nested_plan_acceptance_claimed'])

    def test_wrapper_only_plan_is_not_accepted_as_nested_plan(self):
        plan = json.dumps({'Query Text': 'select public.list_current_member_history_page(null,\'\',\'newest\',null,50)',
                           'Plan': {'Node Type': 'Result', 'Shared Hit Blocks': 1}})
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(Q.D, 'scalar', return_value={}), \
             patch.object(Q.U, 'command', return_value=subprocess.CompletedProcess([], 0, '', plan)):
            with self.assertRaises(AssertionError):
                Q.measured('qa_clone', 'select synthetic_api();', Path(directory), 'wrapper')

    def test_nested_buffer_plan_retains_actual_reported_duration(self):
        plan = 'LOG: duration: 1.234 ms plan:\n' + json.dumps({
            'Query Text': 'select count(*) from public.payments where status=\'posted\'',
            'Plan': {'Node Type': 'Aggregate', 'Shared Hit Blocks': 7, 'Plans': [
                {'Node Type': 'Seq Scan', 'Actual Rows': 42, 'Shared Hit Blocks': 6},
            ]},
        })
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(Q.D, 'scalar', return_value={'synthetic': True}), \
             patch.object(Q.U, 'command', return_value=subprocess.CompletedProcess([], 0, '{}', plan)):
            answer, record = Q.measured('qa_clone', 'select synthetic_api();', Path(directory), 'nested')
        self.assertEqual(answer, {'synthetic': True})
        self.assertEqual(record['nested_plan_count'], 1)
        self.assertEqual(record['nested_plans'][0]['Observed Duration Milliseconds'], 1.234)
        self.assertEqual(list(Q.nodes(record['nested_plans'][0]['Plan']))[1]['Actual Rows'], 42)
        self.assertFalse(record['wrapper_only_plan_accepted'])
        self.assertEqual(record['execution_api_role'], 'authenticated')
        self.assertEqual(len(record['end_to_end_seconds']), 3)


if __name__ == '__main__':
    unittest.main(verbosity=2)
