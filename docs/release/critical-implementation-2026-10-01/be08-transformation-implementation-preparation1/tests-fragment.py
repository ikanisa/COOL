class TransformationCandidateTests(unittest.TestCase):
    build=LineageAndGapTests.build
    find=LineageAndGapTests.find

    def candidates(self,sql):
        return M.sql_transformation_candidates(sql,"synthetic.sql","20260101000000")

    def wrapper_sql(self,inventory="'old'"):
        return """DO $install$ DECLARE f record; alias_name text; arguments text; guard_sql text;
 entries text[]:=array["""+inventory+"""]; BEGIN
 FOR f IN SELECT p.proname, p.proargnames, pg_get_function_arguments(p.oid) AS declaration,
 pg_get_function_identity_arguments(p.oid) AS identity_args FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' and p.proname=any(entries) LOOP
 alias_name:=f.proname||'_guarded_149';
 execute format('alter function public.%I(%s) set schema collect_hybrid',f.proname,f.identity_args);
 execute format('alter function collect_hybrid.%I(%s) rename to %I',f.proname,f.identity_args,alias_name);
 execute format($ddl$create function public.%I(%s) returns jsonb language plpgsql security definer set search_path='' as $fn$
   begin %s return collect_hybrid.%I(%s); end $fn$ $ddl$,f.proname,f.declaration,guard_sql,alias_name,arguments);
 END LOOP; END $install$;"""

    def test_finite_inventory_hints_are_name_only_and_do_not_admit_overloads(self):
        sql=self.wrapper_sql("'old','old'")
        candidates=self.candidates(sql)
        self.assertEqual(len(candidates),2)
        self.assertEqual({c['operation'] for c in candidates},{'finite-inventory-private-move-rename','finite-inventory-generated-wrapper'})
        self.assertEqual({(c['target']['schema'],c['target']['name']) for c in candidates},{('public','old'),('collect_hybrid','old_guarded_149')})
        for c in candidates:
            self.assertIsNone(c['target']['signature_types'])
            self.assertFalse(c['resolved']);self.assertFalse(c['lineage_complete'])
            self.assertFalse(c['expected_body_computed']);self.assertIsNone(c['expected_body_hash_match'])
            self.assertEqual(c['literal_inventory'],['old'])
        with tempfile.TemporaryDirectory() as tmp:
            rows=[function('old','SELECT 2;',arguments='p_id uuid'),function('old','SELECT 3;',arguments='p_id text'),function('old_guarded_149','SELECT 1;','collect_hybrid',arguments='p_id uuid'),function('unrelated','SELECT 9;')]
            doc,_=self.build(Path(tmp),sql,rows)
            for obj in [o for o in doc['objects'] if o['kind']=='function']:
                hints=obj['source_match_review']['transformation_candidates']
                self.assertEqual(len(hints),0 if obj['name']=='unrelated' else 1)
                self.assertEqual(obj['source_status'],'no-exact-body-source-match')
                self.assertFalse(obj['source_match_review']['resolved']);self.assertEqual(obj['matched_body_sources'],[])

    def test_header_alias_records_source_destination_and_exact_source_hashes(self):
        sql="CREATE FUNCTION public.old(p_id uuid) RETURNS int AS $$SELECT 1;$$ LANGUAGE sql;\nDO $$DECLARE body text; BEGIN body:=pg_get_functiondef('public.old(uuid)'::regprocedure); execute replace(body,'FUNCTION public.old(', 'FUNCTION collect_hybrid.saved('); END$$;"
        c=self.candidates(sql)[0]
        self.assertEqual(c['operation'],'function-definition-header-copy')
        self.assertEqual((c['predecessor']['schema'],c['predecessor']['name'],c['predecessor']['signature_types']),('public','old',('uuid',)))
        self.assertEqual((c['target']['schema'],c['target']['name']),('collect_hybrid','saved'))
        for s in [c['anonymous_block'],c['operation_source']]:
            self.assertEqual(s['sha256'],M.sha(sql[s['start_character_offset']:s['end_character_offset']].encode()))
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('saved','SELECT 1;','collect_hybrid',arguments='p_id uuid')])
            review=self.find(doc,'saved')['source_match_review']
            hint=review['transformation_candidates'][0]
            self.assertEqual(len(hint['predecessor_source_definition_candidates']),1)
            self.assertFalse(hint['predecessor_candidates_are_installed_state'])
            self.assertFalse(review['resolved']);self.assertEqual(review['reason'],'no-literal-effective-name-definition')

    def test_replacement_hints_preserve_order_and_raw_e_string_expression(self):
        sql="DO $$DECLARE body text; needle text:='SELECT 1;'; replacement text:=needle||E'\\nSELECT 2;'; BEGIN body:=pg_get_functiondef('public.saved()'::regprocedure); execute replace(body,needle,replacement); needle:='2'; replacement:='3'; execute replace(body,needle,replacement); body:=pg_get_functiondef('public.other()'::regprocedure); execute replace(body,'1','9'); END$$;"
        candidates=self.candidates(sql)
        self.assertEqual([c['target']['name'] for c in candidates],['saved','saved','other'])
        self.assertEqual([c['operation'] for c in candidates],['function-definition-replace']*3)
        expression=candidates[0]['nearest_textual_replacement_assignments'][1]
        span=expression['source_span'];raw=sql[span['start_character_offset']:span['end_character_offset']]
        self.assertEqual(raw,"needle||E'\\nSELECT 2;'")
        self.assertEqual(span['sha256'],M.sha(raw.encode()));self.assertFalse(expression['evaluation_performed'])
        self.assertLess(candidates[0]['operation_source']['start_character_offset'],candidates[1]['operation_source']['start_character_offset'])

    def test_literal_signature_candidate_cannot_attach_to_different_overload(self):
        sql="DO $$DECLARE body text; BEGIN body:=pg_get_functiondef('public.saved(uuid)'::regprocedure); execute replace(body,'1','2'); END$$;"
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('saved','SELECT 2;',arguments='p_id uuid'),function('saved','SELECT 3;',arguments='p_id text')])
            objects=[o for o in doc['objects'] if o['kind']=='function']
            self.assertEqual([len(o['source_match_review']['transformation_candidates']) for o in objects],[1,0])
        self.assertEqual(M.transformation_signature('p_at timestamp with time zone'),M.transformation_signature('p_at timestamptz'))
        self.assertIsNone(M.transformation_signature('p_id "OddType"'))
        self.assertIsNone(M.transformation_signature('OUT p_id uuid'))

    def test_strings_comments_and_nonliteral_targets_do_not_generate_hints(self):
        fragment="body:=pg_get_functiondef('public.saved()'::regprocedure); execute replace(body,'1','2');"
        cases=["-- DO $$BEGIN "+fragment+" END$$;", "/* /* nested */ DO $$BEGIN "+fragment+" END$$; */",
               "DO $do$BEGIN RAISE NOTICE $payload$"+fragment+"$payload$; END$do$;",
               "DO $$BEGIN body:=pg_get_functiondef('saved(uuid)'::regprocedure); execute replace(body,'1','2'); END$$;",
               "DO $$BEGIN body:=pg_get_functiondef(target_oid); execute replace(body,'1','2'); END$$;",
               "DO $$BEGIN body:=pg_get_functiondef('public.saved'::regproc); execute replace(body,'1','2'); END$$;",
               self.wrapper_sql().replace("array['old']","runtime_inventory")]
        for sql in cases:
            with self.subTest(sql=sql):self.assertEqual(self.candidates(sql),[])
        with self.assertRaisesRegex(ValueError,'unknown or unterminated DO syntax'):
            M.sql_lineage_uncertainty("DO $missing$ BEGIN SELECT 1;",'synthetic.sql','20260101000000')

    def test_wrapper_template_or_argument_drift_remains_unrecognized(self):
        sql=self.wrapper_sql()
        cases=[sql.replace('begin %s return','begin  %s return'),
               sql.replace('f.declaration,guard_sql','other_declaration,guard_sql'),
               sql.replace("n.nspname='public'","n.nspname='unknown'"),
               sql.replace("alias_name:=f.proname||'_guarded_149'","alias_name:=runtime_alias(f.proname)")]
        for changed in cases:
            with self.subTest(changed=changed):self.assertEqual(self.candidates(changed),[])

    def test_dynamic_hints_preserve_all_existing_semantics_and_uncertainty(self):
        sql="CREATE FUNCTION public.old() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; DO $$BEGIN PERFORM public.unknown_effect(); END$$; ALTER FUNCTION public.old() RENAME TO saved; DO $$DECLARE body text; BEGIN body:=pg_get_functiondef('public.saved()'::regprocedure); execute replace(body,'1','2'); END$$;"
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);doc,out=self.build(root,sql,[function('saved','SELECT 1;')])
            gaps=json.loads((out/'gaps.json').read_text())
            original=M.sql_transformation_candidates
            try:
                M.sql_transformation_candidates=lambda *args:[]
                baseline_out=root/'baseline-output'
                M.build(root,[root/'catalog.json',root/'catalog-peer.json'],baseline_out)
                baseline=json.loads((baseline_out/'schema-domain-map.json').read_text())
                baseline_gaps=json.loads((baseline_out/'gaps.json').read_text())
            finally:M.sql_transformation_candidates=original
            for record in [*doc['objects'],*baseline['objects']]:
                if 'source_match_review' in record:record['source_match_review'].pop('transformation_candidates',None)
            for record in [*gaps['function_body_match_review'],*baseline_gaps['function_body_match_review']]:record.pop('transformation_candidates',None)
            self.assertEqual(doc,baseline);self.assertEqual(gaps,baseline_gaps)
            review=self.find(doc,'saved')['source_match_review']
            self.assertEqual(review['reason'],'intervening-unproved-function-effects')
            self.assertTrue(review['withdrawn_static_lineage_candidates']);self.assertFalse(review['resolved'])
            self.assertEqual(doc['summary']['functions_with_exact_body_hash_match'],0)
            self.assertFalse(doc['summary']['business_owner_assignments_verified'])

    def test_transformation_hint_tamper_is_rejected_by_full_semantic_readback(self):
        sql="DO $$DECLARE body text; BEGIN body:=pg_get_functiondef('public.saved()'::regprocedure); execute replace(body,'1','2'); END$$;"
        for artifact in ['schema-domain-map.json','gaps.json']:
            for mode in ['alter','omit','duplicate']:
                with self.subTest(artifact=artifact,mode=mode),tempfile.TemporaryDirectory() as tmp:
                    root=Path(tmp);_,out=self.build(root,sql,[function('saved','SELECT 2;')])
                    path=out/artifact;data=json.loads(path.read_text())
                    review=next(o for o in data['objects'] if o['kind']=='function')['source_match_review'] if artifact=='schema-domain-map.json' else data['function_body_match_review'][0]
                    hints=review['transformation_candidates'];self.assertEqual(len(hints),1)
                    if mode=='alter':hints[0]['resolved']=True
                    elif mode=='omit':hints.clear()
                    else:hints.append(copy.deepcopy(hints[0]))
                    path.write_text(json.dumps(data))
                    with self.assertRaisesRegex(ValueError,'semantic recomputation mismatch: '+artifact):M.verify_bundle(root,out)
