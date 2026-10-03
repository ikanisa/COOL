from pathlib import Path
import hashlib,json,datetime
ROOT=Path(__file__).resolve().parents[4];OUT=Path(__file__).resolve().parent
BASE=ROOT/'.cache/ai-dispatch-policy-implementation-batch1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def tree(p):return {str(f.relative_to(p)):sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
errors=[];index=json.loads((OUT/'evidence-index.json').read_text());batch=json.loads((OUT/'batch.json').read_text())
for row in index['files']:
 p=ROOT/row['path']
 if p.is_symlink() or not p.is_file() or p.stat().st_size!=row['bytes'] or sha(p)!=row['sha256']:errors.append(row['path'])
if sha(OUT/'evidence-index.json')!=batch['evidence_index']['sha256']:errors.append('index')
proposal=json.loads((OUT/'proposal.json').read_text());final=json.loads((OUT/'attempt3/verification.json').read_text())
if proposal['shared_promotion'] or not proposal['shared22_unchanged'] or proposal['real_linux_http_acceptance_executed'] or proposal['whole_BE13_closed']:errors.append('scope approval flags')
if sha(OUT/'full-candidate.patch')!=proposal['full_patch_sha256']:errors.append('review patch')
if tree(BASE/'candidate/source')!=final['candidate_after'] or tree(OUT/'candidate')!=final['candidate_after']:errors.append('private candidate')
for name,digest in final['shared_after'].items():
 if sha(ROOT/name)!=digest:errors.append('current:'+name)
for attempt in ['attempt1','attempt2','attempt3']:
 r=json.loads((OUT/attempt/'verification.json').read_text())
 if not r['source_unchanged'] or not r['tools_unchanged']:errors.append(attempt+':phase source/tool drift')
 for name,digest in r['remote_after'].items():
  if sha(BASE/attempt/'deno-dir/remote'/name)!=digest:errors.append(attempt+':remote:'+name)
 if attempt!='attempt3':
  for stage in ['old','candidate']:
   if tree(OUT/attempt/stage/'source')!=r[stage+'_after']:errors.append(attempt+':frozen '+stage)
  if sha(OUT/attempt/'verify_private.py')!=r['runner_after']:errors.append(attempt+':runner')
 else:
  if sha(OUT/'verify_private.py')!=r['runner_after']:errors.append(attempt+':runner')
 phases={p['label']:p['exit_code'] for p in r['phases']}
 if phases.get('old-types',0)!=0 or phases.get('old-tests',1)!=1:errors.append(attempt+':old baseline phases')
 if attempt=='attempt1':
  if phases['candidate-types']!=0 or phases['candidate-tests']!=0 or phases['candidate-lint']!=1 or phases['candidate-format']!=0:errors.append('attempt1 original phases')
  if r['old-tests_summaries']!=[['112','40','']] or r['candidate-tests_summaries']!=[['203','0','']]:errors.append('attempt1 counts')
 else:
  if any(v for k,v in phases.items() if k.startswith('candidate')) or phases['baseline-integration-lint']!=1:errors.append(attempt+':candidate/baseline phases')
  if r['candidate-tests_summaries']!=[['213','0','']]:errors.append(attempt+':candidate count')
  if attempt=='attempt2' and r['old-tests_summaries']!=[['112','50','']]:errors.append('attempt2 old count')
if sha(ROOT/'.cache/roster-deno-2.5.6-20260929/deno')!=final['runtime_after']:errors.append('pinned Deno')
if not json.loads((OUT/'original-case-preservation.json').read_text())['all_original_cases_and_assertions_unchanged']:errors.append('original cases')
if not json.loads((OUT/'integration-fixture-preservation-final.json').read_text())['formatted_bodies_preserved']:errors.append('six fixture bodies')
prior=json.loads((OUT/'prior-packets-readback.json').read_text())
for record in prior['packets']:
 packet=OUT.parent/record['packet']
 if sha(packet/'batch.json')!=record['batch_sha256'] or sha(packet/'evidence-index.json')!=record['index_sha256']:errors.append('prior seal:'+record['packet'])
 for row in json.loads((packet/'evidence-index.json').read_text())['files']:
  p=ROOT/row['path']
  if not p.is_file() or p.stat().st_size!=row['bytes'] or sha(p)!=row['sha256']:errors.append('prior leaf:'+row['path'])
receipt={'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'pass' if not errors else 'fail','new_indexed_leaves':len(index['files']),'maintained_source_inputs':len(final['shared_after']),'private_candidate_inputs':len(final['candidate_after']),'remote_cache_inputs_per_phase':len(final['remote_after']),'prior_leaves':prior['indexed_leaves'],'batch_sha256':sha(OUT/'batch.json'),'index_sha256':sha(OUT/'evidence-index.json'),'candidate_patch_sha256':sha(OUT/'full-candidate.patch'),'shared_promotion':False,'real_linux_http_acceptance':False,'whole_BE13_closed':False,'production_acceptance':False,'errors':errors}
with (OUT/'seal-readback.json').open('x') as p:p.write(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt));raise SystemExit(0 if not errors else 1)
