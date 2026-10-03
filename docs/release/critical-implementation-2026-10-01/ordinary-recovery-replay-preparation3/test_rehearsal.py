#!/usr/bin/env python3
"""Focused stdlib-only admission, archive parser, and bounded runner checks."""
from pathlib import Path
import copy
import importlib.util
import json
import os
import sys
import tempfile
import time
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('recovery_candidate', HERE / 'rehearsal.py')
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)


class AdmissionTests(unittest.TestCase):
    def review(self):
        # Test parser fixture only; never retained or used as authorization.
        return dict(kind='collect_local_synthetic_recovery_review_v1', decision='admit',
            review_reference='test-fixture-not-authorization', code_sha256='a' * 64,
            inputs_sha256='b' * 64, image_id=r.IMAGE, client_version='17.6',
            server_version_num=170006, operations=list(r.OPERATIONS),
            scope='owned_networkless_synthetic_fixture_only')

    def test_exact_proposed_fixture_cohort(self):
        self.assertEqual(r.admit_review(self.review(), 'a'*64, 'b'*64)['decision'], 'admit')

    def test_review_drift_and_scope_are_refused(self):
        values = [('code_sha256','c'*64), ('inputs_sha256','c'*64), ('image_id','latest'),
                  ('client_version','17.7'), ('server_version_num',170007),
                  ('operations',['query','migration','restore']), ('scope','hosted'),
                  ('decision','proposed'), ('review_reference','arbitrary command;')]
        for key, value in values:
            with self.subTest(key=key):
                candidate = self.review(); candidate[key] = value
                with self.assertRaises(r.Refused):
                    r.admit_review(candidate, 'a'*64, 'b'*64)

    def test_unknown_and_duplicate_json_fields_refused(self):
        candidate = self.review(); candidate['approval_created_by_script'] = True
        with self.assertRaises(r.Refused):
            r.admit_review(candidate, 'a'*64, 'b'*64)
        with self.assertRaisesRegex(r.Refused,'DUPLICATE_JSON_KEY'):
            json.loads('{"decision":"proposed","decision":"admit"}', object_pairs_hook=r.unique)

    def test_actual_tool_versions(self):
        for tool in ['psql','pg_dump','pg_restore','postgres']:
            self.assertEqual(r.version(tool, tool + ' (PostgreSQL) 17.6\n'),'17.6')
            self.assertEqual(r.version(tool, tool + ' (PostgreSQL) 17.6 (Ubuntu)\n'),'17.6')
            for bad in ['17.5','17.60','18.0','17.6\nextra']:
                with self.subTest(tool=tool,bad=bad), self.assertRaises(r.Refused):
                    r.version(tool, tool + ' (PostgreSQL) ' + bad + '\n')

    def test_owned_container_guard(self):
        name='collect_ordinary_recovery_restore_'+'1'*12
        info=dict(Image=r.IMAGE, Config=dict(Labels={'collect.recovery.owner':name}),
            HostConfig=dict(NetworkMode='none',PortBindings={},Privileged=False,
                Tmpfs={'/var/lib/postgresql/collect-rehearsal':'rw,size=1073741824'},
                Binds=None,Devices=None,CapAdd=None))
        self.assertTrue(r.owned(info,name))
        for key,value in [('NetworkMode','host'),('PortBindings',{'5432/tcp':[{'HostPort':'5432'}]}),
                          ('Privileged',True),('Tmpfs',{}),('Binds',['/host:/target']),
                          ('Devices',[{}]),('CapAdd',['SYS_ADMIN'])]:
            with self.subTest(key=key):
                candidate=copy.deepcopy(info); candidate['HostConfig'][key]=value
                with self.assertRaises(r.Refused): r.owned(candidate,name)
        candidate=copy.deepcopy(info);candidate['Config']['Labels']['collect.recovery.owner']='other'
        with self.assertRaises(r.Refused):r.owned(candidate,name)

    def test_database_acl_parser(self):
        value=dict(name='postgres',owner='postgres',connection_limit=-1,
            acl=['=Tc/postgres','postgres=CTc/postgres','dashboard_user=CTc/postgres'])
        self.assertIn('grant TEMPORARY,CONNECT on database postgres to PUBLIC;',r.database_acl_sql(value))
        for entry in ['anon=X/postgres','anon=CTc/other','anon;select=CTc/postgres','anon=C*/postgres']:
            bad=copy.deepcopy(value);bad['acl']=[entry]
            with self.assertRaises(r.Refused):r.database_acl_sql(bad)


class ArchiveTests(unittest.TestCase):
    def test_preinstalled_extension_entries_keep_all_data_history_and_acl(self):
        toc='''; Archive created at test time
1; 1262 5 DATABASE - postgres postgres
2; 3079 100 EXTENSION - pgcrypto
3; 3079 101 EXTENSION - pg_net
4; 2615 102 SCHEMA - extensions postgres
5; 0 0 ACL - SCHEMA extensions postgres
6; 0 0 TABLE DATA supabase_migrations schema_migrations postgres
7; 0 0 TABLE DATA auth users postgres
8; 0 0 TABLE DATA public payments postgres
9; 0 0 ACL public TABLE payments postgres
'''
        catalog=dict(extensions=[['pgcrypto','1.3','extensions','postgres'],['pg_net','0.20.0','extensions','supabase_admin']])
        output,omitted=r.restore_list(toc,catalog)
        self.assertEqual(len(omitted),4)
        self.assertIn('5; 0 0 ACL - SCHEMA extensions postgres',output)
        for line in toc.splitlines()[6:]:self.assertIn(line,output)
        for incomplete in [toc.replace('TABLE DATA auth users','TABLE DATA auth unrelated'),
                           toc.replace('TABLE DATA supabase_migrations schema_migrations','TABLE DATA public fake')]:
            with self.assertRaises(r.Refused):r.restore_list(incomplete,catalog)

    def test_dump_integrity_and_substitutions(self):
        with tempfile.TemporaryDirectory() as temporary:
            base=Path(temporary).resolve();path=base/'synthetic.dump';body=b'PGDMPsynthetic-only-fixture'
            path.write_bytes(body);digest=r.sha(body)
            self.assertEqual(r.sealed_dump(path,digest),body)
            path.write_bytes(body+b'corrupt')
            with self.assertRaisesRegex(r.Refused,'DUMP_CONTENT_SEAL_CHANGED'):r.sealed_dump(path,digest)
            path.write_bytes(body);link=base/'link';link.symlink_to(path)
            with self.assertRaises(r.Refused):r.sealed_dump(link,digest)
            hard=base/'hard';os.link(path,hard)
            with self.assertRaises(r.Refused):r.sealed_dump(path,digest)


class RunnerTests(unittest.TestCase):
    def test_tool_output_and_wall_time_are_bounded(self):
        with tempfile.TemporaryDirectory() as temporary:
            runner=r.Runner(Path(temporary).resolve(),time.monotonic()+5)
            with self.assertRaisesRegex(r.Refused,'BOUNDED_TOOL_OUTPUT_LIMIT'):
                runner.call([sys.executable,'-c',"print('x'*4096)"],limit=100)
            with self.assertRaisesRegex(r.Refused,'BOUNDED_TOOL_DEADLINE'):
                runner.call([sys.executable,'-c','import time;time.sleep(2)'],timeout=.1)
            self.assertEqual(len(runner.records),2)
            self.assertTrue(all(row['status']=='refused' for row in runner.records))
            self.assertEqual(len((Path(temporary)/'commands.jsonl').read_text().splitlines()),2)

    def test_concurrent_input_and_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            runner=r.Runner(Path(temporary).resolve(),time.monotonic()+5)
            body=b'synthetic'*16384
            answer=runner.call([sys.executable,'-c','import sys;sys.stdout.buffer.write(sys.stdin.buffer.read())'],body)
            self.assertEqual(answer.stdout,body)
            self.assertEqual(runner.records[-1]['input_sha256'],r.sha(body))


class SourceRoleTests(unittest.TestCase):
    def fixture(self):
        return json.loads((HERE / 'source-role-globals.json').read_text())

    def test_observed_missing_role_has_one_exact_prerequisite(self):
        source = self.fixture(); target = copy.deepcopy(source)
        target['roles'].remove(r.SOURCE_ROLE)
        self.assertEqual(r.restore_role_plan(source, target), r.SOURCE_ROLE_SQL)
        self.assertEqual(r.SOURCE_ROLE_SQL, 'create role supabase_functions_admin with nosuperuser noinherit createrole nocreatedb login noreplication nobypassrls connection limit -1;')
        target['roles'].append(list(r.SOURCE_ROLE)); target['roles'].sort(key=lambda x:x[0])
        self.assertTrue(r.exact_role_globals(source, target))

    def test_already_exact_roles_require_no_mutation(self):
        source = self.fixture()
        self.assertEqual(r.restore_role_plan(source, copy.deepcopy(source)), '')

    def test_unknown_missing_and_extra_roles_refused(self):
        source = self.fixture()
        for name in ['pg_checkpoint', 'supabase_auth_admin']:
            target = copy.deepcopy(source)
            target['roles'] = [row for row in target['roles'] if row[0] != name]
            with self.subTest(name=name), self.assertRaises(r.Refused):
                r.restore_role_plan(source, target)
        target = copy.deepcopy(source); row = list(r.SOURCE_ROLE); row[0] = 'unexpected_role'
        target['roles'].append(row); target['roles'].sort(key=lambda x:x[0])
        with self.assertRaisesRegex(r.Refused, 'UNADMITTED_ROLE_IDENTITIES'):
            r.restore_role_plan(source, target)

    def test_every_observed_role_attribute_mismatch_refused(self):
        source = self.fixture()
        for name in ['supabase_functions_admin', 'postgres', 'pg_checkpoint']:
            for index in range(1, 11):
                target = copy.deepcopy(source)
                row = next(row for row in target['roles'] if row[0] == name)
                row[index] = not row[index] if index < 8 else 0 if index == 8 else 'infinity' if index == 9 else 'a'*64
                with self.subTest(name=name,index=index), self.assertRaisesRegex(r.Refused, 'SOURCE_ROLE_ATTRIBUTES_CHANGED'):
                    r.restore_role_plan(source, target)

    def test_unadmitted_source_role_attributes_refused(self):
        source = self.fixture(); next(row for row in source['roles'] if row[0] == r.SOURCE_ROLE[0])[2] = True
        with self.assertRaisesRegex(r.Refused, 'EXACT_OBSERVED_SOURCE_ROLE_COHORT_REQUIRED'):
            r.restore_role_plan(source, copy.deepcopy(source))

    def test_membership_and_setting_mismatches_refused(self):
        source = self.fixture()
        targets = []
        for category in ('memberships','settings'):
            target = copy.deepcopy(source); target[category].pop(); targets.append(target)
        target = copy.deepcopy(source); target['memberships'][0][3] = True; targets.append(target)
        target = copy.deepcopy(source); target['settings'][0][2] = 'a'*64; targets.append(target)
        for target in targets:
            with self.assertRaisesRegex(r.Refused, 'SOURCE_ROLE_MEMBERSHIPS_OR_SETTINGS_CHANGED'):
                r.restore_role_plan(source, target)
            with self.assertRaisesRegex(r.Refused, 'WHOLE_SOURCE_ROLE_GLOBALS_CHANGED'):
                r.exact_role_globals(source, target)

    def test_duplicate_malformed_and_unknown_global_rows_refused(self):
        source = self.fixture(); targets = []
        target = copy.deepcopy(source); target['roles'].insert(0,list(target['roles'][0])); targets.append(target)
        target = copy.deepcopy(source); target['roles'][0][1] = 0; targets.append(target)
        target = copy.deepcopy(source); target['memberships'][0][0] = 'unknown'; targets.append(target)
        target = copy.deepcopy(source); target['settings'].append(list(target['settings'][0])); targets.append(target)
        target = copy.deepcopy(source); target['unknown'] = []; targets.append(target)
        for target in targets:
            with self.assertRaises(r.Refused): r.role_globals(target)

    def test_readonly_query_reuses_exact_bound_catalog_expressions(self):
        inputs = json.loads((HERE / 'inputs.json').read_text())
        body = (Path(inputs['candidate']) / r.CATALOG).read_text()
        query = r.role_inventory_query(body)
        fragment = body[body.index(" 'roles',"):body.index(" 'relations',")].rstrip()[:-1]
        self.assertIn(fragment, query)
        self.assertTrue(query.startswith('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;'))
        self.assertTrue(query.endswith('COMMIT;\n'))
        self.assertNotIn('schema_migrations', query)
        for bad in [body.replace(" 'roles',", " 'renamed',"), body + " 'roles',", body.replace(" 'settings',", " 'renamed',")]:
            with self.assertRaises(r.Refused): r.role_inventory_query(bad)


class GraphQLSourceTests(unittest.TestCase):
    def fixture(self):
        inputs = json.loads((HERE / 'inputs.json').read_text())
        root = Path(inputs['candidate'])
        return ((root / '.cache/receipt-foundation-attempt8/schema-only.sql').read_text(),
                json.loads((root / 'reference/observed-output/ordinary_populated/predecessor-effective-catalog.json').read_text()))

    def test_exact_frozen_hook_body_identity_and_extension_membership(self):
        sql, catalog = self.fixture(); scope = r.graphql_source_scope(sql, catalog)
        self.assertEqual(scope['source_wrapper_body_sha256'], r.GRAPHQL_FUNCTION[11])
        self.assertEqual(scope['source_function_definition_sha256'], r.GRAPHQL_FUNCTION[12])
        self.assertEqual(scope['source_hook_body_sha256'], r.GRAPHQL_HOOK[11])
        self.assertTrue(scope['source_extension_membership_proven'])
        self.assertIn('create function graphql_public.graphql(', scope['create_function_sql'])
        self.assertNotIn('create or replace', scope['create_function_sql'])
        self.assertEqual(scope['dependencies'], r.GRAPHQL_DEPENDENCIES)

    def test_changed_unknown_duplicate_hook_or_wrapper_refused(self):
        sql, catalog = self.fixture()
        for bad in [sql.replace('query := query,', 'query := null,', 1),
                    sql.replace('create or replace function graphql_public.graphql(', 'create or replace function graphql_public.unknown(', 1),
                    sql.replace('            language sql\n        as $$', '            language plpgsql\n        as $$', 1),
                    sql + '\n' + sql[sql.index('CREATE FUNCTION extensions.grant_pg_graphql_access()'):sql.index("COMMENT ON FUNCTION extensions.grant_pg_graphql_access()")]]:
            with self.assertRaises(r.Refused): r.graphql_source_scope(bad, catalog)

    def test_unknown_source_identity_attributes_and_provenance_refused(self):
        sql, catalog = self.fixture(); candidates = []
        for index,value in [(2,'other text'),(4,'postgres'),(10,[]),(11,'a'*64),(12,'a'*64)]:
            bad = copy.deepcopy(catalog); next(row for row in bad['functions'] if row[:2]==r.GRAPHQL_ID[:2])[index] = value; candidates.append(bad)
        bad = copy.deepcopy(catalog); row = list(r.GRAPHQL_FUNCTION); row[2]='unknown text'; bad['functions'].append(row); candidates.append(bad)
        bad = copy.deepcopy(catalog); bad['dependencies'].remove(r.GRAPHQL_DEPENDENCIES[0]); candidates.append(bad)
        bad = copy.deepcopy(catalog); next(row for row in bad['dependencies'] if row==r.GRAPHQL_DEPENDENCIES[0])[-1]='other_extension'; candidates.append(bad)
        bad = copy.deepcopy(catalog); next(row for row in bad['event_triggers'] if row[0]==r.GRAPHQL_TRIGGER[0])[5]=['CREATE EXTENSION']; candidates.append(bad)
        for bad in candidates:
            with self.assertRaisesRegex(r.Refused,'EXACT_DECLARED_GRAPHQL_SOURCE_PROVENANCE_REQUIRED'):
                r.graphql_source_scope(sql,bad)

    def test_restore_plan_is_exact_and_existing_mismatch_refuses(self):
        sql, catalog = self.fixture(); scope = r.graphql_source_scope(sql,catalog)
        empty = dict(schema=None,functions=[],dependencies=[])
        expected = '\n'.join([scope['create_schema_sql'],scope['create_function_sql'],r.GRAPHQL_MEMBERSHIP_SQL])
        self.assertEqual(r.graphql_restore_plan(scope,empty),expected)
        state = dict(schema=list(r.GRAPHQL_SCHEMA),functions=[copy.deepcopy(r.GRAPHQL_FUNCTION)],dependencies=copy.deepcopy(r.GRAPHQL_DEPENDENCIES))
        self.assertEqual(r.graphql_restore_plan(scope,state),'')
        state['functions'][0][10]=['=X/supabase_admin','supabase_admin=X/supabase_admin']
        state['dependencies']=[copy.deepcopy(r.GRAPHQL_DEPENDENCIES[1])]
        self.assertEqual(r.graphql_restore_plan(scope,state),r.GRAPHQL_MEMBERSHIP_SQL)
        for index,value in [(2,'other text'),(4,'postgres'),(10,['unknown=X/supabase_admin']),(11,'a'*64),(12,'a'*64)]:
            bad=copy.deepcopy(state);bad['functions'][0][index]=value
            with self.assertRaises(r.Refused):r.graphql_restore_plan(scope,bad)
        bad=copy.deepcopy(state);bad['dependencies'][0][-1]='unknown'
        with self.assertRaises(r.Refused):r.graphql_restore_plan(scope,bad)
        bad=copy.deepcopy(state);bad['functions'].append(copy.deepcopy(r.GRAPHQL_FUNCTION))
        with self.assertRaises(r.Refused):r.graphql_restore_plan(scope,bad)

    def test_forged_scope_sql_or_provenance_refused(self):
        sql,catalog=self.fixture();scope=r.graphql_source_scope(sql,catalog)
        for key,value in [('create_schema_sql','create schema unknown;'),('create_function_sql','select 1;'),
                          ('extension_membership_sql','alter extension pg_graphql add function unknown();'),
                          ('dependencies',[]),('hook',[]),('event_trigger',[])]:
            bad=copy.deepcopy(scope);bad[key]=value
            with self.assertRaises(r.Refused):r.graphql_restore_plan(bad,dict(schema=None,functions=[],dependencies=[]))

    def test_toc_comments_only_exact_schema_and_keeps_wrapper_acl(self):
        sql,catalog=self.fixture();scope=r.graphql_source_scope(sql,catalog)
        toc='''1; 3079 100 EXTENSION - pg_graphql
2; 2615 101 SCHEMA - graphql_public supabase_admin
3; 0 0 ACL graphql_public FUNCTION graphql("operationName" text, query text, variables jsonb, extensions jsonb) supabase_admin
4; 0 0 ACL - SCHEMA graphql_public supabase_admin
5; 0 0 TABLE DATA supabase_migrations schema_migrations postgres
6; 0 0 TABLE DATA auth users postgres
7; 0 0 TABLE DATA public payments postgres
'''
        output,omitted=r.restore_list(toc,catalog,scope)
        self.assertEqual(len(omitted),2)
        for line in toc.splitlines()[2:]:self.assertIn(line+'\n',output)
        self.assertIn('; preinstalled exact frozen prerequisite: 2;',output)
        for bad in [toc.replace('SCHEMA - graphql_public supabase_admin','SCHEMA - graphql_public postgres'),
                    toc.replace('graphql("operationName" text','graphql(unknown text'),
                    toc.replace('2; 2615 101 SCHEMA - graphql_public supabase_admin\n',''),
                    toc+'8; 1255 101 FUNCTION graphql_public graphql(unknown text) supabase_admin\n']:
            with self.assertRaises(r.Refused):r.restore_list(bad,catalog,scope)

    def test_readonly_function_projection_keeps_exact_expressions(self):
        inputs=json.loads((HERE/'inputs.json').read_text());body=(Path(inputs['candidate'])/r.CATALOG).read_text()
        query=r.graphql_inventory_query(body)
        self.assertTrue(query.startswith(''+body[:body.index('\nSELECT jsonb_build_object(')]))
        self.assertIn(body[body.index(" 'functions',"):body.index(" 'policies',")].rstrip().rstrip(','),query)
        self.assertIn(body[body.index(" 'dependencies',"):body.index('\n);\nCOMMIT;')],query)
        self.assertNotIn('FROM supabase_migrations.schema_migrations',query)
        self.assertTrue(query.endswith('COMMIT;\n'))
        for bad in [body.replace(" 'functions',"," 'renamed',"),body+" 'functions',"]:
            with self.assertRaises(r.Refused):r.graphql_inventory_query(bad)
        with self.assertRaises(r.Refused):r.graphql_state(dict(schemas=[[]],functions=[],dependencies=[]))


if __name__=='__main__':unittest.main()
