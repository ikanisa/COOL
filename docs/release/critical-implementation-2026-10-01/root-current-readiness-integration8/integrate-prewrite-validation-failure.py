from pathlib import Path
import json,hashlib,datetime,copy
R=Path.cwd();B=R/'docs/release/critical-implementation-2026-10-01';P=B/'root-current-readiness-checkpoint8-preparation1';O=B/'root-current-readiness-integration8';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();dump=lambda j:(json.dumps(j,indent=2,ensure_ascii=False)+'\n').encode();now=datetime.datetime.now(datetime.timezone.utc).isoformat();fences=json.loads((O/'before-fences.json').read_text())['before_sha256']
for n,h in fences.items():assert sha(R/n)==h,n
plan=json.loads((P/'checkpoint8-update-plan.json').read_text());updates=json.loads((P/'ledger-item-updates.json').read_text());cp=json.loads((P/'checkpoint8.json').read_text());lp=plan['ledger']['path'];old=json.loads((R/lp).read_text());L=copy.deepcopy(old)
def ref(n):return {'path':n,'sha256':sha(R/n)}
newrefs=[ref('docs/release/critical-implementation-2026-10-01/'+n) for n in ['pd12-current-evidence-index-integration1/packet-files.json','pd12-current-evidence-index-integration1/status-note.json','root-pd12-original-criterion-review1/review.json','arc09-production-aab-observation9/packet-files.json','root-arc09-aab-failure-readback9/readback.json','root-arc09-current-graph-readback9/readback.json','root-readonly-r8-kotlin-compatibility1/compatibility-readback.json']]
refs=plan['ledger']['append_verified_current_readback_entries_without_rewriting_old_results']+newrefs
for e in refs:assert sha(R/e['path'])==e['sha256'],e['path']
cp['captured_at_utc']=now;cp['closed_ids'].append('PD-12');cp['full_findings_open']=33;cp['native_packages_built']=False
cp['current_native_retry']['unsigned_AAB']='attempt9_config_and_fresh_graphs_PASS_AAB159.1s_FAIL_missing_offline_lint32.0.1_R8_9.0.32_below_Kotlin2.4_floor'
cp['ARC09_actual_attempt9']={'AAB_seconds':159.1,'AAB_exit_code':1,'default_Proguard_producer_readback':'PASS','runtime_graph':{'exit_code':0,'seconds':41.251,'components':173,'edges':995,'artifacts':141},'compile_graph':{'exit_code':0,'seconds':36.259,'components':64,'edges':296,'artifacts':47},'graph_JSON_equals_prior_selected_graphs':True,'missing_offline_artifact':'com.android.tools.lint:lint-gradle:32.0.1','embedded_R8':'9.0.32','KGP_and_locked_stdlib':'2.4.20','required_R8_for_Kotlin2.4':'9.1.29','R8_metadata_warnings':5,'source_SDK_protected_guards':'PASS','observed_owned_groups_absent':True,'lint_and_shrinking_enabled':True,'package_and_SBOM_acceptance':False,'next':'Prepare verified exact lint tooling cache and compatible R8 override; then actual package/artifact consumers.'}
cp['PD12_current_index']={'status':'original_current_index_reconciliation_criterion_met_in_declared_epoch','tests':14,'schema_validation':'PASS','authority_hygiene':'PASS','reader_seconds':4.36327883299964,'reader_exit_code':1,'facts_matched':101,'file_sets':26,'expected_archived_Android2_drift_rows':2,'other_drift_or_unknown_physical_entries':0,'full_finding_closed':True,'whole_graph_native_visual_or_release_acceptance':False,'current_source_epoch':'1c55bbe1af164ec66a146ca3d0e2256e38ab3423647694c7ee8f37faccffeac0','later_source_epochs_require_rebinding':True}
for e in newrefs:
 if e not in cp['references']:cp['references'].append(e)
L['previous_checkpoint_before_update8']=L['latest_checkpoint'];L['latest_checkpoint']=cp;L['captured_at_utc']=now
L['candidate_status']='Current index original PD12 criterion met for declared2563/1c55 epoch; archived app/native outcomes remain scoped. Actual attempt9 config/graphs pass, package fails missing lint32.0.1 and retains R8/Kotlin compatibility gap. Next source epochs and package consumers require exact new bindings; no release approval.'
for item in L['items']:
 if item['id'] in updates:
  u=updates[item['id']];item.update(u['replace'])
  for e in u['append_unique_evidence_packets']:
   if e not in item['evidence_packets']:item['evidence_packets'].append(e)
 if item['id']=='ARC-09':
  item['implementation_status']='attempt9_config_graphs_pass_AAB_failed_missing_lint32_R8_compatibility_correction_preparing'
  item['next_action']='Original archived native12/20 and app1114/41 outcomes remain scoped. Reviewed Android directory fix passes actual Proguard producer check and fresh canonical runtime/compile graphs, whose JSON is identical to the previous selected graphs. AAB9 exits1 after159.1s because offline lint-gradle32.0.1 is absent. Five R8 metadata warnings correspond to embedded9.0.32 below published9.1.29 floor for Kotlin2.4.20. Preserve lint/shrinking, admit exact verified lint tooling cache and compatible standalone R8, then run actual assembly and artifact-bound reader/SBOM. Complete licence/fork/frozen/provider and signed IPA/web artifact scopes. OSV157 is a retained dated exact-version query, not full package acceptance.'
  item['evidence_packets']+= [e for e in newrefs[3:] if e not in item['evidence_packets']]
 if item['id']=='PD-12':
  item['implementation_status']='closed_original_current_index_reconciliation_criterion_in_declared2563_source_epoch'
  item['acceptance_status']='closed_scoped_current_index_reconciliation';item['full_finding_closed']=True
  item['next_action']='Original criterion met: current index actually checks declared relevant source/transitive/artifact bytes, preserves superseded outcomes and explicitly separates unverified scopes. Fourteen tests, Draft2020-12 schema and authority hygiene pass;101 facts/26 sets verify with exactly two intentionally retained archived-vs-current Android drift rows. This is not whole graph, native, visual, font-rights, hosted or release acceptance. Maintain a newly bound index for subsequent source epochs and actual package results.'
  item['evidence_packets'] += [e for e in newrefs[:3] if e not in item['evidence_packets']]
for e in refs:L['evidence_current_readback'][e['path']]={'checked_at_utc':now,'sha256':e['sha256'],'scope':'Retained named actual result/proposal in its own declared scope; no entire checkout/provider/release acceptance.'}
contracts=lambda j:[tuple(i.get(k) for k in ('id','title','report','status','review_status','acceptance_requirement_from_report')) for i in j['items']]
assert contracts(L)==contracts(old);assert len(L['items'])==40
closed=[i['id'] for i in L['items'] if i['full_finding_closed']];assert set(closed)==set(cp['closed_ids']) and len(closed)==7
out={lp:dump(L)};ledgerhash=hashlib.sha256(out[lp]).hexdigest()
for n in plan['legacy_extensions']['paths']:
 original=json.loads((R/n).read_text());j=copy.deepcopy(original);ex=j['critical_review_implementation_extension'];ex['previous_checkpoint_before_update8']=ex['latest_checkpoint'];ex['latest_checkpoint']=cp;ex['captured_at_utc']=now;ex['sha256']=ledgerhash;ex['specialist_findings_closed']=7
 ex['closed_scope']=str(ex['closed_scope'])+' PD-12 original current-index reconciliation criterion is now closed only for declared2563/1c55 source epoch; later epochs require new bindings.'
 ex['current_integration_note']=L['candidate_status'];ex['current_schema_progress_note']='Actual current209 mapper:1095 inputs/668 sources/718 callers,57 tests pass,127 unresolved functions and37 additive transformation candidates preserved; ownership/history remain open.'
 for e in refs:
  if e not in ex['latest_scoped_evidence']:ex['latest_scoped_evidence'].append(e)
 assert j['items']==original['items'];out[n]=dump(j)
mdplan=json.loads((P/'markdown-update-plan.json').read_text());texts={n:(R/n).read_text() for n in fences if n.endswith('.md')};history={n:t[t.index('Historical checkpoint —'):] for n,t in texts.items() if 'Historical checkpoint —' in t}
for e in mdplan['exact_replacements']:
 n=e['path'];assert texts[n].count(e['old'])==1,(n,e['old'][:40]);texts[n]=texts[n].replace(e['old'],e['new'],1)
for n,t in texts.items():
 prefix,sep,hist=t.partition('Historical checkpoint —');prefix=prefix.replace('2026-10-02T14:14:26.447056+00:00',now).replace('**6 original findings closed; 34 open in full.','**7 original findings closed; 33 open in full.').replace('**34 of 40 original findings','**33 of 40 original findings')
 paras=prefix.split('\n\n')
 for i,s in enumerate(paras):
  if s.startswith('The prior native8 run'):
   paras[i]='Archived native8 results retain their original source scope. The reviewed two-file Android directory fix passes the actual default-Proguard producer check, with shrinking enabled. Fresh runtime/compile graphs pass (173/64 components) and equal the prior parsed graphs. AAB9 fails after159.1s at release lint because exact lint-gradle32.0.1 is absent offline; embedded R8 9.0.32 also falls below the published9.1.29 floor for Kotlin2.4.20. Source/SDK/protected and observed owned-group readbacks pass. Exact lint-cache and R8 correction are being prepared; no package/SBOM/release acceptance is claimed.'
  elif s.startswith('Prior captured app/backend/SQL/native8 results'):
   paras[i]='Archived app/backend/SQL/native results retain their recorded source scope. Current ARC-03 tests and57 mapper tests pass; fresh current209 verification preserves127 unresolved functions. AAB9 passes configuration/graphs and then fails on missing offline lint tooling, with a confirmed R8/Kotlin compatibility gap. PD-12 current-index reconciliation meets its original criterion for declared2563 source:14 tests, schema/hygiene pass and101 facts with exactly two archived Android drift rows. No package or release acceptance is asserted.'
  elif 'PD-12 final index review remains pending.' in s:
   paras[i]=s.replace('PD-12 final index review remains pending.','[PD-12 current-index review](root-pd12-original-criterion-review1/review.json) records its scoped original-criterion closure; later source epochs require new bindings.')
  elif 'Current-index scripts' in s or ('PD-12' in s and 'final review pending' in s and not s.startswith('|')):
   paras[i]='PD-12 original current-index reconciliation criterion is met for the declared source epoch. The maintained verifier passes14 tests and schema validation; required authority hygiene passes. Actual101 facts/26 sets retain exactly two archived-vs-current Android differences and match all other listed bindings, while full graph/native/visual/provider/release acceptance stays unverified.'
 prefix='\n\n'.join(paras)
 lines=[]
 for s in prefix.splitlines():
  if s.startswith('| ARC-09 |'):
   s='| ARC-09 | Complete licence/fork/frozen and AAB/IPA/web SBOM acceptance; correct missing offline lint32.0.1 and R8/Kotlin compatibility, then verify an actual package. |' if 'CURRENT_OPEN_' in n else '| ARC-09 | P1: fork/dependency governance is uneven across ecosystems | actual directory/graph checks pass; package fails missing lint tooling; R8 compatibility correction pending | Open |'
  if s.startswith('| PD-12 |'):
   if 'CURRENT_OPEN_' in n:continue
   s='| PD-12 | Medium: typography and public acceptance summaries describe superseded input states | actual current index14 tests/schema/hygiene/101 facts, expected archived drift explicit | Closed in original recorded scope |'
  if s.startswith('The previous 37 count included'):
   s='The previous37 count included ARC-01, ARC-02, BE-10 and PD-12; those now meet their original criteria. ARC-04, PD-02 and PD-14 retain earlier closure scopes. Original102 production rows and24 local rows are unchanged.'
  if s.startswith('New closures:'):s += ' PD-12 now closes its original current-index reconciliation criterion; full native/visual/provider/release acceptance remains separate.'
  lines.append(s)
 prefix='\n'.join(lines)+('\n' if prefix.endswith('\n') else '')
 full=prefix+sep+hist
 if n in history:assert full[full.index('Historical checkpoint —'):]==history[n],n
 out[n]=full.encode()
assert sum(1 for s in out['docs/release/critical-implementation-2026-10-01/CURRENT_OPEN_FINDINGS_2026-10-02.md'].decode().splitlines() if s.startswith('| BE-') or s.startswith('| ARC-') or s.startswith('| PD-'))==33
for n in out:assert sha(R/n)==fences[n],n
for n,data in out.items():
 with (R/n).open('wb') as w:w.write(data)
for n,data in out.items():assert (R/n).read_bytes()==data,n
receipt={'captured_at_utc':now,'before_sha256':fences,'after_sha256':{n:sha(R/n) for n in out},'contracts40_unchanged':True,'legacy102_24_arrays_unchanged':True,'historical_markdown_bodies_unchanged':True,'closed_ids':closed,'full_open':33,'PD12_scoped_original_criterion_closed':True,'source_epoch':'1c55bbe1af164ec66a146ca3d0e2256e38ab3423647694c7ee8f37faccffeac0','AAB9_result':'FAIL_missing_lint32.0.1_with_R8_compatibility_gap','production_release_decision':'NO-GO','goal_status':'active','new_references':newrefs};(O/'receipt.json').write_bytes(dump(receipt));print(json.dumps(receipt,indent=2))
