from pathlib import Path
base=Path(__file__).parent;p=base/'proposal/scripts/tests/collect_schema_domain_map_test.py'
s=p.read_text();anchor='if __name__=="__main__":unittest.main(verbosity=2)\n'
addition=r'''class LiteralReplacementCandidateTests(unittest.TestCase):
    build=LineageAndGapTests.build
    find=LineageAndGapTests.find

    def definition(self,body="SELECT 1;",arguments=""):
        return "CREATE FUNCTION public.saved("+arguments+") RETURNS int LANGUAGE sql AS $fn$"+body+"$fn$;\n"

    def recipe(self,needle="SELECT 1;",replacement="SELECT 2;",signature="",declaration=False,count_guard=False):
        literals="needle:=$old$"+needle+"$old$;replacement:=$new$"+replacement+"$new$;"
        declarations=("needle text:=$old$"+needle+"$old$;replacement text:=$new$"+replacement+"$new$;") if declaration else "needle text;replacement text;"
        guard="if(length(body)-length(replace(body,needle,'')))/length(needle)<>1" if count_guard else "if strpos(body,needle)=0"
        return ("DO $do$ DECLARE body text;"+declarations+"BEGIN body:=pg_get_functiondef('public.saved("+signature+")'::regprocedure);"
                +(literals if not declaration else "")+guard+" then raise exception 'patch_drift' using errcode='55000';end if;"
                "execute replace(body,needle,replacement);END $do$;")

    def review(self,sql,expected="SELECT 2;",arguments=""):
        with tempfile.TemporaryDirectory() as tmp:
            doc,_=self.build(Path(tmp),sql,[function('saved',expected,arguments=arguments)])
            obj=self.find(doc,'saved')
            return obj['source_match_review'],doc

    def candidate(self,sql):
        return M.sql_transformation_candidates(sql,"synthetic.sql","20260101000000")[0]

    def computation(self,sql,candidate=None,definitions=None):
        candidate=candidate or self.candidate(sql)
        definitions=definitions if definitions is not None else M.sql_definitions(sql,"synthetic.sql","20260101000000")
        return M.literal_replacement_computation(candidate,definitions,{("synthetic.sql","20260101000000"):sql},M.sha(b'SELECT 2;'))

    def test_partial_raw_body_candidate_matches_catalog_without_resolving_lineage(self):
        sql=self.definition()+self.recipe();review,doc=self.review(sql)
        candidate=review['transformation_candidates'][0];proof=candidate['literal_replacement_computation']
        self.assertTrue(candidate['expected_body_computed']);self.assertTrue(candidate['expected_body_hash_match'])
        self.assertEqual(proof['computed_prosrc_sha256'],M.sha(b'SELECT 2;'));self.assertEqual(proof['computed_prosrc_utf8_bytes'],9)
        self.assertEqual(proof['needle_occurrences'],1)
        self.assertFalse(review['resolved']);self.assertFalse(candidate['resolved']);self.assertFalse(candidate['lineage_complete'])
        self.assertFalse(proof['installed_predecessor_state_verified']);self.assertFalse(proof['pg_get_functiondef_ddl_evaluated'])
        self.assertFalse(proof['dynamic_SQL_evaluation_performed'])
        self.assertEqual(doc['summary']['functions_without_exact_body_match'],1)
        self.assertEqual(self.find(doc,'saved')['matched_body_sources'],[])
        self.assertNotIn('_literal_replacement_recipe',candidate)

    def test_full_body_declaration_recipe_and_occurrence_guard_preserve_exact_bytes(self):
        body="\nSELECT 'é';\n";replacement="\nSELECT '雪';\n"
        sql=self.definition(body)+self.recipe(body,replacement,declaration=True,count_guard=True)
        review,_=self.review(sql,replacement);candidate=review['transformation_candidates'][0]
        proof=candidate['literal_replacement_computation'];self.assertTrue(candidate['expected_body_hash_match'])
        self.assertEqual(proof['predecessor_literal_body']['utf8_bytes'],len(body.encode()))
        self.assertEqual(proof['computed_prosrc_utf8_bytes'],len(replacement.encode()))
        for span in [candidate['anonymous_block'],candidate['operation_source'],proof['guard_source'],proof['predecessor_assignment_source'],proof['needle_literal']['source_span'],proof['replacement_literal']['source_span'],proof['predecessor_literal_body']]:
            self.assertEqual(span['sha256'],M.sha(sql[span['start_character_offset']:span['end_character_offset']].encode()))
        self.assertGreater(len(sql.encode()),len(sql))

    def test_expected_body_hash_mismatch_remains_a_computed_unresolved_candidate(self):
        review,_=self.review(self.definition()+self.recipe(),'SELECT 3;')
        candidate=review['transformation_candidates'][0]
        self.assertTrue(candidate['expected_body_computed']);self.assertFalse(candidate['expected_body_hash_match'])
        self.assertEqual(candidate['literal_replacement_computation']['computed_prosrc_sha256'],M.sha(b'SELECT 2;'))
        self.assertFalse(review['resolved'])

    def test_e_strings_singlequotes_branches_loops_and_dynamic_effects_are_rejected(self):
        recipe=self.recipe()
        cases=[recipe.replace('$new$SELECT 2;$new$',"E'SELECT 2;'"),
               recipe.replace('$new$SELECT 2;$new$',"'SELECT 2;'"),
               recipe.replace('$new$SELECT 2;$new$',"$new$SELECT 2;$new$||$more$SELECT 3;$more$"),
               recipe.replace('execute replace','if current_setting(\'flag\')=\'yes\' then execute replace').replace('END $do$','end if;END $do$'),
               recipe.replace('execute replace','LOOP execute replace').replace('END $do$','END LOOP;END $do$'),
               recipe.replace('execute replace',"PERFORM public.unknown_effect();execute replace"),
               recipe.replace('execute replace',"body:=runtime_body();execute replace"),
               recipe.replace('execute replace',"needle:=$again$SELECT 1;$again$;execute replace"),
               recipe.replace('end if;',"else replacement:=$other$SELECT 9;$other$;end if;"),
               recipe.replace("'55000'","'22023'"),
               recipe.replace('strpos(body,needle)=0','strpos(body,needle)>0'),
               recipe.replace('body:=pg_get_functiondef', 'body:=other_get_functiondef')]
        for changed in cases:
            with self.subTest(recipe=changed):
                candidates=M.sql_transformation_candidates(changed,'synthetic.sql','20260101000000')
                self.assertTrue(all('_literal_replacement_recipe' not in c for c in candidates))

    def test_missing_or_duplicate_needle_and_empty_needle_are_not_computed(self):
        for body,needle,count in [('SELECT 9;','SELECT 1;',0),('SELECT 1; SELECT 1;','SELECT 1;',2),('SELECT 1;','',0)]:
            with self.subTest(body=body,needle=needle):
                sql=self.definition(body)+self.recipe(needle,'SELECT 2;')
                proof=self.computation(sql)
                self.assertFalse(proof['computed']);self.assertIsNone(proof['catalog_prosrc_hash_match'])
                self.assertEqual(proof['needle_occurrences'],count)

    def test_exact_signature_selects_only_its_literal_predecessor(self):
        sql=self.definition(arguments='p_id uuid')+self.definition('SELECT 9;','p_id text')+self.recipe(signature='uuid')
        proof=self.computation(sql);self.assertTrue(proof['computed']);self.assertTrue(proof['catalog_prosrc_hash_match'])
        review,_=self.review(sql,arguments='p_id uuid')
        self.assertEqual(len(review['transformation_candidates']),1)
        self.assertEqual(len(review['transformation_candidates'][0]['predecessor_source_definition_candidates']),1)
        changed=sql.replace("public.saved(uuid)'::regprocedure","public.saved(text)'::regprocedure")
        proof=self.computation(changed);self.assertFalse(proof['computed']);self.assertEqual(proof['needle_occurrences'],0)

    def test_ambiguous_missing_and_later_literal_predecessors_fail_closed(self):
        recipe=self.recipe()
        for sql,count in [(recipe,0),(self.definition()+self.definition()+recipe,2),(recipe+self.definition(),0)]:
            with self.subTest(count=count):
                proof=self.computation(sql)
                self.assertFalse(proof['computed']);self.assertEqual(proof['predecessor_definition_count'],count)
        body=self.definition().replace('FUNCTION','PROCEDURE')+recipe
        self.assertFalse(self.computation(body)['computed'])

    def test_singlequoted_and_inexact_predecessor_source_bytes_fail_closed(self):
        sql="CREATE FUNCTION public.saved() RETURNS int LANGUAGE sql AS 'SELECT 1;';"+self.recipe()
        proof=self.computation(sql);self.assertFalse(proof['computed']);self.assertEqual(proof['reason'],'predecessor-not-exact-dollarquoted-source')
        sql=self.definition()+self.recipe();definitions=M.sql_definitions(sql,'synthetic.sql','20260101000000')
        definitions[0]['body']='SELECT 9;'
        proof=self.computation(sql,definitions=definitions);self.assertFalse(proof['computed'])

    def test_unknown_intervening_do_keeps_source_review_and_existing_counters_unresolved(self):
        sql=self.definition()+"DO $$BEGIN PERFORM public.unknown_effect();END$$;"+self.recipe()
        review,doc=self.review(sql);candidate=review['transformation_candidates'][0]
        self.assertTrue(candidate['expected_body_hash_match']);self.assertFalse(review['resolved'])
        self.assertEqual(doc['summary']['functions_without_exact_body_match'],1)
        self.assertFalse(doc['summary']['runtime_call_graph_complete']);self.assertFalse(doc['summary']['business_owner_assignments_verified'])

    def test_multiple_straightline_recipes_do_not_share_reassigned_literal_state(self):
        first=self.recipe('SELECT 1;','SELECT 2;')
        second=self.recipe('SELECT 2;','SELECT 3;')
        sql=self.definition()+first.replace('END $do$;',second.split('BEGIN ',1)[1])
        candidates=M.sql_transformation_candidates(sql,'synthetic.sql','20260101000000')
        self.assertEqual(len(candidates),2);self.assertTrue(all('_literal_replacement_recipe' in c for c in candidates))
        self.assertTrue(self.computation(sql,candidates[0])['catalog_prosrc_hash_match'])
        proof=self.computation(sql,candidates[1]);self.assertFalse(proof['computed']);self.assertEqual(proof['needle_occurrences'],0)
        # Reusing old assignments after another get_functiondef read is refused.
        changed=sql.replace('needle:=$old$SELECT 2;$old$;replacement:=$new$SELECT 3;$new$;','')
        self.assertTrue(all('_literal_replacement_recipe' not in c for c in M.sql_transformation_candidates(changed,'synthetic.sql','20260101000000')))

    def test_recipe_span_value_signature_and_migration_drift_fail_source_rebinding(self):
        sql=self.definition()+self.recipe();candidate=self.candidate(sql)
        cases=[]
        altered=copy.deepcopy(candidate);altered['_literal_replacement_recipe']['needle']['source_span']['sha256']='0'*64;cases.append(altered)
        altered=copy.deepcopy(candidate);altered['_literal_replacement_recipe']['replacement']['value']='SELECT 9;';cases.append(altered)
        altered=copy.deepcopy(candidate);altered['target']['signature_types']=('uuid',);cases.append(altered)
        altered=copy.deepcopy(candidate);altered['source_migration_sha256']='0'*64;cases.append(altered)
        for altered in cases:
            with self.subTest(candidate=altered):
                proof=self.computation(sql,altered);self.assertFalse(proof['computed']);self.assertIsNone(proof['catalog_prosrc_hash_match'])

    def test_computed_hash_match_artifact_tamper_is_rejected_by_semantic_recomputation(self):
        sql=self.definition()+self.recipe()
        for name in ['schema-domain-map.json','gaps.json']:
            with self.subTest(artifact=name),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);_,out=self.build(root,sql,[function('saved','SELECT 2;')]);path=out/name;data=json.loads(path.read_text())
                review=next(o for o in data['objects'] if o['kind']=='function')['source_match_review'] if name=='schema-domain-map.json' else data['function_body_match_review'][0]
                candidate=review['transformation_candidates'][0];self.assertTrue(candidate['expected_body_hash_match'])
                candidate['literal_replacement_computation']['computed_prosrc_sha256']='0'*64;path.write_text(json.dumps(data))
                with self.assertRaisesRegex(ValueError,'semantic recomputation mismatch: '+name):M.verify_bundle(root,out)

'''
if s.count(anchor)!=1:raise SystemExit('test insertion anchor')
p.write_text(s.replace(anchor,addition+anchor))
print('12 focused private tests added')
