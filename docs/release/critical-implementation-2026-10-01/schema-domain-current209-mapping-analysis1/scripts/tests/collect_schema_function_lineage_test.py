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

HERE = Path(__file__).resolve().parents[2]
ROOT = next(parent for parent in (HERE, *HERE.parents) if (parent / 'supabase/migrations').is_dir())
DATA = ROOT / 'docs/release/critical-implementation-2026-10-01/schema-domain-current209-mapping-analysis1'


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

    def lineage(self, definitions=None, alterations=None, sources=None):
        return L.reviewed_transform_lineage(M, self.sources if sources is None else sources,
            self.definitions if definitions is None else definitions,
            self.alterations if alterations is None else alterations)

    def test_actual34_match_independent_analysis_and_full_catalog_bodies(self):
        expected = json.loads((DATA / 'mapping-analysis.json').read_text())['mappings']
        state = self.lineage()
        for row in expected:
            raw = row['catalog_row']
            key = (raw[0], raw[1], L.signature(M, raw[2]))
            self.assertEqual(state[key]['body'], row['reconstructed_prosrc'])
            self.assertEqual(state[key]['prosrc_sha256'], raw[11])
            self.assertFalse(state[key]['SQL_evaluation_performed'])
        self.assertEqual(len(expected), 34)

    def test_changed_reviewed_source_program_refuses(self):
        path = next(iter(L.REVIEWED_PROGRAMS))
        source = copy.deepcopy(self.sources[path]); source['text'] += '\n-- changed program\n'
        source['sha256'] = M.sha(source['text'].encode())
        with self.assertRaisesRegex(ValueError, 'new lineage review required'):
            self.lineage(definitions=[], alterations=[], sources={path:source})

    def test_missing_or_overloaded_roster_predecessor_refuses(self):
        absent = [d for d in self.definitions if d['name'] != 'admin_get_roster_import']
        with self.assertRaisesRegex(ValueError, 'missing, invalidated or ambiguous'):
            self.lineage(definitions=absent)
        original = next(d for d in self.definitions if d['schema'] == 'public' and d['name'] == 'admin_get_roster_import')
        extra = {**original, 'signature_types':('text',)}
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            self.lineage(definitions=[*self.definitions, extra])

    def test_drop_before_installer_invalidates_predecessor(self):
        sql = 'DROP FUNCTION public.admin_get_roster_import(uuid);'
        drop = M.sql_static_alterations(sql, 'synthetic-before.sql', '20260930165000')
        with self.assertRaisesRegex(ValueError, 'invalidated'):
            self.lineage(alterations=[*self.alterations, *drop])

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
            with self.assertRaisesRegex(ValueError, 'unknown input signature'):
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

    def test_all49_original_test_bytes_and_assertion_ASTs_preserved(self):
        original = (ROOT / 'scripts/tests/collect_schema_domain_map_test.py').read_bytes()
        copied = (HERE / 'scripts/tests/collect_schema_domain_map_test.py').read_bytes()
        self.assertEqual(copied, original)
        methods = lambda raw:{n.name:ast.dump(n, include_attributes=False) for n in ast.walk(ast.parse(raw))
            if isinstance(n, ast.FunctionDef) and n.name.startswith('test_')}
        self.assertEqual(methods(copied), methods(original))
        self.assertEqual(len(methods(copied)), 49)


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(LineageTests))
    print(json.dumps(dict(tests=result.testsRun, errors=len(result.errors), failures=len(result.failures), skips=len(result.skipped)), sort_keys=True))
    raise SystemExit(0 if result.wasSuccessful() and result.testsRun == 12 and not result.skipped else 1)
