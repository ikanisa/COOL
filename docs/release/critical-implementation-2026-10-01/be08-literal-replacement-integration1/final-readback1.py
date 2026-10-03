from pathlib import Path
import copy,hashlib,json,stat,ast
root=Path.cwd();base=root/'docs/release/critical-implementation-2026-10-01/be08-literal-replacement-integration1';prep=base.parent/'be08-literal-replacement-preparation1';prior=base.parent/'root-be08-post-integration-current2091/generated-current209';out=base/'generated-current209'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def write(name,value):(base/name).write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')
old=json.loads((prior/'schema-domain-map.json').read_text());new=json.loads((out/'schema-domain-map.json').read_text());oldgaps=json.loads((prior/'gaps.json').read_text());newgaps=json.loads((out/'gaps.json').read_text())
def normalize(doc,gaps=False):
 d=copy.deepcopy(doc)
 if not gaps:
  d.pop('input_manifest_sha256',None);rows=[o['source_match_review'] for o in d['objects'] if 'source_match_review' in o]
 else:rows=d['function_body_match_review']
 for row in rows:
  for c in row['transformation_candidates']:
   c.pop('literal_replacement_computation',None);c['expected_body_computed']=False;c['expected_body_hash_match']=None
   c['limitations']=['anonymous effects and variable/control-flow state unproved','replacement scope and literal/E-string decoding unproved','predecessor installed state and effective history unproved']
 return d
parity=normalize(old)==normalize(new);gapsparity=normalize(oldgaps,True)==normalize(newgaps,True)
coverageold=json.loads((prior/'coverage.json').read_text());coverage=json.loads((out/'coverage.json').read_text())
if not parity or not gapsparity or coverageold!=coverage:raise SystemExit('Existing semantics or counters changed')
private=json.loads((prep/'reviewed-final/generated-current209/schema-domain-map.json').read_text());privategaps=json.loads((prep/'reviewed-final/generated-current209/gaps.json').read_text())
private.pop('input_manifest_sha256',None);actual=copy.deepcopy(new);actual.pop('input_manifest_sha256',None)
if private!=actual or privategaps!=newgaps:raise SystemExit('Maintained results differ from reviewed private candidate semantics')
old_manifest=json.loads((prior/'input-manifest.json').read_text());manifest=json.loads((out/'input-manifest.json').read_text())
oldinputs={(r['kind'],r['path']):r for r in old_manifest['inputs']};newinputs={(r['kind'],r['path']):r for r in manifest['inputs']}
if set(oldinputs)!=set(newinputs):raise SystemExit('Current maintained input membership changed')
changes=[{'before':oldinputs[k],'after':newinputs[k]} for k in oldinputs if oldinputs[k]!=newinputs[k]]
if len(changes)!=2 or {r['after']['kind'] for r in changes}!={'generator-proposal','maintained-caller-source'} or any(r['after']['path']!='scripts/audits/collect_schema_domain_map.py' for r in changes):raise SystemExit('Unexpected held source change')
if any(r['after']['sha256']!='bbf78e003736bb023e65efe1b5301b7c71159e9bb508462f90bafdffd16a7dd4' for r in changes):raise SystemExit('Integrated mapper identity drift')
records=[c for o in new['objects'] if 'source_match_review' in o for c in o['source_match_review']['transformation_candidates']]
recognized=[c for c in records if 'literal_replacement_computation' in c];computed=[c for c in records if c['expected_body_computed']]
expected={'queue_receipt_exception_source':(802,'368e24280a4071f19e619f71438e4334b75d1b8bb534f13ffa0d9207004df8c5'),'receipt_exception_quota_available':(1002,'92b8e73053749e3cc21ae9ba9b497220edc582214f344cd72301b842c80089e9'),'capture_receipt_backlog_budget_refusal':(490,'403688ec34f93edba0670241442d26a153c0aa48dd22d2f50c79fbb22fc7d6df')}
proofs=[]
for c in computed:
 p=c['literal_replacement_computation'];expected_bytes,expected_hash=expected[c['target']['name']]
 if p['computed_prosrc_utf8_bytes']!=expected_bytes or p['computed_prosrc_sha256']!=expected_hash or c['expected_body_hash_match'] is not True or c['resolved'] or c['lineage_complete']:raise SystemExit('Computed body proof mismatch')
 proofs.append(c)
if len(proofs)!=3:raise SystemExit('Computed subset changed')
oldreasons={r['identity']:(r['reason'],r['resolved']) for r in oldgaps['function_body_match_review']};newreasons={r['identity']:(r['reason'],r['resolved']) for r in newgaps['function_body_match_review']}
if oldreasons!=newreasons or oldgaps['functions_without_exact_body_match']!=newgaps['functions_without_exact_body_match'] or len(newgaps['functions_without_exact_body_match'])!=127:raise SystemExit('Unresolved identities/reasons changed')
rows=json.loads((base/'applied-source-readback.json').read_text())['paths'];final_sources=[]
for row in rows:
 p=root/row['path'];raw=p.read_bytes();mode=stat.S_IMODE(p.stat().st_mode)
 if sha(raw)!=row['after_sha256'] or mode!=row['mode']:raise SystemExit('Final source or mode changed')
 preserved=(base/'before'/row['path']).read_bytes()
 if sha(preserved)!=row['before_sha256']:raise SystemExit('Preserved source bytes mismatch')
 final_sources.append({'path':row['path'],'sha256':sha(raw),'bytes':len(raw),'mode':mode,'preserved_before_sha256':sha(preserved)})
oldtests=ast.parse((base/'before/scripts/tests/collect_schema_domain_map_test.py').read_text());currenttests=ast.parse((root/'scripts/tests/collect_schema_domain_map_test.py').read_text())
def tests(tree):return {c.name+'.'+m.name:ast.dump(m,include_attributes=False) for c in tree.body if isinstance(c,ast.ClassDef) for m in c.body if isinstance(m,ast.FunctionDef) and m.name.startswith('test_')}
before_tests=tests(oldtests);after_tests=tests(currenttests)
if len(before_tests)!=57 or len(after_tests)!=69 or any(after_tests.get(k)!=v for k,v in before_tests.items()):raise SystemExit('Prior test bodies changed')
checks={name:json.loads((base/(name+'.json')).read_text()) for name in ['tests-maintained','generation-maintained','independent-semantic-verification-maintained']}
if any(r['exit_code'] or r['timed_out'] or not r['owned_group_absent'] or not r['held1095inputs_after_match'] for r in checks.values()):raise SystemExit('Command receipt failed')
parity_record={'format':'collect-be08-maintained-literal-replacement-parity-v1','comparison_baseline':str(prior),'schema_all_existing_semantics_equal_except_documented_candidate_metadata_and_generator_binding':parity,'gaps_all_existing_semantics_equal_except_documented_candidate_metadata':gapsparity,'coverage_all_fields_equal':coverageold==coverage,'reviewed_private_semantics_match_maintained_current_semantics':True,'unresolved127_identities_reasons_resolved_flags_exactly_equal':True,'summary':coverage,'caller_sites':len(new['caller_sites']),'objects':len(new['objects']),'input_count':len(manifest['inputs']),'source_files':coverage['maintained_source_files'],'transformation_candidate_count':len(records),'recognized_literal_recipe_count':len(recognized),'computed_body_candidate_count':len(computed),'computed_hash_matches':len(computed),'ambiguous_predecessor_refusals':[{'identity':c['catalog_identity'],'operation_line':c['operation_source']['line'],'reason':c['literal_replacement_computation']['reason'],'predecessor_definition_count':c['literal_replacement_computation']['predecessor_definition_count']} for c in recognized if not c['expected_body_computed']],'input_changes_exactly_two_mapper_rows':changes,'all_other1093input_records_exactly_equal':True,'prior57_test_method_bodies_exactly_preserved':True}
write('semantic-parity-readback.json',parity_record)
write('three-computed-body-readback.json',{'format':'collect-be08-maintained-three-computed-body-readback-v1','method':'actual maintained generator outputs compared to reviewed independent literal extraction and both captured catalogs','reviewed_independent_proof_path':str(prep/'reviewed-final/three-real-computed-body-proofs.json'),'reviewed_independent_proof_sha256':sha((prep/'reviewed-final/three-real-computed-body-proofs.json').read_bytes()),'computed_candidates':proofs,'raw_prosrc_hashes_match_reviewed_expected':True,'overall_unresolved_count':127})
write('final-integration-readback.json',{'format':'collect-be08-maintained-literal-replacement-integration-readback-v1','applied_write_boundary':final_sources,'maintained_write_count':2,'old_modes_preserved':True,'old57tests_preserved':True,'total_maintained_tests_passed':69,'checks':checks,'semantics':parity_record,'source_ownership_released':True,'root_aggregate_source_fence_pending_android_settings_owner':True,'broad_source_fence_captured_by_this_agent':False,'db_or_migration_writes':0,'provider_or_build_calls':0,'full_be08_acceptance_closed':False,'pd12_index_status_register_writes':0})
print(json.dumps({'maintained_tests':69,'all_prior57_preserved':True,'summary_parity':True,'unresolved127_identites_and_reasons_unchanged':True,'inputs':1095,'source_files':668,'input_changes_only_two_mapper_rows':True,'computed':3,'ambiguous':4,'write_boundary':final_sources,'ownership_released':True}))
