from pathlib import Path
import ast,copy,difflib,hashlib,importlib.util,json,re,sys
root=Path.cwd();base=root/'docs/release/critical-implementation-2026-10-01/be08-literal-replacement-preparation1';final=base/'reviewed-final';baseline=base.parent/'root-be08-post-integration-current2091/generated-current209';output=final/'generated-current209'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def write(name,data):(final/name).write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')
# Actual held source hashes: every catalog, replay, maintained source, migration,
# generator and seam input from the current209 baseline, plus owned test fences.
prior=json.loads((base/'current209-input-fences-before.json').read_text());after=[]
for row in prior['inputs']:
 p=Path(row['path']);p=p if p.is_absolute() else root/p;raw=p.read_bytes()
 observed={**row,'observed_sha256':sha(raw),'observed_bytes':len(raw),'unchanged':sha(raw)==row['sha256'] and len(raw)==row['bytes']}
 after.append(observed)
if not all(r['unchanged'] for r in after):raise SystemExit('Held current209 source drift')
owned=json.loads((base/'source-fences-before.json').read_text())['paths']
for row in owned:
 if sha((root/row['path']).read_bytes())!=row['sha256']:raise SystemExit('Owned source fence drift: '+row['path'])
write('source-fences-after.json',{'format':'collect-be08-private-input-readback-v1','all_1095_current209_inputs_unchanged':True,'all_6_selected_sources_unchanged':True,'inputs':after,'selected_sources':owned})
# Exact old test method bodies retained, not just test counts.
def methods(text):
 return {c.name+'.'+m.name:ast.dump(m,include_attributes=False) for c in ast.parse(text).body if isinstance(c,ast.ClassDef) for m in c.body if isinstance(m,ast.FunctionDef) and m.name.startswith('test_')}
oldtests=methods((base/'before/scripts/tests/collect_schema_domain_map_test.py').read_text());newtests=methods((base/'proposal/scripts/tests/collect_schema_domain_map_test.py').read_text())
if not all(newtests.get(k)==v for k,v in oldtests.items()):raise SystemExit('Old test method changed')
# Build exact two-file patch; companion seams are an unchanged private support copy.
patch='';proposed=[]
for rel in ['scripts/audits/collect_schema_domain_map.py','scripts/tests/collect_schema_domain_map_test.py']:
 before=(base/'before'/rel).read_bytes();new=(base/'proposal'/rel).read_bytes()
 patch+=''.join(difflib.unified_diff(before.decode().splitlines(keepends=True),new.decode().splitlines(keepends=True),fromfile='a/'+rel,tofile='b/'+rel))
 proposed.append({'path':rel,'before_sha256':sha(before),'after_sha256':sha(new),'before_bytes':len(before),'after_bytes':len(new),'private_proposed_path':str(base/'proposal'/rel)})
(final/'literal-replacement.patch').write_text(patch)
write('patch-readback.json',{'format':'collect-be08-private-patch-readback-v1','maintained_mutations':0,'write_boundary':proposed,'patch_sha256':sha(patch.encode()),'old_test_methods_preserved':len(oldtests),'new_test_methods':sorted(set(newtests)-set(oldtests)),'total_test_methods':len(newtests),'unchanged_support_copy':'proposal/scripts/audits/collect_schema_domain_caller_seams.json'})
# Retain every existing semantic field except the explicitly computed candidate
# fields and private-generator manifest binding/path. Compare whole documents.
before_doc=json.loads((baseline/'schema-domain-map.json').read_text());after_doc=json.loads((output/'schema-domain-map.json').read_text())
before_gaps=json.loads((baseline/'gaps.json').read_text());after_gaps=json.loads((output/'gaps.json').read_text())
def normalize_candidate(c):
 c.pop('literal_replacement_computation',None)
 c['expected_body_computed']=False;c['expected_body_hash_match']=None
 c['limitations']=['anonymous effects and variable/control-flow state unproved','replacement scope and literal/E-string decoding unproved','predecessor installed state and effective history unproved']
def normalized(doc,gaps=False):
 value=copy.deepcopy(doc)
 if not gaps:
  value.pop('input_manifest_sha256',None)
  rows=[o['source_match_review'] for o in value['objects'] if 'source_match_review' in o]
 else:rows=value['function_body_match_review']
 for row in rows:
  for c in row['transformation_candidates']:normalize_candidate(c)
 return value
semantic=normalized(before_doc)==normalized(after_doc);gap_parity=normalized(before_gaps,True)==normalized(after_gaps,True)
coverage_parity=json.loads((baseline/'coverage.json').read_text())==json.loads((output/'coverage.json').read_text())
if not(semantic and gap_parity and coverage_parity):raise SystemExit('Unintended existing semantics changed')
old_manifest=json.loads((baseline/'input-manifest.json').read_text());new_manifest=json.loads((output/'input-manifest.json').read_text())
manifest_old={(r['kind'],r['path']):r for r in old_manifest['inputs']};manifest_new={(r['kind'],r['path']):r for r in new_manifest['inputs']}
removed=[r for k,r in manifest_old.items() if k not in manifest_new];added=[r for k,r in manifest_new.items() if k not in manifest_old]
shared=[k for k in manifest_old if k in manifest_new];changed_shared=[k for k in shared if manifest_old[k]!=manifest_new[k]]
if len(removed)!=2 or len(added)!=2 or changed_shared or {r['kind'] for r in removed}!={'generator-proposal','reviewed-caller-seams'}:raise SystemExit('Unexpected private execution manifest boundary')
records=[c for o in after_doc['objects'] if 'source_match_review' in o for c in o['source_match_review']['transformation_candidates']]
recognized=[c for c in records if 'literal_replacement_computation' in c];computed=[c for c in records if c['expected_body_computed']]
if len(computed)!=3 or any(c['resolved'] or c['lineage_complete'] or c['expected_body_hash_match'] is not True for c in computed):raise SystemExit('Computed subset or unresolved flags changed')
write('semantic-parity-readback.json',{'format':'collect-be08-private-semantic-parity-v1','comparison_baseline':str(baseline),'coverage_all_fields_equal':coverage_parity,'schema_all_existing_semantics_equal_except_documented_candidate_metadata_and_generator_binding':semantic,'gaps_all_existing_semantics_equal_except_documented_candidate_metadata':gap_parity,'unresolved127_list_exactly_equal':before_gaps['functions_without_exact_body_match']==after_gaps['functions_without_exact_body_match'],'summary':after_doc['summary'],'caller_sites':len(after_doc['caller_sites']),'objects':len(after_doc['objects']),'inputs':len(new_manifest['inputs']),'transformation_candidates':len(records),'recognized_literal_recipes':len(recognized),'computed_literal_body_candidates':len(computed),'computed_hash_matching_candidates':sum(c['expected_body_hash_match'] is True for c in records),'uncomputed_ambiguous_predecessor_candidates':[{'identity':c['catalog_identity'],'line':c['operation_source']['line'],'reason':c['literal_replacement_computation']['reason'],'predecessor_definition_count':c['literal_replacement_computation']['predecessor_definition_count']} for c in recognized if not c['expected_body_computed']],'private_manifest_changes':{'removed':removed,'added':added,'unchanged_shared_count':len(shared),'changed_shared':changed_shared}})
# Independent extraction uses the unchanged maintained body's static parser,
# literal delimiters in exact bounded source line ranges, and hashlib directly.
source=root/'scripts/audits/collect_schema_domain_map.py';spec=importlib.util.spec_from_file_location('maintained_map',source);m=importlib.util.module_from_spec(spec);sys.modules[spec.name]=m;spec.loader.exec_module(m)
original=root/'supabase/migrations/20261001140000_receipt_deferral_exceptions.sql';original_text=original.read_text();defs=m.sql_definitions(original_text,original.relative_to(root).as_posix(),'20261001140000')
clean=root/'docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/observed-output/ordinary_clean/final-effective-catalog.json';peer=clean.parent.parent/'ordinary_populated/final-effective-catalog.json';catalog=json.loads(clean.read_text())
if json.loads(peer.read_text())!=catalog:raise SystemExit('Peer catalog mismatch')
expected=[('queue_receipt_exception_source','20261001210000_receipt_worker_bounded_sweep.sql',50,60,802,'368e24280a4071f19e619f71438e4334b75d1b8bb534f13ffa0d9207004df8c5','$patch$','$patch$'),('receipt_exception_quota_available','20261001210000_receipt_worker_bounded_sweep.sql',86,93,1002,'92b8e73053749e3cc21ae9ba9b497220edc582214f344cd72301b842c80089e9','$patch$','$patch$'),('capture_receipt_backlog_budget_refusal','20261002080000_receipt_repeat_run_recovery.sql',125,150,490,'403688ec34f93edba0670241442d26a153c0aa48dd22d2f50c79fbb22fc7d6df','$old$','$new$')]
proofs=[]
for name,filename,start_line,end_line,expected_bytes,expected_hash,needle_tag,replacement_tag in expected:
 text=(root/'supabase/migrations'/filename).read_text();region=''.join(text.splitlines(keepends=True)[start_line-1:end_line])
 # Extract the first and second dollarquoted literals in this exact recipe range.
 first_start=region.index(needle_tag)+len(needle_tag);first_end=region.index(needle_tag,first_start);needle=region[first_start:first_end]
 second_start=region.index(replacement_tag,first_end+len(needle_tag))+len(replacement_tag);second_end=region.index(replacement_tag,second_start);replacement=region[second_start:second_end]
 definitions=[d for d in defs if d['schema']=='collect_ops' and d['name']==name]
 if len(definitions)!=1:raise SystemExit('Independent literal source ambiguity')
 definition=definitions[0];rawbody=definition['body'];rawexpected=rawbody.replace(needle,replacement).encode()
 rows=[r for r in catalog['functions'] if r[0]=='collect_ops' and r[1]==name];candidates=[c for c in computed if c['target']['name']==name]
 if len(rows)!=1 or len(candidates)!=1 or rawbody.count(needle)!=1 or len(rawexpected)!=expected_bytes or sha(rawexpected)!=expected_hash or rows[0][11]!=expected_hash:raise SystemExit('Independent rawbody replacement proof failed')
 candidate=candidates[0];candidate_proof=candidate['literal_replacement_computation']
 if candidate_proof['computed_prosrc_sha256']!=expected_hash or candidate_proof['computed_prosrc_utf8_bytes']!=expected_bytes:raise SystemExit('Private evaluator differs from independent extraction')
 proofs.append({'identity':candidate['catalog_identity'],'rawbody_only':True,'original_literal_definition':{'path':definition['path'],'line':definition['line'],'prosrc_sha256':definition['prosrc_sha256'],'utf8_bytes':len(rawbody.encode())},'recipe':{'path':'supabase/migrations/'+filename,'bounded_line_start':start_line,'bounded_line_end':end_line,'needle_utf8_bytes':len(needle.encode()),'needle_sha256':sha(needle.encode()),'replacement_utf8_bytes':len(replacement.encode()),'replacement_sha256':sha(replacement.encode())},'needle_occurrences':rawbody.count(needle),'computed_prosrc_utf8_bytes':len(rawexpected),'computed_prosrc_sha256':sha(rawexpected),'clean_catalog_prosrc_sha256':rows[0][11],'peer_catalog_prosrc_sha256':next(r[11] for r in json.loads(peer.read_text())['functions'] if r[0]=='collect_ops' and r[1]==name),'all_hashes_match':True,'private_candidate':candidate,'overall_source_review_resolved':False,'overall_source_review_lineage_complete':False})
write('three-real-computed-body-proofs.json',{'format':'collect-be08-three-real-literal-body-proofs-v1','method':'independent bounded dollar-delimiter extraction + unchanged maintained static literal body parser + hashlib SHA-256; no PostgreSQL evaluation or DDL reconstruction','catalog_paths':[str(clean),str(peer)],'catalog_sha256':[sha(clean.read_bytes()),sha(peer.read_bytes())],'proofs':proofs,'all_three_match':True,'overall_unresolved_count_preserved':127})
print(json.dumps({'old_tests_preserved':len(oldtests),'new_tests':len(newtests)-len(oldtests),'total_tests':len(newtests),'all1095inputs_unchanged':True,'semantic_parity':semantic,'gap_parity':gap_parity,'coverage_parity':coverage_parity,'computed':len(computed),'three_real_independent_proofs_match':True,'patch_sha256':sha(patch.encode()),'proposed_sources':proposed}))
