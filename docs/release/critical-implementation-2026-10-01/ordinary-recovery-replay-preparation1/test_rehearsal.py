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


if __name__=='__main__':unittest.main()
