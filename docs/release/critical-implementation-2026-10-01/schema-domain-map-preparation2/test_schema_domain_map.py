#!/usr/bin/env python3
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

SPEC=importlib.util.spec_from_file_location("domain_map",Path(__file__).with_name("generate_schema_domain_map.py"))
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

if __name__=="__main__":unittest.main(verbosity=2)
