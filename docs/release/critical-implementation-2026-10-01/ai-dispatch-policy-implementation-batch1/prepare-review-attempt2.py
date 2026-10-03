from pathlib import Path
import hashlib,json,shutil,difflib,re,textwrap,datetime
ROOT=Path(__file__).resolve().parents[4];OUT=Path(__file__).resolve().parent;BASE=ROOT/'.cache/ai-dispatch-policy-implementation-batch1';STAGE=BASE/'candidate/source'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def tree(base):return {str(p.relative_to(base)):sha(p) for p in sorted(base.rglob('*')) if p.is_file()}
r=json.loads((OUT/'attempt3/verification.json').read_text());assert r['status']=='candidate-pass' and r['source_unchanged'] and r['tools_unchanged']
assert tree(STAGE)==r['candidate_after']
changed=[];patches=[]
for name,digest in r['candidate_after'].items():
 p=STAGE/name;t=OUT/'candidate'/name;t.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,t)
 before=OUT/'before'/name
 if not before.exists() or sha(before)!=digest:
  a=before.read_text() if before.exists() else ''
  b=p.read_text();patch=''.join(difflib.unified_diff(a.splitlines(True),b.splitlines(True),fromfile=('a/'+name if before.exists() else '/dev/null'),tofile='b/'+name));patches.append(patch)
  q=OUT/'patches'/(name+'.patch');q.parent.mkdir(parents=True,exist_ok=True);q.write_text(patch)
  changed.append({'path':name,'base_sha256':sha(before) if before.exists() else None,'candidate_sha256':digest,'candidate_bytes':p.stat().st_size,'patch_sha256':sha(q)})
assert len(changed)==7
(OUT/'full-candidate.patch').write_text(''.join(patches))
name='supabase/functions/_shared/roster_decoder_integration_test.ts';a=(OUT/'attempt2/candidate/source'/name).read_text();b=(STAGE/name).read_text();(OUT/'integration-fixture-lint.patch').write_text(''.join(difflib.unified_diff(a.splitlines(True),b.splitlines(True),fromfile='candidate-before/'+name,tofile='candidate-after/'+name)))
records=json.loads((OUT/'integration-fixture-preservation.json').read_text())
# Callback expressions and bodies are compared after indentation only; string,
# assertion, branch, response and return bytes must remain identical.
pattern=re.compile(r'^( +)(authenticate|fetch|rpc): (\([^\n]*\)) =>\s*fixturePromise\(\(\) => (\([^\n]*\)|\{)',re.M)
newcallbacks=[]
for m in pattern.finditer(b):
 indent,field,args,expr=m.groups()
 if expr=='{':
  end=re.search(r'^'+indent+r'  \}\),$',b[m.end():],re.M);assert end
  body=b[m.end():m.end()+end.start()]
 else: body=expr
 newcallbacks.append((field,body))
assert len(newcallbacks)==6
for item,(field,body) in zip(records['callbacks'],newcallbacks):
 assert field==item['callback']
 original=item['original'];oldbody=original.split('=> ',1)[1]
 if oldbody.startswith('{'):oldbody=oldbody[1:oldbody.rfind('}')]
 else:oldbody=oldbody[:-1]
 item['formatted_body_sha256']=hashlib.sha256(textwrap.dedent(body).encode()).hexdigest()
 item['original_dedented_body_sha256']=hashlib.sha256(textwrap.dedent(oldbody).encode()).hexdigest()
 item['formatted_body_equals_original_after_dedent']=item['formatted_body_sha256']==item['original_dedented_body_sha256']
 assert item['formatted_body_equals_original_after_dedent'],field
records['formatted_bodies_preserved']=True;(OUT/'integration-fixture-preservation-final.json').write_text(json.dumps(records,indent=2)+'\n')
old=(OUT/'before/supabase/functions/prepare-roster-import/handler_test.ts').read_text()
new=(STAGE/'supabase/functions/prepare-roster-import/handler_test.ts').read_text()
suffix=old.split('async function errorResponse(',1)[1]
new_suffix=new.split('async function errorResponse(',1)[1].split('// AI dispatch policy cases use synthetic approval assertions only.',1)[0]
assert suffix.rstrip('\n')==new_suffix.rstrip('\n'),'original case/assertion suffix changed'
(OUT/'original-case-preservation.json').write_text(json.dumps({'original_test_case_suffix_sha256':hashlib.sha256(suffix.rstrip('\n').encode()).hexdigest(),'candidate_original_test_case_suffix_sha256':hashlib.sha256(new_suffix.rstrip('\n').encode()).hexdigest(),'all_original_cases_and_assertions_unchanged':True,'boundary_only_difference':'one separating blank line before new policy cases','fixturePromise_preserved':old.split('function fixturePromise<T>',1)[1].split('function fixture()',1)[0]==new.split('function fixturePromise<T>',1)[1].split('function fixture()',1)[0]},indent=2)+'\n')
proposal={'status':'PRIVATE_CANDIDATE_ROOT_REVIEW_REQUIRED','shared_promotion':False,'shared22_unchanged':{r['path']:sha(ROOT/r['path']) for r in json.loads((OUT/'source-before.json').read_text())['files']}==r['shared_before'],'source_stage':str(STAGE),'full_patch_sha256':sha(OUT/'full-candidate.patch'),'candidate_inputs':len(r['candidate_after']),'changed_files':changed,'candidate_checks':r['phases'],'candidate_tests':{'passed':213,'failed':0,'original109_unchanged':True,'new_handler_policy_cases':53,'validator_cases':25,'existing_decoder_unit_cases':26},'old_source_new_tests':{'passed':112,'failed':50,'all_original109_pass':True,'expected_failures_preserved':True},'integration_fixture_lint_before':6,'integration_fixture_lint_after':0,'integration_fixture_callbacks_preserved':6,'real_linux_http_acceptance_executed':False,'real_provider_calls':0,'actual_policy_approval_or_vendor_acceptance':False,'whole_BE13_closed':False,'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
assert proposal['shared22_unchanged']
(OUT/'proposal.json').write_text(json.dumps(proposal,indent=2)+'\n')
print(json.dumps({'status':proposal['status'],'changed_files':len(changed),'candidate_inputs':proposal['candidate_inputs'],'full_patch_sha256':proposal['full_patch_sha256'],'proposal_sha256':sha(OUT/'proposal.json'),'shared22_unchanged':proposal['shared22_unchanged']}))
