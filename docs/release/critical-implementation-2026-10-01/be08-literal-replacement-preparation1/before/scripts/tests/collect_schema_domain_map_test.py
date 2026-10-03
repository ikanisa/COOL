#!/usr/bin/env python3
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

SPEC=importlib.util.spec_from_file_location("domain_map",Path(__file__).resolve().parents[1] / "audits" / "collect_schema_domain_map.py")
M=importlib.util.module_from_spec(SPEC);sys.modules[SPEC.name]=M;SPEC.loader.exec_module(M)

def catalog():
    body="\n SELECT public.groups_read();\n"
    d={k:[] for k in ["schemas","relations","functions","columns","roles","memberships","default_acls","types","dependencies","settings","policies","triggers","indexes","constraints","extensions","event_triggers"]}
    d.update(format="collect-recovery-catalog-v1",server={"major":17},database={"name":"postgres","owner":"postgres","acl":["postgres=CTc/postgres"]},migrations=["20260101000000"])
    d["schemas"]=[["public","postgres",["postgres=UC/postgres"]]]
    d["functions"]=[["public","get_current_member_profile","","f","postgres",True,"s","u",False,False,["authenticated=X/postgres"],M.sha(body.encode()),"a"*64],
                    ["public","groups_read","p_id uuid","f","postgres",False,"s","u",False,False,[],"b"*64,"c"*64]]
    d["relations"]=[["public","profiles","r","p","postgres",True,False,["authenticated=r/postgres"],[],None]]
    d["columns"]=[["public","profiles",1,"id","uuid",True,"","",["anon=r/postgres"],None,None]]
    d["roles"]=[["postgres",True,True,True,True,True,True,True,-1,None,"a"*64]]
    d["types"]=[["public","profiles","c","postgres",False,"-",None,[],[]]]
    return d

class ParserTests(unittest.TestCase):
    def test_comments_and_non_database_from_are_not_calls(self):
        text="// client.rpc('ghost');\n/* client.rpc('ghost'); */\nMap<String, dynamic>.from(row); Array.from(x); client.rpc<dynamic>('get_current_member_profile');"
        sites=M.client_sites(text,"lib/repository.dart",catalog())
        self.assertEqual([(s["kind"],s["symbol"]) for s in sites],[("rpc-call","get_current_member_profile")])
        self.assertEqual(sites[0]["line"],3)

    def test_dynamic_wrapper_overload_and_unknown_are_exposed(self):
        d=catalog();d["functions"].append([*d["functions"][1][:2],"p_id text",*d["functions"][1][3:]])
        sites=M.client_sites("rpc(name, args); this.rpc('groups_read', {}); client.rpc('absent');", "lib/admin/x.dart",d)
        self.assertEqual(sites[0]["kind"],"dynamic-rpc-call")
        self.assertEqual(sites[1]["resolution"],"overload-or-name-ambiguous")
        self.assertEqual(sites[2]["resolution"],"unresolved")
        self.assertTrue(all(s["authorization"]=="not-inferred" for s in sites))

    def test_edge_route_is_not_a_function_target(self):
        sites=M.client_sites("supabase.functions.invoke('get_current_member_profile');", "lib/x.dart",catalog())
        self.assertEqual(sites[0]["candidate_targets"],[])
        self.assertEqual(sites[0]["resolution"],"edge-route-not-database-object")

    def test_roster_helper_and_declarations(self):
        sites=M.client_sites("function rpc(name,args) {} rpc(name: string, args: Json); rpc(deps, 'groups_read', {});", "supabase/functions/prepare-roster-import/handler.ts",catalog())
        self.assertEqual(len(sites),1)
        self.assertEqual(sites[0]["symbol"],"groups_read")

    def test_reviewed_admin_rpcmap_is_a_call_but_rpc_factory_or_action_helper_is_not(self):
        sites=M.client_sites("rpcMap('get_current_member_profile'); callShadowRpc('begin', input); enrollmentOwnerRpc(owner);", "lib/admin/core/x.dart",catalog())
        self.assertEqual([(s["kind"],s["symbol"]) for s in sites],[("rpc-call","get_current_member_profile")])

    def test_interpolation_is_not_resolved_and_schema_override_requires_review(self):
        text="client.schema('private'); client.rpc('groups_read'); String get rpcName => 'admin_${name}_gateway_device_v1'; fetch(`${origin}/rest/v1/rpc/${rpc}`);"
        sites=M.client_sites(text,"lib/admin/x.dart",catalog())
        self.assertEqual(sites[0]["resolution"],"schema-override-review-required")
        self.assertEqual(sum(s["kind"]=="dynamic-symbol-template" for s in sites),2)

    def test_relation_and_realtime_are_separate(self):
        sites=M.client_sites("client.from('profiles'); onPostgresChanges(table: 'profiles'); client.from(tableName);", "lib/x.dart",catalog())
        self.assertEqual([s["kind"] for s in sites],["relation-sdk","dynamic-relation-sdk","realtime-table"])

    def test_sql_body_hash_and_calls_do_not_claim_argument_resolution(self):
        text="CREATE OR REPLACE FUNCTION public.get_current_member_profile() RETURNS jsonb LANGUAGE sql AS $f$\n SELECT public.groups_read();\n$f$;"
        defs=M.sql_definitions(text,"supabase/migrations/20260101000000_x.sql","20260101000000")
        self.assertEqual(defs[0]["prosrc_sha256"],catalog()["functions"][0][11])
        sites=M.sql_sites(defs[0],catalog())
        self.assertEqual(sites[0]["candidate_targets"],["public.groups_read(p_id uuid)"])
        self.assertEqual(sites[0]["resolution"],"unique-qualified-name")

    def test_commented_or_dynamic_create_text_is_not_an_active_definition(self):
        text="-- CREATE FUNCTION public.fake() RETURNS int AS $$1$$ LANGUAGE sql;\n/* CREATE FUNCTION public.fake2() RETURNS int AS $$2$$ LANGUAGE sql; */\nDO $do$ BEGIN EXECUTE 'CREATE FUNCTION public.fake3() RETURNS int AS $q$3$q$ LANGUAGE sql'; END $do$;"
        self.assertEqual(M.sql_definitions(text,"migration.sql","1"),[])

    def test_dynamic_sql_and_unqualified_search_path_are_gaps(self):
        definition={"body":"/* public.groups_read() */ EXECUTE format('SELECT public.groups_read()'); PERFORM groups_read();"}
        sites=M.sql_sites(definition,catalog())
        self.assertEqual([s["kind"] for s in sites],["dynamic-sql-execute","sql-function-name"])
        self.assertEqual(sites[1]["resolution"],"search-path-review-required")

    def test_exclusions_do_not_admit_release_archives_or_tests(self):
        self.assertIsNotNone(M.source_exclusion("supabase/functions/foo/handler_test.ts"))
        self.assertIsNotNone(M.source_exclusion("tools/collect-notification-mcp/src/testing/fixture.ts"))
        self.assertIsNotNone(M.source_exclusion("lib/model.g.dart"))
        self.assertIsNone(M.source_exclusion("supabase/functions/foo/handler.ts"))
        self.assertIsNone(M.source_exclusion("scripts/qa/backend_release_delivery.py"))
        self.assertIsNone(M.source_exclusion("scripts/qa/postgres_admission.py"))

class AdmissionAndCoverageTests(unittest.TestCase):
    def test_bad_format_shape_and_duplicate_identity_rejected(self):
        for mutation in [lambda d:d.update(format="unknown"),lambda d:d["functions"].append(d["functions"][0]),lambda d:d["columns"].append(["bad"]),lambda d:d.pop("dependencies")]:
            d=catalog();mutation(d)
            with self.assertRaises(ValueError):M.admit(d)

    def test_column_grants_and_explicit_empty_function_acl_preserved(self):
        d=catalog();objects=M.normalize_objects(d);grants=M.normalized_grants(d,objects)
        self.assertEqual(sum(g["acl_scope"]=="column" for g in grants),1)
        self.assertEqual(next(g for g in grants if g["acl_scope"]=="column")["domain"],"member-profile")
        self.assertEqual(next(o for o in objects if o["identity"]=="public.groups_read(p_id uuid)")["catalog_acl"],[])

    def setup_tree(self,root):
        (root/"lib").mkdir();(root/"supabase/migrations").mkdir(parents=True)
        (root/"lib/client.dart").write_text("client.rpc('get_current_member_profile'); client.rpc(name);\n")
        (root/"supabase/config.toml").write_text('[api]\nschemas = ["public"]\n')
        (root/"supabase/migrations/20260101000000_first.sql").write_text("CREATE FUNCTION public.get_current_member_profile() RETURNS jsonb AS $$\n SELECT public.groups_read();\n$$ LANGUAGE sql;")
        p=root/"catalog.json";p.write_text(json.dumps(catalog()));p.with_name("catalog-peer.json").write_bytes(p.read_bytes());return p

    def test_stale_chain_is_draft_and_only_catalog_represented_body_sources_match(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=self.setup_tree(root)
            (root/"supabase/migrations/20260102000000_new.sql").write_text("CREATE FUNCTION public.groups_read(p_id uuid) RETURNS jsonb AS $$new$$ LANGUAGE sql;")
            summary=M.build(root,[p,p.with_name("catalog-peer.json")],root/"output")
            self.assertFalse(summary["catalog_matches_current_migration_names"])
            self.assertEqual(summary["acceptance"],"stale-catalog-draft")
            self.assertEqual(summary["functions_with_exact_body_hash_match"],1)
            self.assertEqual(M.verify_bundle(root,root/"output")["status"],"PASS")

    def test_peer_catalog_difference_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=self.setup_tree(root);other=catalog();other["functions"][0][4]="unexpected_owner"
            q=root/"other.json";q.write_text(json.dumps(other))
            with self.assertRaisesRegex(ValueError,"peer final catalogs differ"):M.build(root,[p,q],root/"output")

    def test_replay_source_bytes_are_required_and_drift_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=self.setup_tree(root);captured=root/"captured";captured.mkdir()
            source=next((root/"supabase/migrations").glob("*.sql"));(captured/source.name).write_bytes(source.read_bytes())
            result=M.build(root,[p,p.with_name("catalog-peer.json")],root/"output",captured)
            self.assertTrue(result["replayed_migration_bytes_match"])
            self.assertEqual(result["acceptance"],"draft-with-open-mappings")
            (captured/source.name).write_text("different")
            with self.assertRaisesRegex(ValueError,"replayed migration byte drift"):M.build(root,[p,p.with_name("catalog-peer.json")],root/"output",captured)

    def test_readback_rejects_source_drift_and_object_or_grant_omission(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=self.setup_tree(root);out=root/"output";M.build(root,[p,p.with_name("catalog-peer.json")],out)
            self.assertEqual(M.verify_bundle(root,out)["catalog_objects_verified"],5)
            original=(out/"schema-domain-map.json").read_text();d=json.loads(original)
            d["grants"].pop();(out/"schema-domain-map.json").write_text(json.dumps(d))
            with self.assertRaisesRegex(ValueError,"ACL coverage loss"):M.verify_bundle(root,out)
            d=json.loads(original);d["objects"].pop();(out/"schema-domain-map.json").write_text(json.dumps(d))
            with self.assertRaisesRegex(ValueError,"catalog object coverage loss"):M.verify_bundle(root,out)
            (out/"schema-domain-map.json").write_text(original);(root/"lib/client.dart").write_text("changed")
            with self.assertRaisesRegex(ValueError,"input drift"):M.verify_bundle(root,out)

    def test_unknown_domain_is_visible_not_fallback_classified(self):
        self.assertEqual(M.domain("private","mysterious"),("unclassified","no-reviewed-rule"))
        self.assertEqual(M.domain("public","unexplained"),("unclassified","no-reviewed-rule"))

    def test_readback_rejects_new_source_and_new_migration_not_just_changed_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=self.setup_tree(root);out=root/"output";M.build(root,[p,p.with_name("catalog-peer.json")],out)
            new_source=root/"lib/new.dart";new_source.write_text("client.rpc('groups_read');")
            with self.assertRaisesRegex(ValueError,"caller source set drift"):M.verify_bundle(root,out)
            new_source.unlink();(root/"supabase/migrations/20260102000000_new.sql").write_text("select 1;")
            with self.assertRaisesRegex(ValueError,"migration source set drift"):M.verify_bundle(root,out)

class SemanticRecomputationTests(unittest.TestCase):
    def fixture(self,root):
        p=AdmissionAndCoverageTests().setup_tree(root);out=root/"output"
        M.build(root,[p,p.with_name("catalog-peer.json")],out)
        return p,out

    def mutate_json(self,path,mutation):
        data=json.loads(path.read_text());mutation(data);path.write_text(json.dumps(data))

    def test_omitted_or_removed_caller_and_sql_sites_are_rejected(self):
        for key in ["caller_sites","sql_reference_sites"]:
            for remove in [False,True]:
                with self.subTest(category=key,remove_key=remove),tempfile.TemporaryDirectory() as tmp:
                    root=Path(tmp);_,out=self.fixture(root);path=out/"schema-domain-map.json"
                    self.assertTrue(json.loads(path.read_text())[key])
                    self.mutate_json(path,lambda d:d.pop(key) if remove else d.__setitem__(key,[]))
                    with self.assertRaisesRegex(ValueError,"semantic recomputation mismatch: schema-domain-map.json"):M.verify_bundle(root,out)

    def test_consistently_forged_object_and_grant_domain_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);_,out=self.fixture(root)
            def forge(d):
                obj=next(o for o in d["objects"] if o["kind"]=="relation")
                obj["domain"]="fabricated-reviewed-domain";obj["domain_basis"]="claimed-owner-review"
                for grant in d["grants"]:
                    if grant["target_kind"] in {"relation","column"} and grant["target_identity"].startswith("public.profiles"):grant["domain"]=obj["domain"]
            self.mutate_json(out/"schema-domain-map.json",forge)
            with self.assertRaisesRegex(ValueError,"semantic recomputation mismatch: schema-domain-map.json"):M.verify_bundle(root,out)

    def test_forged_resolution_or_removed_valid_targets_are_rejected(self):
        for key in ["caller_sites","sql_reference_sites"]:
            for field,value in [("resolution","runtime-and-business-authorized"),("candidate_targets",[])]:
                with self.subTest(category=key,field=field),tempfile.TemporaryDirectory() as tmp:
                    root=Path(tmp);_,out=self.fixture(root)
                    self.mutate_json(out/"schema-domain-map.json",lambda d:d[key][0].__setitem__(field,value))
                    with self.assertRaisesRegex(ValueError,"semantic recomputation mismatch: schema-domain-map.json"):M.verify_bundle(root,out)

    def test_forged_summary_and_consistent_coverage_copy_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);_,out=self.fixture(root)
            fields={"runtime_call_graph_complete":True,"business_owner_assignments_verified":True,"unclassified_objects":0,"dynamic_or_unresolved_caller_sites":0,"acceptance":"complete"}
            self.mutate_json(out/"schema-domain-map.json",lambda d:d["summary"].update(fields))
            self.mutate_json(out/"coverage.json",lambda d:d.update(fields))
            with self.assertRaisesRegex(ValueError,"semantic recomputation mismatch: schema-domain-map.json"):M.verify_bundle(root,out)

    def test_forged_standalone_coverage_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);_,out=self.fixture(root)
            self.mutate_json(out/"coverage.json",lambda d:d.__setitem__("source_migrations",999))
            with self.assertRaisesRegex(ValueError,"semantic recomputation mismatch: coverage.json"):M.verify_bundle(root,out)

    def test_omitted_gap_rows_categories_and_missing_gap_artifact_are_rejected(self):
        for mutation in [lambda d:d.__setitem__("unresolved_callers",[]),lambda d:d.pop("functions_without_exact_body_match")]:
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);_,out=self.fixture(root)
                self.mutate_json(out/"gaps.json",mutation)
                with self.assertRaisesRegex(ValueError,"semantic recomputation mismatch: gaps.json"):M.verify_bundle(root,out)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);_,out=self.fixture(root);(out/"gaps.json").unlink()
            with self.assertRaisesRegex(ValueError,"missing or unreadable input: .*gaps.json"):M.verify_bundle(root,out)

    def test_domain_summary_and_object_source_indexes_are_recomputed(self):
        for mutation in [lambda d:d.__setitem__("domain_summaries",[]),lambda d:d["objects"][2].__setitem__("caller_site_indexes",[]),lambda d:d["objects"][2].__setitem__("matched_body_sources",[]),lambda d:d.__setitem__("invented_field",True)]:
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);_,out=self.fixture(root)
                self.mutate_json(out/"schema-domain-map.json",mutation)
                with self.assertRaisesRegex(ValueError,"semantic recomputation mismatch: schema-domain-map.json"):M.verify_bundle(root,out)

    def test_manifest_scan_boundary_and_markdown_are_recomputed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);_,out=self.fixture(root)
            self.mutate_json(out/"input-manifest.json",lambda d:d.__setitem__("scan_roots",["claimed-complete-scope"]))
            with self.assertRaisesRegex(ValueError,"semantic recomputation mismatch: input-manifest.json"):M.verify_bundle(root,out)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);_,out=self.fixture(root);(out/"DOMAIN_MAP.md").write_text("Perfect coverage and authorized.\n")
            with self.assertRaisesRegex(ValueError,"semantic recomputation mismatch: DOMAIN_MAP.md"):M.verify_bundle(root,out)

    def test_two_distinct_peer_catalog_paths_are_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p,_=self.fixture(root)
            for paths in [[],[p],[p,p],[p,p.parent/"."/p.name],[p,p.with_name("catalog-peer.json"),p]]:
                with self.subTest(paths=paths),self.assertRaisesRegex(ValueError,"two distinct effective catalog paths required"):M.build(root,paths,root/"invalid")

    def test_removed_peer_even_with_rebound_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);_,out=self.fixture(root)
            manifest=json.loads((out/"input-manifest.json").read_text());inputs=manifest["inputs"]
            second=[i for i in inputs if i["kind"]=="effective-catalog"][1];inputs.remove(second)
            (out/"input-manifest.json").write_text(json.dumps(manifest))
            self.mutate_json(out/"schema-domain-map.json",lambda d:d.__setitem__("input_manifest_sha256",M.sha(M.canonical(inputs))))
            with self.assertRaisesRegex(ValueError,"two distinct effective catalog paths required"):M.verify_bundle(root,out)

    def test_duplicate_type_identity_is_rejected(self):
        d=catalog();d["types"].append(copy.deepcopy(d["types"][0]))
        with self.assertRaisesRegex(ValueError,"duplicate catalog identity: types"):M.admit(d)

    def test_non_object_catalog_has_a_bounded_admission_error(self):
        for value in [[],None,"catalog"]:
            with self.subTest(value=value),self.assertRaisesRegex(ValueError,"unsupported or incomplete catalog"):M.admit(value)

    def test_missing_catalog_input_has_a_bounded_explicit_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p,out=self.fixture(root);peer=p.with_name("catalog-peer.json");peer.unlink()
            with self.assertRaisesRegex(ValueError,"missing or unreadable input: .*catalog-peer.json"):M.verify_bundle(root,out)
            with self.assertRaisesRegex(ValueError,"missing or unreadable input: .*catalog-peer.json"):M.build(root,[p,peer],root/"invalid")

def function(name,body,schema='public',arguments='',kind='f'):
    row=list(catalog()['functions'][0]);row[0]=schema;row[1]=name;row[2]=arguments;row[3]=kind;row[11]=M.sha(body.encode())
    return row

class LineageAndGapTests(unittest.TestCase):
    def build(self,root,sql,rows):
        p=AdmissionAndCoverageTests().setup_tree(root)
        source=root/'supabase/migrations/20260101000000_first.sql';source.write_text(sql)
        d=catalog();d['functions']=rows
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

class UnqualifiedDropLineageTests(unittest.TestCase):
    def lineage(self, sql):
        return M.sql_static_lineage(
            M.sql_definitions(sql, "synthetic.sql", "20260101000000"),
            M.sql_static_alterations(sql, "synthetic.sql", "20260101000000"))

    def test_unqualified_and_quoted_drop_cannot_reuse_opaque_recreation(self):
        for name, drop in [("old", "old()"), ("old", "IF EXISTS old()"), ('"Old"', '"Old"()')]:
            with self.subTest(name=name, drop=drop):
                sql=(f"SET search_path=public; CREATE FUNCTION public.{name}() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; "
                     f"DROP FUNCTION {drop}; DO $do$ BEGIN EXECUTE 'CREATE FUNCTION public.{name}() RETURNS int AS $q$SELECT 1;$q$ LANGUAGE sql'; END; $do$; "
                     f"ALTER FUNCTION public.{name}() RENAME TO saved;")
                self.assertFalse(any(key[1]=="saved" for key in self.lineage(sql)))

    def test_mixed_drop_list_invalidates_unqualified_later_target(self):
        sql=("CREATE FUNCTION public.a() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; "
             "CREATE FUNCTION public.b(p_id uuid) RETURNS int AS $$SELECT 2;$$ LANGUAGE sql; "
             "DROP FUNCTION IF EXISTS public.a(), b(uuid); "
             "ALTER FUNCTION public.b(uuid) RENAME TO saved;")
        alterations=M.sql_static_alterations(sql,"synthetic.sql","20260101000000")
        dropped={(row["schema"],row["name"]) for row in alterations if row["operation"]=="drop-name"}
        self.assertEqual(dropped,{("public","a"),(None,"b")})
        self.assertFalse(any(key[1]=="saved" for key in self.lineage(sql)))

    def test_unqualified_drop_invalidates_same_name_schemas_and_overloads(self):
        sql=("CREATE FUNCTION public.old(p_id uuid) RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; "
             "CREATE FUNCTION public.old(p_id text) RETURNS int AS $$SELECT 2;$$ LANGUAGE sql; "
             "CREATE FUNCTION other.old(p_id uuid) RETURNS int AS $$SELECT 3;$$ LANGUAGE sql; "
             "DROP FUNCTION old(uuid); ALTER FUNCTION public.old(text) RENAME TO saved; "
             "ALTER FUNCTION other.old(uuid) SET SCHEMA moved;")
        self.assertEqual(self.lineage(sql),{})

    def test_qualified_drop_keeps_other_schema_lineage(self):
        sql=("CREATE FUNCTION public.old() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; "
             "CREATE FUNCTION other.old() RETURNS int AS $$SELECT 2;$$ LANGUAGE sql; "
             "DROP FUNCTION other.old(); ALTER FUNCTION public.old() RENAME TO saved;")
        value=self.lineage(sql)
        self.assertEqual(set(value),{("public","saved",())})
        self.assertEqual(value[("public","saved",())]["prosrc_sha256"],M.sha(b"SELECT 1;"))

    def test_uncertain_short_name_cannot_become_rename_destination(self):
        sql=("DROP FUNCTION IF EXISTS old(); CREATE FUNCTION public.fresh() RETURNS int AS $$SELECT 1;$$ LANGUAGE sql; "
             "ALTER FUNCTION public.fresh() RENAME TO old;")
        self.assertFalse(any(key[1]=="old" for key in self.lineage(sql)))

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

if __name__=="__main__":unittest.main(verbosity=2)
