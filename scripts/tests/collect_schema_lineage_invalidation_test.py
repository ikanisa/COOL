"""Focused conservative parser/lineage tests; no SQL or historical fixtures."""
import ast
import hashlib
import importlib.util
from pathlib import Path
import sys
import unittest

HERE=Path(__file__).resolve().parents[2]
ROOT=next(p for p in (HERE,*HERE.parents) if (p/'supabase/migrations').is_dir())
spec=importlib.util.spec_from_file_location('mapper_under_test',HERE/'scripts/audits/collect_schema_domain_map.py')
M=importlib.util.module_from_spec(spec);sys.modules[spec.name]=M;spec.loader.exec_module(M)

def definition(schema='public',name='source',body='SELECT p_id::text;'):
    return f'CREATE FUNCTION {schema}.{name}(p_id uuid) RETURNS text LANGUAGE sql AS $fn${body}$fn$;'

def inventory(chunks, fenced=True):
    definitions=[];alterations=[];fences=[]
    for i,text in enumerate(chunks):
        version=f'{i:014d}';path=f'synthetic-{i}.sql'
        definitions.extend(M.sql_definitions(text,path,version))
        alterations.extend(M.sql_static_alterations(text,path,version))
        fences.extend(M.sql_lineage_uncertainty(text,path,version))
    return M.sql_static_lineage(definitions,[*alterations,*(fences if fenced else [])]),definitions,fences

class InvalidationTests(unittest.TestCase):
    def test_qualified_unsupported_alter_invalidates_source_and_destination(self):
        sql=definition()+definition(name='renamed')+'ALTER FUNCTION public.source(pg_catalog.uuid) RENAME TO renamed;'
        state,_,fences=inventory([sql])
        self.assertEqual(state,{})
        self.assertEqual({(f['schema'],f['name']) for f in fences},{('public','source'),('public','renamed')})
        self.assertTrue(all(f['source_migration_sha256']==M.sha(sql.encode()) for f in fences))

    def test_unsupported_set_schema_invalidates_both_names(self):
        sql=definition()+definition(schema='elsewhere')+'ALTER FUNCTION public.source(custom_type) SET SCHEMA elsewhere;'
        state,_,fences=inventory([sql])
        self.assertEqual(state,{})
        self.assertEqual({(f['schema'],f['name']) for f in fences},{('public','source'),('elsewhere','source')})

    def test_unqualified_alter_does_not_assume_search_path(self):
        sql=definition()+definition(schema='elsewhere')+'ALTER FUNCTION source(uuid) RENAME TO renamed;'
        state,_,fences=inventory([sql])
        self.assertEqual(state,{})
        self.assertEqual({(f['schema'],f['name']) for f in fences},{(None,'source'),(None,'renamed')})

    def test_first_do_routine_effect_does_not_retain_hash_equal_chain(self):
        chunks=[definition(),'DO $$BEGIN PERFORM public.some_unreviewed_routine();END$$; ALTER FUNCTION public.source(uuid) RENAME TO renamed;']
        baseline,_,_=inventory(chunks,False)
        self.assertIn(('public','renamed',('uuid',)),baseline)
        state,defs,fences=inventory(chunks)
        self.assertEqual(state,{})
        self.assertEqual(defs[0]['prosrc_sha256'],baseline[('public','renamed',('uuid',))]['prosrc_sha256'])
        self.assertEqual(fences[0]['statement_offset'],0)

    def test_intervening_do_execute_invalidates_static_candidate(self):
        text=definition()+"DO $$BEGIN EXECUTE opaque_sql;END$$; ALTER FUNCTION public.source(uuid) RENAME TO renamed;"
        state,defs,fences=inventory([text])
        self.assertEqual(state,{})
        self.assertGreater(fences[0]['statement_offset'],defs[0]['definition_offset'])
        self.assertEqual(fences[0]['operation'],'drop-all')

    def test_all_unreviewed_do_invocations_and_side_effects_are_opaque(self):
        for body in ('PERFORM public.unknown();','SELECT public.unknown();','CALL public.unknown();',
                     'IF public.unknown() THEN NULL;END IF;','UPDATE public.x SET value=1;',
                     'EXECUTE format(\'REVOKE ALL ON FUNCTION %s FROM public\',identity);','NULL;'):
            state,_,fences=inventory([definition(),'DO $$BEGIN '+body+'END$$;'])
            self.assertEqual(state,{})
            self.assertEqual(len(fences),1)

    def test_top_level_execute_and_call_invalidate_at_first_token(self):
        for sql in ('EXECUTE unknown_statement;','CALL public.unknown();'):
            state,_,fences=inventory([definition(),sql])
            self.assertEqual(state,{})
            self.assertEqual(fences[0]['statement_offset'],0)

    def test_safe_literal_static_and_quoted_or_commented_words_are_unaffected(self):
        sql=definition(body="SELECT 'DO EXECUTE CALL ALTER FUNCTION';")+'-- DO $$bad$$;\nALTER FUNCTION public.source(uuid) RENAME TO renamed;'
        state,defs,fences=inventory([sql])
        self.assertEqual(fences,[])
        self.assertEqual(state[('public','renamed',('uuid',))]['prosrc_sha256'],defs[0]['prosrc_sha256'])
        self.assertEqual(len(state[('public','renamed',('uuid',))]['static_lineage']),1)
        # ON CONFLICT DO and trigger EXECUTE FUNCTION are not command starts.
        self.assertEqual(M.sql_lineage_uncertainty('INSERT INTO public.x VALUES(1) ON CONFLICT DO NOTHING; CREATE TRIGGER t BEFORE UPDATE ON public.x FOR EACH ROW EXECUTE FUNCTION public.f();','x','1'),[])

    def test_fresh_explicit_declaration_can_start_new_chain_after_barrier(self):
        chunks=[definition(body='SELECT old_body();'),'DO $$BEGIN PERFORM public.unknown();END$$;',
                definition(body='SELECT fresh_body();')+'ALTER FUNCTION public.source(uuid) RENAME TO renamed;']
        state,defs,_=inventory(chunks)
        current=state[('public','renamed',('uuid',))]
        self.assertEqual(current['path'],'synthetic-2.sql')
        self.assertEqual(current['prosrc_sha256'],defs[-1]['prosrc_sha256'])
        self.assertNotEqual(current['prosrc_sha256'],defs[0]['prosrc_sha256'])

    def test_unknown_or_unterminated_do_refuses(self):
        for sql in ('DO $$BEGIN PERFORM public.unknown();END','DO LANGUAGE other $$BEGIN END$$;',"DO 'BEGIN END"):
            with self.assertRaisesRegex(ValueError,'unknown or unterminated DO'):
                M.sql_lineage_uncertainty(sql,'x','1')

    def test_original49_bytes_and_method_assertion_asts_are_unchanged(self):
        original=(ROOT/'scripts/tests/collect_schema_domain_map_test.py').read_bytes()
        copied=(HERE/'scripts/tests/collect_schema_domain_map_test.py').read_bytes()
        self.assertEqual(copied,original)
        methods=lambda raw:{n.name:ast.dump(n,include_attributes=False) for n in ast.walk(ast.parse(raw)) if isinstance(n,ast.FunctionDef) and n.name.startswith('test_')}
        self.assertEqual(methods(copied),methods(original));self.assertEqual(len(methods(copied)),49)
        self.assertEqual(hashlib.sha256(original).hexdigest(),'ed9698015a6b290bf4af3f877fa6ca5ce37da9555ce175f76e3ecfa06f990ce4')

if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(InvalidationTests))
    print(f'tests={result.testsRun} errors={len(result.errors)} failures={len(result.failures)}')
    raise SystemExit(0 if result.wasSuccessful() and result.testsRun==11 and not result.skipped else 1)
