#!/usr/bin/env python3
"""Offline admission failures for new Admin query diagnostics; no SQL or Docker."""
import json
import copy
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import current_admin_query_benchmark_uat as A


def nested(scope='gateway', rows=51, buffers=True):
    node = {'Node Type': 'Index Scan', 'Relation Name': A.API_RELATIONS[scope],
            'Actual Rows': rows}
    if buffers:
        node['Shared Hit Blocks'] = 7
    return {'Query Text': 'with candidates as materialized(select fixture_rows) select fixture_projection',
            'Plan': {'Node Type': 'Limit', 'Actual Rows': rows, 'Plans': [node]}}


class AdminDiagnosticAdmissionTest(unittest.TestCase):
    def test_new_public_api_wrapper_does_not_establish_relational_plan(self):
        for scope, api in A.API_NAMES.items():
            wrapper = {'Query Text': 'select ' + api + '(50)',
                       'Plan': {'Node Type': 'Result', 'Shared Hit Blocks': 9}}
            with self.subTest(scope=scope), self.assertRaises(AssertionError):
                A.read_plan(json.dumps(wrapper), scope)

    def test_actor_or_other_relation_plan_does_not_establish_list_plan(self):
        plan = nested()
        plan['Plan']['Plans'][0]['Relation Name'] = 'profiles'
        with self.assertRaises(AssertionError):
            A.read_plan(json.dumps(plan), 'gateway')

    def test_actual_nested_buffers_and_reported_duration_are_retained(self):
        for scope in A.API_NAMES:
            plan = nested(scope)
            with self.subTest(scope=scope):
                actual = A.read_plan('LOG: duration: 1.234 ms plan:\n' + json.dumps(plan), scope)
                self.assertEqual(actual['Observed Duration Milliseconds'], 1.234)
                self.assertEqual(actual['Plan']['Plans'][0]['Shared Hit Blocks'], 7)

    def test_unbounded_generated_window_is_rejected(self):
        with self.assertRaises(AssertionError):
            A.read_plan(json.dumps(nested(rows=52)), 'gateway')

    def test_missing_nested_buffers_are_rejected(self):
        with self.assertRaises(AssertionError):
            A.read_plan(json.dumps(nested(buffers=False)), 'gateway')

    def test_failed_diagnostic_is_preserved_and_not_retried(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(A.D, 'scalar', return_value={}) as reads, \
                patch.object(A.Q, 'diagnostic_query', return_value=subprocess.CompletedProcess(
                    [], 2, '', 'FATAL synthetic diagnostic denied')) as diagnostic:
            packet = Path(directory)
            with self.assertRaises(AssertionError):
                A.measured('synthetic_disposable', 'select synthetic_api()', packet, 'denied', 'gateway')
            self.assertEqual(reads.call_count, 3)
            self.assertEqual(diagnostic.call_count, 1)
            self.assertEqual((packet / 'denied.stderr').read_text(), 'FATAL synthetic diagnostic denied')
            body = diagnostic.call_args.args[1]
            self.assertLess(body.index("load 'auto_explain'"), body.index('set session authorization postgres'))
            self.assertLess(body.index('set session authorization postgres'), body.index('set local role authenticated'))

    def test_preflight_requires_exact_api_role_actor_and_session(self):
        valid = dict(preflight=True, session_user='postgres', api_role='authenticated',
                     actor=A.P.MAKER, session=A.SID)
        for mutation in ({}, {'api_role': 'supabase_admin'}, {'actor': 'different-actor'},
                         {'session': 'departed-session'}):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory, \
                    patch.object(A.Q, 'diagnostic_query', return_value=subprocess.CompletedProcess(
                        [], 0, json.dumps(dict(valid, **mutation)) + '\n', '')) as diagnostic:
                if mutation:
                    with self.assertRaises(AssertionError):
                        A.preflight('synthetic_disposable', Path(directory))
                else:
                    self.assertTrue(A.preflight('synthetic_disposable', Path(directory))['before_volume_fixtures'])
                self.assertEqual(diagnostic.call_count, 1)


class FullReceiptAdmissionTest(unittest.TestCase):
    def receipt(self):
        rows = [dict(path=f'supabase/migrations/2026100100000{i}_synthetic.sql',
                     version=f'2026100100000{i}', sha256=str(i) * 64) for i in range(3)]
        guard = dict(network='none', published_ports=False, labels_verified=True, cron='off', net='0')
        phase = dict(status='pass', task_container_removed=True, guard=guard,
            scheduler_readback=dict(cron='off', net='0', history=0),
            net_platform_ownership=dict(extension_owner='supabase_admin', schema='extensions', version='0.20.0'),
            migrations=[dict(row, status='pass', canonical_predecessor_preserved=True,
                actual_installer_authority=dict(superuser=False, current_user='postgres', current_role='postgres'))
                        for row in rows])
        path = 'scripts/sql/receipt_transport_platform_prerequisites.sql'
        proof = dict(kind='ordinary_local_installer_all_current_clean_populated', status='pass',
            all_task_containers_removed=True, shared_database_written=False, source_rows_copied=False,
            source_inventory=rows, predecessor=dict(count=1),
            platform_prerequisite_sha256={path: 'a' * 64},
            phases=dict(clean=copy.deepcopy(phase), populated=copy.deepcopy(phase)))
        return proof, {r['path']: r['sha256'] for r in rows}, path

    def test_dynamic_capture_count_admits_exact_clean_and_populated_receipt(self):
        proof, current, path = self.receipt()
        self.assertEqual(len(A.admit_receipt(proof, current, path, 'a' * 64)), 3)

    def test_failed_partial_or_unremoved_target_is_not_a_terminal_receipt(self):
        for mutation in (dict(status='running'), dict(status='failed'), dict(all_task_containers_removed=False)):
            proof, current, path = self.receipt()
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                A.admit_receipt(dict(proof, **mutation), current, path, 'a' * 64)

    def test_changed_added_or_missing_source_is_refused_before_sql(self):
        for kind in ('changed', 'added', 'missing'):
            proof, current, path = self.receipt()
            if kind == 'changed':
                current[next(iter(current))] = 'f' * 64
            elif kind == 'added':
                current['supabase/migrations/20261002000001_new.sql'] = 'f' * 64
            else:
                current.pop(next(iter(current)))
            with self.subTest(kind=kind), self.assertRaises(AssertionError):
                A.admit_receipt(proof, current, path, 'a' * 64)

    def test_missing_phase_migration_or_superuser_execution_is_refused(self):
        for kind in ('phase', 'migration', 'superuser', 'preservation', 'scheduler'):
            proof, current, path = self.receipt()
            if kind == 'phase':
                proof['phases'].pop('populated')
            elif kind == 'migration':
                proof['phases']['clean']['migrations'].pop()
            elif kind == 'superuser':
                proof['phases']['populated']['migrations'][1]['actual_installer_authority']['superuser'] = True
            elif kind == 'preservation':
                proof['phases']['populated']['migrations'][1]['canonical_predecessor_preserved'] = False
            else:
                proof['phases']['clean']['scheduler_readback']['net'] = '1'
            with self.subTest(kind=kind), self.assertRaises(AssertionError):
                A.admit_receipt(proof, current, path, 'a' * 64)

    def test_unbound_platform_sql_cannot_be_used(self):
        proof, current, path = self.receipt()
        with self.assertRaises(AssertionError):
            A.admit_receipt(proof, current, path, 'b' * 64)

    def test_owner_assertions_and_all_column_privacy_revokes_are_admitted(self):
        source = """do $owner$begin
          if current_user<>'supabase_admin' then raise exception 'platform owner required';end if;
          end $owner$;
          revoke all on net._http_response,net.http_request_queue from public,anon,authenticated,service_role,postgres;
          do $columns$declare c text;begin
          for c in select attname from pg_attribute where attrelid='net._http_response'::regclass loop
            execute format('revoke all(%I)on net._http_response from public,anon,authenticated,service_role,postgres',c);
          end loop;end $columns$;
        """ + ';\n'.join(A.PLATFORM_STATEMENTS) + ';'
        self.assertEqual(A.admit_platform_sql(source), source)

    def test_broad_grant_owner_change_or_http_work_is_refused(self):
        source = ';\n'.join(A.PLATFORM_STATEMENTS) + ';'
        for unsafe in ('grant pg_read_all_data to postgres;',
                       'grant select on net._http_response to postgres;',
                       'alter role postgres superuser;',
                       'alter table net._http_response owner to postgres;',
                       "select net.http_post('https://synthetic.invalid');"):
            with self.subTest(unsafe=unsafe), self.assertRaises(AssertionError):
                A.admit_platform_sql(source + unsafe)

    def test_actual_bound_platform_regprocedure_assertion_is_not_http_work(self):
        source = A.PLATFORM_PATH.read_text()
        self.assertIn("to_regprocedure('net.http_post(", source)
        self.assertEqual(A.admit_platform_sql(source), source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
