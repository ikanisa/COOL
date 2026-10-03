#!/usr/bin/env python3
"""Affected source-lineage refusals; no SQL, provider actions or maintained writes."""
import ast
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[2]
ROOT = next(parent for parent in (HERE, *HERE.parents) if (parent / 'supabase/migrations').is_dir())
CASES = Path(__file__).with_name('collect_schema_function_lineage_cases.json')


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


M = module('private_mapper', HERE / 'scripts/audits/collect_schema_domain_map.py')
L = module('private_lineage', HERE / 'scripts/audits/collect_schema_function_lineage.py')


class LineageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources, cls.definitions, cls.alterations = {}, [], []
        for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
            raw = path.read_bytes(); text = raw.decode(); relative = path.relative_to(ROOT).as_posix()
            version = path.name[:14]
            cls.sources[relative] = dict(text=text, version=version, sha256=M.sha(raw))
            cls.definitions.extend(M.sql_definitions(text, relative, version))
            cls.alterations.extend(M.sql_static_alterations(text, relative, version))
        # The controlled parser fixture removes unreviewed DO blocks without
        # shifting any literal declaration offsets. It is not current209 proof.
        cls.controlled_sources = copy.deepcopy(cls.sources)
        for path, source in cls.controlled_sources.items():
            if path in L.REVIEWED_PROGRAMS:
                continue
            chars = list(source['text'])
            tokens = M.lex(source['text'], sql=True)
            for i, token in enumerate(tokens[:-1]):
                if token.kind == 'id' and token.value.lower() == 'do' and tokens[i+1].kind == 'string':
                    for j in range(token.start, tokens[i+1].end):
                        if chars[j] != '\n':
                            chars[j] = ' '
            source['text'] = ''.join(chars); source['sha256'] = M.sha(source['text'].encode())

    def lineage(self, definitions=None, alterations=None, sources=None):
        return L.reviewed_transform_lineage(M, self.controlled_sources if sources is None else sources,
            self.definitions if definitions is None else definitions,
            self.alterations if alterations is None else alterations)

    def test_self_contained34_case_hashes_and_controlled_lineage(self):
        fixture = json.loads(CASES.read_text())
        self.assertEqual(fixture['format'], 'collect-current209-review-lineage-cases-v1')
        self.assertEqual(fixture['provenance']['source_migration_count'], 209)
        expected = {(r[0],r[1],tuple(r[2])):r[3] for r in fixture['cases']}
        self.assertEqual(len(expected), 34)
        state = self.lineage()
        for key, digest in expected.items():
            self.assertEqual(state[key]['prosrc_sha256'], digest)
            self.assertEqual(M.sha(state[key]['body'].encode()), digest)
            self.assertFalse(state[key]['SQL_evaluation_performed'])

    def test_current209_retains_only_uninterrupted_fixture_case(self):
        expected = {(r[0],r[1],tuple(r[2])):r[3] for r in json.loads(CASES.read_text())['cases']}
        state = self.lineage(sources=self.sources)
        retained = {k:v for k,v in state.items() if k in expected and v['prosrc_sha256'] == expected[k]}
        self.assertEqual({key[:2] for key in retained}, {('public','admin_list_receipt_operation_evidence_v1')})
        self.assertEqual(len(retained), 1)
        self.assertTrue(any(u['operation'] == 'drop-all' for u in state.uncertainty))
        self.assertTrue(any(u['operation'] == 'reviewed-transform-withheld' for u in state.uncertainty))

    def test_changed_reviewed_source_program_refuses(self):
        path = next(iter(L.REVIEWED_PROGRAMS))
        source = copy.deepcopy(self.sources[path]); source['text'] += '\n-- changed program\n'
        source['sha256'] = M.sha(source['text'].encode())
        with self.assertRaisesRegex(ValueError, 'new lineage review required'):
            self.lineage(definitions=[], alterations=[], sources={path:source})

    def test_missing_or_overloaded_roster_predecessor_refuses(self):
        absent = [d for d in self.definitions if d['name'] != 'admin_get_roster_import']
        state = self.lineage(definitions=absent)
        self.assertNotIn(('public','admin_get_roster_import',('uuid',)), state)
        self.assertTrue(any(u['names'] == [('public','admin_get_roster_import')] and 'missing' in u['reason'] for u in state.uncertainty))
        original = next(d for d in self.definitions if d['schema'] == 'public' and d['name'] == 'admin_get_roster_import')
        extra = {**original, 'signature_types':('text',)}
        state = self.lineage(definitions=[*self.definitions, extra])
        self.assertNotIn(('public','admin_get_roster_import',('uuid',)), state)
        self.assertTrue(any(u['names'] == [('public','admin_get_roster_import')] and 'ambiguous' in u['reason'] for u in state.uncertainty))

    def test_drop_before_installer_invalidates_predecessor(self):
        sql = 'DROP FUNCTION public.admin_get_roster_import(uuid);'
        drop = M.sql_static_alterations(sql, 'synthetic-before.sql', '20260930165000')
        state = self.lineage(alterations=[*self.alterations, *drop])
        self.assertNotIn(('public','admin_get_roster_import',('uuid',)), state)
        self.assertTrue(any(u['names'] == [('public','admin_get_roster_import')] and 'invalidated' in u['reason'] for u in state.uncertainty))

    def test_later_multi_target_drop_invalidates_all_derived_overloads(self):
        sql = 'DROP FUNCTION public.admin_get_roster_import(uuid), collect_ops.receipt_exception_base_refresh_source(text,uuid);'
        drop = M.sql_static_alterations(sql, 'synthetic-after.sql', '20261003000000')
        state = self.lineage(alterations=[*self.alterations, *drop])
        self.assertFalse(any(key[:2] in {('public', 'admin_get_roster_import'), ('collect_ops', 'receipt_exception_base_refresh_source')} for key in state))

    def test_later_unknown_signature_invalidates_old_derived_name(self):
        unknown = dict(path='synthetic-after.sql', version='20261003000000', line=1,
            definition_offset=0, body_offset=0, schema='public', name='admin_get_roster_import',
            signature_types=None, routine_kind='function', body='changed', prosrc_sha256=M.sha(b'changed'), declaration_sha256='a'*64)
        state = self.lineage(definitions=[*self.definitions, unknown])
        self.assertFalse(any(key[:2] == ('public', 'admin_get_roster_import') for key in state))

    def test_later_known_definition_replaces_derived_body(self):
        later = next(d for d in self.definitions if d['schema'] == 'public' and d['name'] == 'admin_get_roster_import')
        later = {**later, 'version':'20261003000000', 'body':'different body', 'prosrc_sha256':M.sha(b'different body')}
        state = self.lineage(definitions=[*self.definitions, later])
        self.assertNotIn(('public', 'admin_get_roster_import', ('uuid',)), state)

    def test_patch_absent_or_duplicate_needle_refuses(self):
        for body in ('needle absent', 'abc abc'):
            with self.assertRaisesRegex(ValueError, 'absent or repeated'):
                L.apply_patch_exact(body, 'abc', 'replacement')

    def test_nonliteral_patch_or_unreviewed_escape_refuses(self):
        for expression in ("lower('abc')", "format('%s','abc')", "needle||current_setting('x')", "E'\\r'"):
            with self.assertRaises(ValueError):
                L.literal_expression(M, expression, 'bound needle')

    def test_unknown_modes_types_and_quoted_or_duplicate_names_refuse(self):
        self.assertEqual(L.signature(M, 'p_at timestamptz'), ('timestamp with time zone',))
        for value in ('OUT p_id uuid', 'p_id collect_hybrid.custom_type', 'p_ids uuid[]'):
            with self.assertRaises(ValueError):
                L.signature(M, value)
        for value in ('"p_id" uuid', 'p_id uuid,p_id text'):
            with self.assertRaises(ValueError):
                L.named_arguments(M, value)

    def test_unknown_wrapper_branch_identifier_and_template_refuse(self):
        text = self.sources[next(iter(L.REVIEWED_PROGRAMS))]['text']
        _, template, expiry = L.roster_template(text)
        with self.assertRaises(ValueError):
            L.wrapper_body('admin_get_roster_import', ['p_actor_id'], template, expiry)
        with self.assertRaises(ValueError):
            L.wrapper_body('quoted-name', ['p_import_id'], template, expiry)
        with self.assertRaises(ValueError):
            L.roster_template(text.replace('begin %s return collect_hybrid.%I(%s)', 'begin %s return collect_hybrid.%L(%s)'))

    def synthetic_source(self, sql, version='20261003000000'):
        sources = copy.deepcopy(self.controlled_sources)
        sources['synthetic.sql'] = dict(text=sql,version=version,sha256=M.sha(sql.encode()))
        return sources

    def test_qualified_unknown_alter_invalidates_source_and_destination(self):
        sql = 'ALTER FUNCTION public.admin_get_roster_import(pg_catalog.uuid) RENAME TO another_name;'
        key = ('public','admin_get_roster_import',('uuid',))
        self.assertIn(key, self.lineage())
        self.assertEqual(M.sql_static_alterations(sql,'synthetic.sql','20261003000000'), [])
        state = self.lineage(sources=self.synthetic_source(sql))
        self.assertNotIn(key,state)
        self.assertTrue(any(u['names'] == [('public','admin_get_roster_import'),('public','another_name')] for u in state.uncertainty))
        moved = L.unsupported_alter_fences(M, sql.replace('RENAME TO another_name','SET SCHEMA elsewhere'),'synthetic.sql','20261003000000')
        self.assertEqual(moved[0]['names'], [('public','admin_get_roster_import'),('elsewhere','admin_get_roster_import')])

    def test_opaque_do_cannot_revive_matching_final_hash(self):
        sql = "DO $$ BEGIN EXECUTE 'CREATE OR REPLACE FUNCTION public.admin_get_roster_import(uuid) RETURNS jsonb LANGUAGE sql AS $x$SELECT null::jsonb$x$'; EXECUTE opaque_sql; END $$;"
        key = ('public','admin_get_roster_import',('uuid',))
        original = self.lineage()[key]
        state = self.lineage(sources=self.synthetic_source(sql))
        self.assertNotIn(key,state)
        self.assertEqual(original['prosrc_sha256'], M.sha(original['body'].encode()))
        self.assertTrue(any(u['operation']=='drop-all' and 'dynamic' in u['reason'] for u in state.uncertainty))
        # Supplying the unchanged catalog/body hash does not repair source order.
        self.assertFalse(any(v['prosrc_sha256']==original['prosrc_sha256'] for v in state.values()))

    def test_opaque_before_reviewed_program_withholds_transform(self):
        sql = 'DO $$ BEGIN EXECUTE opaque_sql; END $$;'
        state = self.lineage(sources=self.synthetic_source(sql,'20260930165000'))
        self.assertNotIn(('public','admin_get_roster_import',('uuid',)),state)
        self.assertTrue(any(u['operation']=='reviewed-transform-withheld' and u['names']==[('public','admin_get_roster_import')] for u in state.uncertainty))

    def test_constant_copy_effect_scope_does_not_taint_unrelated_names(self):
        sql = "DO $$DECLARE definition text;BEGIN SELECT pg_get_functiondef('collect_ops.run_receipt_exception_schedule()'::regprocedure) INTO definition;definition:=replace(definition,'collect_ops.run_receipt_exception_schedule','collect_ops.receipt_transport_base_schedule');EXECUTE definition;END$$;"
        state = self.lineage(sources=self.synthetic_source(sql))
        self.assertIn(('public','admin_get_roster_import',('uuid',)),state)
        scope = next(u for u in state.uncertainty if u['path']=='synthetic.sql')
        self.assertEqual(scope['operation'],'drop-names')
        self.assertEqual(scope['names'], [('collect_ops','run_receipt_exception_schedule'),('collect_ops','receipt_transport_base_schedule')])
        self.assertFalse(any(u['operation']=='drop-all' for u in state.uncertainty))

    def test_fragment_or_unknown_execute_effects_are_unbounded(self):
        for sql in (
            "DO $$BEGIN EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public', identity);END$$;",
            "DO $$BEGIN EXECUTE format('REVOKE ALL ON TABLE %I FROM public', name)||opaque_sql;END$$;",
            "DO $$BEGIN EXECUTE 'GRANT SELECT ON TABLE public.x TO public; DO $nested$BEGIN EXECUTE opaque_sql;END$nested$';END$$;",
            "DO $$BEGIN EXECUTE 'INSERT INTO public.x SELECT body_mutating_function()';END$$;",
            "DO $$BEGIN EXECUTE opaque_sql;END$$;",
            'EXECUTE dynamic_statement;'):
            state = self.lineage(sources=self.synthetic_source(sql))
            self.assertEqual(state,{})
            self.assertTrue(any(u['operation']=='drop-all' for u in state.uncertainty))

    def test_unclosed_or_unknown_do_syntax_refuses(self):
        for sql in ('DO $$BEGIN EXECUTE opaque_sql;END', 'DO LANGUAGE other $$BEGIN END$$;', "DO 'BEGIN END;"):
            with self.assertRaisesRegex(ValueError,'DO syntax or unterminated'):
                self.lineage(sources=self.synthetic_source(sql))

    def test_alias_normalization_refuses_qualified_quoted_and_custom_types_first(self):
        for value in ('p_at pg_catalog.timestamptz', 'p_at "timestamptz"', '"p_at" timestamptz', 'p_at custom_timestamptz', 'p_at custom.timestamptz'):
            with patch.object(L.re,'sub',side_effect=AssertionError('alias conversion reached before refusal')):
                with self.assertRaises(ValueError):
                    L.signature(M,value)
        self.assertEqual(L.signature(M,'p_at timestamptz DEFAULT NULL'),('timestamp with time zone',))

    def test_loaded_helper_is_exact_captured_manifest_bytes(self):
        captured = b"MARKER = 'manifested'\n"
        with patch.object(Path,'read_bytes',side_effect=AssertionError('path re-read forbidden')):
            helper = M.load_reviewed_lineage_helper(Path('/nonexistent/helper.py'),captured)
        self.assertEqual(helper.MARKER,'manifested')
        self.assertEqual(helper.__loaded_sha256__,M.sha(captured))
        self.assertEqual(helper.__file__,'/nonexistent/helper.py')

    def test_all49_original_test_bytes_and_assertion_ASTs_preserved(self):
        original = (ROOT / 'scripts/tests/collect_schema_domain_map_test.py').read_bytes()
        copied = (HERE / 'scripts/tests/collect_schema_domain_map_test.py').read_bytes()
        self.assertEqual(copied, original)
        methods = lambda raw:{n.name:ast.dump(n, include_attributes=False) for n in ast.walk(ast.parse(raw))
            if isinstance(n, ast.FunctionDef) and n.name.startswith('test_')}
        self.assertEqual(methods(copied), methods(original))
        self.assertEqual(len(methods(copied)), 49)


if __name__ == '__main__':
    selected = sys.argv[1:]
    tests = unittest.TestSuite(LineageTests(name) for name in selected) if selected else unittest.defaultTestLoader.loadTestsFromTestCase(LineageTests)
    result = unittest.TextTestRunner(verbosity=2).run(tests)
    print(json.dumps(dict(tests=result.testsRun, errors=len(result.errors), failures=len(result.failures), skips=len(result.skipped)), sort_keys=True))
    raise SystemExit(0 if result.wasSuccessful() and result.testsRun == (len(selected) if selected else 21) and not result.skipped else 1)
