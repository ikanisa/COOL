#!/usr/bin/env python3
"""Synthetic executable checks; no server, network, Docker or real approval."""
from pathlib import Path
import hashlib
import json
import os
import signal
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/qa'))
import postgres_admission as pg

REF = 'abcdefghijklmnopqrst'


class PostgresAdmissionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.client = self.root / 'psql'
        self.calls = self.root / 'calls.jsonl'
        self.manifest = self.root / 'manifest.json'
        self.service = self.root / 'service.conf'
        self.password = self.root / 'password.conf'
        self.env = dict(os.environ, PSQL_BIN=str(self.client), PGSERVICEFILE=str(self.service), PGPASSFILE=str(self.password), SUPABASE_PROJECT_REF=REF)
        self.program = f'''#!{sys.executable}
import json,os,sys
from pathlib import Path
if sys.argv[1:]==['--version']:
    if any(k in os.environ for k in ('PGPASSWORD','DATABASE_URL','SUPABASE_ACCESS_TOKEN','LD_PRELOAD','PYTHONPATH','BASH_ENV')):
        sys.exit(99)
    print('psql (PostgreSQL) 17.6');sys.exit(0)
with Path({str(self.calls)!r}).open('a') as f:
    f.write(json.dumps({{'argv':sys.argv[1:],'credential_environment':{{k:os.environ[k] for k in ('PGPASSWORD','DATABASE_URL','SUPABASE_ACCESS_TOKEN','COLLECT_PSQL_URL','PGOPTIONS') if k in os.environ}}}})+'\\n')
if any('server_version_num' in a for a in sys.argv):
    print(os.environ.get('SYNTHETIC_SERVER_NUMBER','170006'))
else:
    print('synthetic-result')
'''
        self.executable(self.program)
        self.value = {'schema_version': 1, 'kind': 'collect_postgres_admission',
            'review_reference': 'synthetic-only/not-human-reviewed',
            'client': {'path': str(self.client), 'sha256': pg.sha(self.client.read_bytes()), 'version': '17.6'},
            'server_matrix': [{'client_version': '17.6', 'server_version_num_min': 170006, 'server_version_num_max': 170006, 'operations': ['query', 'migration']}],
            'targets': [{'kind': 'supabase', 'project_ref': REF, 'host': f'db.{REF}.supabase.co', 'port': 5432, 'user': 'postgres', 'database': 'postgres'}],
            'timeouts': {'version_seconds': 1, 'server_seconds': 1, 'operation_seconds': 1}}
        self.service.write_text(f'[collect_readiness]\nhost=db.{REF}.supabase.co\nport=5432\nuser=postgres\ndbname=postgres\nsslmode=require\n')
        self.service.chmod(0o600)
        self.password.write_text('*:*:*:*:synthetic-secret\n')
        self.password.chmod(0o600)
        self.bind()

    def executable(self, text):
        self.client.write_text(text)
        self.client.chmod(0o700)

    def bind(self):
        self.manifest.write_text(json.dumps(self.value, sort_keys=True) + '\n')
        self.env['COLLECT_POSTGRES_ADMISSION'] = str(self.manifest)
        self.env['COLLECT_POSTGRES_ADMISSION_SHA256'] = pg.sha(self.manifest.read_bytes())

    def admit(self, operation='query'):
        return pg.Admission.from_environment(self.env, operation)

    def rows(self):
        return [json.loads(row) for row in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def no_request(self):
        self.assertEqual(self.rows(), [])

    def test_exact_client_and_matrix_then_first_read_and_operation(self):
        admitted = self.admit()
        self.assertEqual(admitted.psql(['service=collect_readiness', '-c', 'select 1'], self.env), b'synthetic-result\n')
        rows = self.rows()
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]['argv'][-1], pg.SERVER_QUERY)
        self.assertEqual(rows[1]['argv'], ['service=collect_readiness', '-c', 'select 1', '-X', '-w'])

    def test_local_admission_scrubs_credentials_before_executable_version(self):
        self.env.update(PGPASSWORD='synthetic-secret', DATABASE_URL='synthetic-secret', SUPABASE_ACCESS_TOKEN='synthetic-secret', BASH_ENV='synthetic-secret', PYTHONPATH='synthetic-secret')
        self.admit()
        self.no_request()

    def test_request_environment_scrubs_unbound_credentials_and_options(self):
        self.env.update(PGPASSWORD='synthetic-secret', DATABASE_URL='synthetic-secret', SUPABASE_ACCESS_TOKEN='synthetic-secret', COLLECT_PSQL_URL='synthetic-secret', PGOPTIONS='-c search_path=evil')
        self.admit().psql(['service=collect_readiness', '-Atq'], self.env)
        self.assertTrue(all(row['credential_environment'] == {} for row in self.rows()))

    def test_unbound_manifest_no_client_or_network_request(self):
        self.env.pop('COLLECT_POSTGRES_ADMISSION_SHA256')
        with self.assertRaisesRegex(pg.Refused, 'PG_MANIFEST_BINDING_REQUIRED'):
            self.admit()
        self.no_request()

    def test_wrong_manifest_digest_refuses_before_client_execution(self):
        self.env['COLLECT_POSTGRES_ADMISSION_SHA256'] = '0' * 64
        with self.assertRaisesRegex(pg.Refused, 'PG_MANIFEST_HASH_CHANGED'):
            self.admit()
        self.no_request()

    def test_byte_different_forged_matching_version_is_not_admitted(self):
        self.executable(self.program + '\n# unreviewed substitute still reports the same version\n')
        with self.assertRaisesRegex(pg.Refused, 'PG_CLIENT_HASH_CHANGED'):
            self.admit()
        self.no_request()

    def test_whole_hash_bound_wrong_version_is_not_admitted(self):
        self.executable(self.program.replace('psql (PostgreSQL) 17.6', 'psql (PostgreSQL) 15.12'))
        self.value['client']['sha256'] = pg.sha(self.client.read_bytes()); self.bind()
        with self.assertRaisesRegex(pg.Refused, 'PG_CLIENT_VERSION_UNKNOWN_OR_WRONG'):
            self.admit()
        self.no_request()

    def test_extra_version_output_refused_without_echoing_secret(self):
        self.executable(self.program.replace("print('psql (PostgreSQL) 17.6')", "print('psql (PostgreSQL) 17.6\\nsynthetic-secret')"))
        self.value['client']['sha256'] = pg.sha(self.client.read_bytes()); self.bind()
        with self.assertRaisesRegex(pg.Refused, 'PG_CLIENT_VERSION_UNKNOWN_OR_WRONG') as caught:
            self.admit()
        self.assertNotIn('synthetic-secret', str(caught.exception))
        self.no_request()

    def test_explicit_override_of_reviewed_absolute_client_is_refused(self):
        self.env['PSQL_BIN'] = str(self.root / 'unreviewed')
        with self.assertRaisesRegex(pg.Refused, 'PG_CLIENT_OVERRIDE_UNBOUND'):
            self.admit()
        self.no_request()

    def test_path_substitute_is_never_selected_or_executed(self):
        directory = self.root / 'substitute'; directory.mkdir()
        impostor = directory / 'psql'; impostor.write_text('#!/bin/sh\nexit 99\n'); impostor.chmod(0o700)
        self.env['PATH'] = str(directory)
        del self.env['PSQL_BIN']
        self.assertEqual(self.admit().client, self.client)
        self.no_request()

    def test_symlink_client_and_symlink_parent_refused(self):
        original = self.root / 'original'; self.client.rename(original); self.client.symlink_to(original)
        with self.assertRaisesRegex(pg.Refused, 'PG_SYMLINK_REFUSED'):
            self.admit()
        self.client.unlink(); original.rename(self.client)
        parent = self.root / 'alias'; parent.symlink_to(self.root, target_is_directory=True)
        self.value['client']['path'] = str(parent / 'psql'); self.env['PSQL_BIN'] = str(parent / 'psql'); self.bind()
        with self.assertRaisesRegex(pg.Refused, 'PG_SYMLINK_REFUSED'):
            self.admit()
        self.no_request()

    def test_hardlinked_client_is_refused(self):
        os.link(self.client, self.root / 'alias')
        with self.assertRaisesRegex(pg.Refused, 'PG_REGULAR_SINGLE_LINK_INPUT_REQUIRED'):
            self.admit()
        self.no_request()

    def test_client_drift_after_admission_refused_before_first_request(self):
        admitted = self.admit(); self.client.write_text(self.program + '\n# drift\n')
        with self.assertRaisesRegex(pg.Refused, 'PG_CLIENT_CHANGED_AFTER_ADMISSION'):
            admitted.psql(['service=collect_readiness', '-c', 'select 1'], self.env)
        self.no_request()

    def test_manifest_content_drift_after_admission_refused(self):
        admitted = self.admit(); self.manifest.write_bytes(self.manifest.read_bytes() + b' ')
        with self.assertRaisesRegex(pg.Refused, 'PG_MANIFEST_CHANGED_AFTER_ADMISSION'):
            admitted.psql(['service=collect_readiness', '-c', 'select 1'], self.env)
        self.no_request()

    def test_same_bytes_manifest_inode_substitution_is_refused_in_process(self):
        admitted = self.admit(); new = self.root / 'replacement'; new.write_bytes(self.manifest.read_bytes()); new.replace(self.manifest)
        with self.assertRaisesRegex(pg.Refused, 'PG_MANIFEST_CHANGED_AFTER_ADMISSION'):
            admitted.guard()

    def test_duplicate_json_keys_unknown_fields_and_overlarge_manifest_refused(self):
        raw = self.manifest.read_text()
        for malformed in [raw.replace('"schema_version": 1', '"schema_version": 1, "schema_version": 1'), raw[:-2] + ',"extra":true}\n', raw + ' ' * 16384]:
            with self.subTest(length=len(malformed)):
                self.manifest.write_text(malformed); self.env['COLLECT_POSTGRES_ADMISSION_SHA256'] = pg.sha(self.manifest.read_bytes())
                with self.assertRaises(pg.Refused):
                    self.admit()
        self.no_request()

    def test_claimed_unsupported_client_cannot_expand_source_cohort(self):
        for version in ['14.12','15.12','18.1','99.1']:
            with self.subTest(version=version):
                self.value['client']['version']=version
                self.value['server_matrix'][0]['client_version']=version
                self.bind()
                with self.assertRaisesRegex(pg.Refused,'PG_CLIENT_OUTSIDE_SOURCE_COHORT'):
                    self.admit()
                self.no_request()

    def test_claimed_unsupported_server_or_restore_cannot_expand_source_cohort(self):
        for low,high in [(150012,150012),(170006,170007),(180001,180001),(990001,990001)]:
            with self.subTest(server=(low,high)):
                self.value['server_matrix'][0]['server_version_num_min']=low
                self.value['server_matrix'][0]['server_version_num_max']=high
                self.bind()
                with self.assertRaisesRegex(pg.Refused,'PG_SERVER_RANGE_OUTSIDE_SOURCE_COHORT'):
                    self.admit()
                self.no_request()
        self.value['server_matrix'][0].update(server_version_num_min=170006,server_version_num_max=170006,operations=['query','restore']);self.bind()
        with self.assertRaisesRegex(pg.Refused,'PG_MATRIX_INVALID'):
            self.admit()
        self.no_request()

    def test_unknown_or_incompatible_server_stops_before_first_write(self):
        for value in ['150012', '170007', '170006 forged', 'unknown']:
            with self.subTest(server=value):
                self.env['SYNTHETIC_SERVER_NUMBER'] = value
                if self.calls.exists(): self.calls.unlink()
                with self.assertRaises(pg.Refused):
                    self.admit().psql(['service=collect_readiness', '-c', 'insert into sensitive values(1)'], self.env)
                self.assertEqual(len(self.rows()), 1)
                self.assertEqual(self.rows()[0]['argv'][-1], pg.SERVER_QUERY)

    def test_changed_server_matrix_range_and_operation_are_refused(self):
        self.value['server_matrix'][0]['operations'] = ['query']; self.bind()
        with self.assertRaisesRegex(pg.Refused, 'PG_OPERATION_OUTSIDE_SOURCE_COHORT'):
            self.admit('restore')
        self.value['server_matrix'][0]['server_version_num_max'] = 180001; self.bind()
        with self.assertRaisesRegex(pg.Refused, 'PG_SERVER_RANGE_OUTSIDE_SOURCE_COHORT'):
            self.admit()

    def test_wrong_service_target_and_project_refuse_before_request(self):
        for content, ref in [(self.service.read_text().replace('dbname=postgres', 'dbname=other'), REF), (self.service.read_text(), 'z'*20)]:
            self.service.write_text(content); self.env['SUPABASE_PROJECT_REF'] = ref
            with self.assertRaises(pg.Refused):
                self.admit().psql(['service=collect_readiness', '-Atq'], self.env)
            self.no_request()

    def test_connection_argument_override_is_refused_before_request(self):
        for args in [['postgresql://synthetic-secret@host/db'], ['service=collect_readiness', '-h', 'evil'], ['service=collect_readiness', '--dbname=evil'], ['service=collect_readiness', 'user=evil']]:
            with self.assertRaises(pg.Refused):
                self.admit().psql(args, self.env)
            self.no_request()

    def test_service_permissions_and_unbound_connection_options_refused(self):
        self.service.chmod(0o644)
        with self.assertRaisesRegex(pg.Refused, 'PG_SERVICE_PERMISSIONS_INVALID'):
            self.admit().psql(['service=collect_readiness'], self.env)
        self.service.chmod(0o600); self.service.write_text(self.service.read_text() + 'hostaddr=127.0.0.1\n')
        with self.assertRaisesRegex(pg.Refused, 'PG_SERVICE_OPTIONS_UNBOUND'):
            self.admit().psql(['service=collect_readiness'], self.env)
        self.no_request()

    def test_management_target_and_exact_single_integer_row_required(self):
        admitted = self.admit('migration')
        self.assertEqual(admitted.management_rows(b'[{"server_version_num":170006}]', REF)['server_version_num'], 170006)
        for raw in [b'[]', b'[{"server_version_num":"170006"}]', b'[{"server_version_num":170006,"other":1}]', b'[{"server_version_num":170006},{"server_version_num":170006}]', b'[{"server_version_num":true}]']:
            with self.assertRaises(pg.Refused): admitted.management_rows(raw, REF)
        with self.assertRaisesRegex(pg.Refused, 'PG_APPROVED_PROJECT_NOT_IN_MANIFEST'):
            admitted.management_rows(b'[{"server_version_num":170006}]', 'z'*20)
        self.no_request()

    def test_local_version_timeout_is_bounded_and_makes_no_request(self):
        self.executable(f'#!{sys.executable}\nimport time\ntime.sleep(20)\n')
        self.value['client']['sha256'] = pg.sha(self.client.read_bytes()); self.value['timeouts']['version_seconds'] = 0.1; self.bind()
        started = time.monotonic()
        with self.assertRaisesRegex(pg.Refused, 'PG_COMMAND_TIMEOUT'):
            self.admit()
        self.assertLess(time.monotonic()-started, 3)
        self.no_request()

    def test_server_read_timeout_never_runs_write(self):
        self.executable(self.program.replace("    print(os.environ.get('SYNTHETIC_SERVER_NUMBER','170006'))", '    import time; time.sleep(20)'))
        self.value['client']['sha256'] = pg.sha(self.client.read_bytes()); self.value['timeouts']['server_seconds'] = 0.1; self.bind()
        with self.assertRaisesRegex(pg.Refused, 'PG_COMMAND_TIMEOUT'):
            self.admit().psql(['service=collect_readiness', '-c', 'insert into sensitive values(1)'], self.env)
        self.assertEqual(len(self.rows()), 1)

    def test_output_limit_refuses_without_raw_output_or_secrets(self):
        self.executable(f'#!{sys.executable}\nprint("synthetic-secret"*10000)\n')
        self.value['client']['sha256'] = pg.sha(self.client.read_bytes()); self.bind()
        with self.assertRaisesRegex(pg.Refused, 'PG_COMMAND_OUTPUT_LIMIT') as caught:
            self.admit()
        self.assertNotIn('synthetic-secret', str(caught.exception))
        self.no_request()

    def test_descendant_holding_pipe_is_killed_on_timeout(self):
        pidfile = self.root / 'child.pid'
        script = f'#!/bin/sh\n/bin/sleep 20 &\nprintf "%s" "$!" > {str(pidfile)!r}\nexit 0\n'
        self.executable(script)
        started = time.monotonic()
        with self.assertRaisesRegex(pg.Refused, 'PG_COMMAND_TIMEOUT'):
            pg.bounded([str(self.client)], pg.local_environment(), 2, limit=1024)
        self.assertLess(time.monotonic()-started, 5)
        pid = int(pidfile.read_text())
        # A killed child may remain a zombie until the OS reaps it. Its state
        # is terminal; no process command receives a global kill or name match.
        import subprocess
        result = subprocess.run(['/bin/ps', '-o', 'stat=', '-p', str(pid)], capture_output=True, timeout=2)
        state = result.stdout.decode().strip()
        self.assertTrue(not state or state.startswith('Z'), state)


if __name__ == '__main__':
    unittest.main()
