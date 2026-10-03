#!/usr/bin/env python3
"""Private synthetic SQL fixtures only; no database or SQL execution."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('schema3_original_tests',HERE/'original_tests.py')
original=importlib.util.module_from_spec(spec);spec.loader.exec_module(original)
M=original.M
tempfile.tempdir='/private/tmp'

def function(name,body,schema='public',arguments='',kind='f'):
    row=list(original.catalog()['functions'][0]);row[0]=schema;row[1]=name;row[2]=arguments;row[3]=kind;row[11]=M.sha(body.encode())
    return row

class LineageAndGapTests(unittest.TestCase):
    def build(self,root,sql,rows):
        p=original.AdmissionAndCoverageTests().setup_tree(root)
        source=root/'supabase/migrations/20260101000000_first.sql';source.write_text(sql)
        d=original.catalog();d['functions']=rows
        d['schemas'].append(['collect_hybrid','postgres',[]])
        p.write_text(json.dumps(d));p.with_name('catalog-peer.json').write_bytes(p.read_bytes())
        out=root/'output';M.build(root,[p,p.with_name('catalog-peer.json')],out)
        return json.loads((out/'schema-domain-map.json').read_text()),out

    def find(self,doc,name):return next(o for o in doc['objects'] if o['kind']=='function' and o['name']==name)

    def test_rename_then_recreate_original_preserves_exact_declaration_and_alter(self):
        sql='CREATE FUNCTION public.old() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql;\nALTER FUNCTION public.old() RENAME TO saved;\nCREATE FUNCTION public.old() RETURNS int AS $$SELECT 2;$$ LANGUAGE sql;'
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('saved','SELECT 1;'),function('old','SELECT 2;')])
            saved=self.find(doc,'saved');old=self.find(doc,'old')
            self.assertEqual(saved['source_status'],'catalog-prosrc-hash-matched-static-lineage')
            evidence=saved['matched_body_sources'][0]
            self.assertEqual((evidence['schema'],evidence['name']),('public','old'))
            self.assertEqual(evidence['declaration_sha256'],M.sha(sql.split('\n')[0].encode()))
            alter=evidence['static_lineage'][0]
            self.assertEqual(alter['statement_sha256'],M.sha(sql.split('\n')[1].encode()))
            self.assertEqual(alter['line'],2)
            self.assertEqual(alter['path'],'supabase/migrations/20260101000000_first.sql')
            self.assertEqual(old['matched_body_sources'][0]['prosrc_sha256'],M.sha(b'SELECT 2;'))
            self.assertEqual(doc['summary']['functions_with_exact_static_lineage_body_hash_match'],1)

    def test_set_schema_preserves_quoted_identifier_case(self):
        sql='CREATE FUNCTION "public"."Mixed"() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql;\nALTER FUNCTION "public"."Mixed"() SET SCHEMA "collect_hybrid";'
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('Mixed','SELECT 1;','collect_hybrid')])
            obj=self.find(doc,'Mixed');self.assertEqual(obj['source_status'],'catalog-prosrc-hash-matched-static-lineage')
            self.assertEqual(obj['matched_body_sources'][0]['static_lineage'][0]['operation'],'set-schema')

    def test_unqualified_alter_does_not_infer_search_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),'CREATE FUNCTION public.old() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; ALTER FUNCTION old() RENAME TO saved;',[function('saved','SELECT 1;')])
            self.assertEqual(self.find(doc,'saved')['source_status'],'no-exact-body-source-match')

    def test_unrelated_identical_body_remains_unmatched(self):
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),'CREATE FUNCTION public.old() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql;',[function('saved','SELECT 1;')])
            obj=self.find(doc,'saved');self.assertEqual(obj['source_status'],'no-exact-body-source-match')
            review=obj['source_match_review'];self.assertTrue(review['same_body_other_name_candidates'])
            self.assertFalse(review['same_body_other_name_is_match'])

    def test_overload_exact_signature_selects_one_declaration(self):
        sql='CREATE FUNCTION public.old(p_id uuid) RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; CREATE FUNCTION public.old(p_id text) RETURNS int AS $$SELECT 2;$$ LANGUAGE sql; ALTER FUNCTION public.old(uuid) RENAME TO saved;'
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('saved','SELECT 1;',arguments='p_id uuid'),function('old','SELECT 2;',arguments='p_id text')])
            self.assertEqual(self.find(doc,'saved')['matched_body_sources'][0]['signature_types'],['uuid'])
            self.assertEqual(self.find(doc,'old')['source_status'],'catalog-prosrc-hash-matched')

    def test_unsupported_signature_does_not_guess_overload(self):
        sql='CREATE FUNCTION public.old(p_id "OddType") RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; ALTER FUNCTION public.old(uuid) RENAME TO saved;'
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('saved','SELECT 1;',arguments='p_id uuid')])
            self.assertEqual(self.find(doc,'saved')['source_status'],'no-exact-body-source-match')

    def test_final_body_hash_required_after_static_rename(self):
        sql='CREATE FUNCTION public.old() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; ALTER FUNCTION public.old() RENAME TO saved;'
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('saved','SELECT 2;')])
            obj=self.find(doc,'saved');self.assertEqual(obj['source_status'],'no-exact-body-source-match')
            self.assertEqual(obj['source_match_review']['reason'],'static-lineage-body-hash-mismatch')

    def test_generated_wrapper_stays_unresolved_with_no_literal_definition(self):
        sql="DO $do$ BEGIN EXECUTE 'CREATE FUNCTION public.saved() RETURNS int AS $q$SELECT 1;$q$ LANGUAGE sql'; END $do$;"
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('saved','SELECT 1;')])
            obj=self.find(doc,'saved');self.assertEqual(obj['source_status'],'no-exact-body-source-match')
            self.assertEqual(obj['source_match_review']['reason'],'no-literal-effective-name-definition')
            self.assertFalse(obj['source_match_review']['dynamic_SQL_evaluation_performed'])

    def test_patched_body_reports_literal_candidates_without_acceptance(self):
        sql="CREATE FUNCTION public.saved() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; DO $do$ BEGIN EXECUTE replace(pg_get_functiondef('public.saved()'::regprocedure),'1','2'); END $do$;"
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('saved','SELECT 2;')])
            obj=self.find(doc,'saved');self.assertEqual(obj['source_status'],'no-exact-body-source-match')
            review=obj['source_match_review'];self.assertEqual(review['reason'],'literal-effective-name-body-hash-mismatch')
            self.assertEqual(review['literal_effective_name_candidates'][0]['prosrc_sha256'],M.sha(b'SELECT 1;'))

    def test_drop_invalidates_prior_lineage(self):
        sql='CREATE FUNCTION public.old() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; DROP FUNCTION public.old(); ALTER FUNCTION public.old() RENAME TO saved;'
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('saved','SELECT 1;')])
            self.assertEqual(self.find(doc,'saved')['source_status'],'no-exact-body-source-match')

    def test_procedure_cannot_supply_function_lineage(self):
        sql='CREATE PROCEDURE public.old() AS $$SELECT 1;$$ LANGUAGE sql; ALTER FUNCTION public.old() RENAME TO saved;'
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('saved','SELECT 1;')])
            self.assertEqual(self.find(doc,'saved')['source_status'],'no-exact-body-source-match')

    def test_reasoned_gap_tamper_is_rejected_by_full_semantic_readback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);_,out=self.build(root,'SELECT 1;',[function('saved','SELECT 1;')])
            gaps=out/'gaps.json';data=json.loads(gaps.read_text());data['function_body_match_review'][0]['reason']='completed'
            gaps.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError,'semantic recomputation mismatch: gaps.json'):M.verify_bundle(root,out)

if __name__=='__main__':
    before={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in (HERE/'collect_schema_domain_map.py',HERE/'original_tests.py',Path(__file__).resolve())}
    suite=unittest.TestSuite([unittest.TestLoader().loadTestsFromModule(original),unittest.TestLoader().loadTestsFromTestCase(LineageAndGapTests)])
    if suite.countTestCases()!=44:raise ValueError('expected unchanged32 plus focused12 tests')
    start=time.monotonic();result=unittest.TextTestRunner(verbosity=2).run(suite)
    after={path:hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in before}
    with (HERE/'tests-result.json').open('x') as out:
        json.dump(dict(tests=result.testsRun,original_cases=32,focused_cases=12,failures=len(result.failures),errors=len(result.errors),skips=len(result.skipped),seconds=round(time.monotonic()-start,6),before=before,after=after,inputs_unchanged=before==after,fixture_parent='/private/tmp',SQL_or_database_execution=False),out,indent=2,sort_keys=True);out.write('\n')
    raise SystemExit(0 if result.wasSuccessful() and not result.skipped and before==after else 1)
