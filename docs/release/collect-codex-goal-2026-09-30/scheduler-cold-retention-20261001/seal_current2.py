import hashlib,json,pathlib,re,shutil,os
s=pathlib.Path(__file__).resolve().parent;r=s.parents[1];p=s/'accepted-proof-current2';previous=s/'accepted-proof-current1'
def digest(f):return hashlib.sha256(f.read_bytes()).hexdigest()
receipt=json.loads((p/'receipt.json').read_text());assert receipt['status']=='accepted' and receipt['inputs_unchanged']
before=json.loads((p/'inputs-before.json').read_text());after=json.loads((p/'inputs-after.json').read_text());assert before==after
old_before=json.loads((previous/'inputs-before.json').read_text());old_after=json.loads((previous/'inputs-after.json').read_text());assert old_before==old_after
common=set(old_after)&set(before)
assert all(old_after[k]==before[k] for k in common)
assert set(old_after)-set(before)=={'proof/verify_current.py'}
assert set(before)-set(old_after)=={'proof/verify_current_repair.py','stage/supabase/migrations/20261001180000_receipt_operations_enrollment_workflow.sql'}
package=s/'tools/collect-notification-mcp';deps=(package/'node_modules').resolve()
for key,value in after.items():
 if key.startswith('stage/'):f=s/key.removeprefix('stage/')
 elif key.startswith('dependencies/'):f=deps/key.removeprefix('dependencies/')
 elif key=='dependency-root-link':f=package/'node_modules'
 elif key=='runtime/node':f=pathlib.Path('/Volumes/PRO-G40/Development/Node/bin/node').resolve()
 elif key=='runtime/python3':f=pathlib.Path('/usr/bin/python3').resolve()
 elif key=='proof/verify_current_repair.py':f=s/'verify_current_repair.py'
 else:raise AssertionError(key)
 info=f.lstat();assert info.st_mode&0o7777==value['mode'],key
 if value['kind']=='link':assert os.readlink(f)==value['target'],key
 else:assert info.st_size==value['bytes'] and digest(f)==value['sha256'],key
def counts(log):return {kind:int(re.search(r'ℹ '+kind+r' (\d+)',log).group(1)) for kind in ['tests','pass','fail','cancelled','skipped','todo']}
def passed_names(log):return [re.sub(r' \([0-9.]+ms\)$','',row[2:]) for row in log.splitlines() if row.startswith('✔ ')]
old_log=(previous/'family.log').read_text();old_counts=counts(old_log);assert old_counts=={'tests':313,'pass':312,'fail':1,'cancelled':0,'skipped':0,'todo':0}
fresh_log=(p/'observed-fixture.log').read_text();fresh_counts=counts(fresh_log);assert fresh_counts=={'tests':11,'pass':11,'fail':0,'cancelled':0,'skipped':0,'todo':0}
fresh_names=passed_names(fresh_log);assert len(fresh_names)==len(set(fresh_names))==11
old_names=passed_names(old_log);assert len(old_names)==312
reused=[name for name in old_names if name not in fresh_names];assert len(reused)==302
excluded=[name for name in old_names if name in fresh_names];assert len(excluded)==10
preparer=(p/'preparer.log').read_text();prepared=int(re.search(r'Ran (\d+) tests',preparer).group(1));assert prepared==15 and '\nOK\n' in preparer
promote=json.loads((s/'promote-delta-draft.json').read_text());unchanged=[]
for key,value in after.items():
 if not key.startswith('stage/') or value['kind']!='file':continue
 rel=key.removeprefix('stage/');canonical=r/rel
 if canonical.is_file() and digest(canonical)==value['sha256']:unchanged.append(rel)
for record in promote['files']:
 rel=record['path'];source=s/rel;canonical=r/rel
 assert digest(source)==record['staged_sha256'],rel
 assert (digest(canonical) if canonical.is_file() else None)==record['canonical_before_sha256'],rel
 for label,original in [('staged',source),('canonical-before',canonical)]:
  if original.is_file():
   destination=p/'source'/label/rel;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(original,destination)
shutil.copy2(s/'promote-delta-draft.json',p/'promotion-files.json')
shutil.copy2(s/'BASELINE.json',p/'BASELINE.json')
shutil.copy2(s/'verify_current_repair.py',p/'verify_current_repair.py')
shutil.copy2(s/'verify_current.py',p/'verify_preceding_family.py')
shutil.copy2(s/'seal_current2.py',p/'seal_current2.py')
for original in sorted(previous.iterdir()):
 if original.is_file():
  target=p/'preceding-source-bound-family'/original.name;target.parent.mkdir(exist_ok=True);shutil.copy2(original,target)
for name in ['retention-attempt1.log','retention-affected-fix.log','retention-authority-current.log']:
 target=p/'preceding-checks'/name;target.parent.mkdir(exist_ok=True);shutil.copy2(s/name,target)
migration='supabase/migrations/20261001180000_receipt_operations_enrollment_workflow.sql'
assert digest(s/migration)==digest(r/migration)
fixture=p/'fixture-dependency'/migration;fixture.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(s/migration,fixture)
summary={'contract_version':1,'status':'accepted_staged_composed_scope','canonical_integrated':False,'canonical_source_writes':0,
 'composed_current_cases':{'tests':313,'pass':313,'fail':0},'whole_family_successful_rerun':False,
 'reused_unchanged_cases':{'count':302,'names':reused,'input_equivalence_verified':True,'common_declared_inputs':len(common),
    'files':[name for name in json.loads((previous/'receipt.json').read_text())['family_test_files'] if name!='src/unattended_enrollment_observed.test.ts']},
 'affected_refresh':fresh_counts,'affected_file':'src/unattended_enrollment_observed.test.ts',
 'preceding_family':{'counts':old_counts,'exit_code':1,'sole_failure':'missing staging-only enrollment migration fixture','ten_other_old_observed_passes_excluded':True},
 'new_fixture_dependency':{'path':migration,'sha256':digest(s/migration),'canonical_and_provenance_hash_match':True,'only_declared_consumer':'src/unattended_enrollment_observed.test.ts'},
 'preparer_tests':prepared,'typescript_exit_code':0,'input_count':receipt['input_count'],'inputs_unchanged':True,'final_readback_pass':True,
 'promotion_file_count':len(promote['files']),'unchanged_canonical_transitive_files':unchanged,
 'live_http_calls':0,'live_signer_calls':0,'launchctl_daemon_calls':0,'dependencies_resolved':False,
 'complete_operational_recovery_proven':False,'full_candidate_regression_proven':False,
 'export_scope':'bounded cold local evidence only; hot/unresolved journals, credentials, deployment, SQL history and live authority excluded',
 'prior_causal_checks':'preserved, not aggregated; attempt1 29/30, affected-fix 6/7, pre-freeze authority causal check 20/20',
 'receipt_sha256':digest(p/'receipt.json'),'promotion_files_sha256':digest(p/'promotion-files.json')}
(p/'acceptance.json').write_text(json.dumps(summary,sort_keys=True,indent=2)+'\n')
hand=(s/'HANDOFF-DRAFT.md').read_text()+'\nFinal acceptance composes 302 unchanged passing cases from the original source-bound 313-case family with an 11/11 refresh of the observed-fixture file after its missing, unchanged migration was added. The original 312/313 command and its one staging-only failure remain retained; no successful whole-family rerun is claimed. All '+str(len(common))+' common source/dependency/runtime bindings match exactly; the refreshed '+str(receipt['input_count'])+' input set passed before/after and final readback. TypeScript and 15/15 preparer cases passed distinctly. '+str(len(promote['files']))+' files are staged for guarded promotion.\n'
(p/'HANDOFF.md').write_text(hand)
manifest={}
for f in sorted(p.rglob('*')):
 if f.is_file() and f.name!='MANIFEST.json':manifest[str(f.relative_to(p))]={'sha256':digest(f),'bytes':f.stat().st_size}
(p/'MANIFEST.json').write_text(json.dumps({'contract_version':1,'files':manifest},sort_keys=True,indent=2)+'\n')
for rel,meta in manifest.items():assert digest(p/rel)==meta['sha256'] and (p/rel).stat().st_size==meta['bytes']
print(json.dumps({'status':summary['status'],'composed_cases':313,'reused_cases':302,'refreshed_cases':11,'preparer_tests':prepared,'input_count':receipt['input_count'],'common_inputs':len(common),'files':len(manifest),'manifest_sha256':digest(p/'MANIFEST.json'),'acceptance_sha256':digest(p/'acceptance.json'),'packet':str(p)},indent=2))
