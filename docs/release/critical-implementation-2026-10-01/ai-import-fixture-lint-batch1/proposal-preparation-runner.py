from pathlib import Path
import hashlib,json,shutil,difflib,subprocess,os,textwrap,datetime
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');OUT=ROOT/'docs/release/critical-implementation-2026-10-01/ai-import-fixture-lint-batch1';OUT.mkdir(exist_ok=False)
PRIOR=ROOT/'docs/release/critical-implementation-2026-10-01/ai-import-minimization-batch1';rows=json.loads((PRIOR/'source-after.json').read_text())['files'];DENO=ROOT/'.cache/roster-deno-2.5.6-20260929/deno';CACHE=ROOT/'.cache/edge-current-integration-batch1/attempt2/deno-dir';STAGE=ROOT/'.cache/ai-import-fixture-lint-batch1/proposal/source';STAGE.mkdir(parents=True,exist_ok=False)
name='supabase/functions/prepare-roster-import/handler_test.ts';old=(ROOT/name).read_text();assert hashlib.sha256(old.encode()).hexdigest()=='572d7d8b00ba433a4733ad452a2808f0e5d68c32d8f8804694ae717d2ce8222b'
for r in rows:
 p=ROOT/r['path'];assert hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256']
 for base in (OUT/'before',STAGE):
  t=base/r['path'];t.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,t)
(OUT/'source-before.json').write_text(json.dumps({'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'files':rows,'base_source_name':name,'base_sha256':hashlib.sha256(old.encode()).hexdigest()},indent=2)+'\n')
helper='''function fixturePromise<T>(body: () => T): Promise<T> {
  try {
    return Promise.resolve(body());
  } catch (error) {
    return Promise.reject(error);
  }
}
'''
new=old.replace('function fixture() {',helper+'function fixture() {',1)
changes=[('    authenticate: async () => {','    authenticate: () => fixturePromise(() => {','    },\n    configuration:','    }),\n    configuration:'),('    rpc: async (name, args) => {','    rpc: (name, args) => fixturePromise(() => {','    },\n    // This fixture','    }),\n    // This fixture'),('    fetch: async (_url, init) => {','    fetch: (_url, init) => fixturePromise(() => {','    },\n  };\n  return {','    }),\n  };\n  return {')]
checks=[]
for a,b,c,d in changes:
 assert new.count(a)==1 and new.count(c)==1
 body=old.split(a+'\n',1)[1].split(c,1)[0];assert 'await ' not in body
 checks.append({'callback':a.strip(),'old_body_sha256':hashlib.sha256(textwrap.dedent(body).encode()).hexdigest(),'no_await':True})
 new=new.replace(a,b,1).replace(c,d,1)
raw=new;(STAGE/name).write_text(new)
command=[str(DENO),'fmt',str(STAGE/name)];r=subprocess.run(command,text=True,capture_output=True,env={'PATH':os.defpath,'DENO_NO_UPDATE_CHECK':'1','NO_COLOR':'1'},timeout=30)
(OUT/'proposal-format.stdout').write_text(r.stdout);(OUT/'proposal-format.stderr').write_text(r.stderr);assert r.returncode==0
new=(STAGE/name).read_text();(OUT/'proposed-handler_test.ts').write_text(new)
for i,(a,b,c,d) in enumerate(changes):
 key=a.split(':',1)[0].strip()+':'
 if i==0:body=new.split('fixturePromise(() => {\n',1)[1].split('      }),\n    configuration:',1)[0]
 elif i==1:body=new.split('    rpc: (name, args) =>\n      fixturePromise(() => {\n',1)[1].split('      }),\n    // This fixture',1)[0]
 else:body=new.split('    fetch: (_url, init) =>\n      fixturePromise(() => {\n',1)[1].split('      }),\n  };\n  return {',1)[0]
 checks[i]['new_body_sha256']=hashlib.sha256(textwrap.dedent(body).encode()).hexdigest();assert checks[i]['old_body_sha256']==checks[i]['new_body_sha256']
(OUT/'proposed-fixture.patch').write_text(''.join(difflib.unified_diff(old.splitlines(keepends=True),new.splitlines(keepends=True),fromfile='a/'+name,tofile='b/'+name)))
(OUT/'proposed-fixture-raw.patch').write_text(''.join(difflib.unified_diff(old.splitlines(keepends=True),raw.splitlines(keepends=True),fromfile='a/'+name,tofile='b/'+name)))
(OUT/'body-preservation.json').write_text(json.dumps({'callbacks':checks,'new_private_helper':helper,'mechanics':'body() runs synchronously before Promise.resolve; synchronous throws become immediately rejected Promise via catch; no artificial await, deferred .then or suppression','all_callback_bodies_identical_after_dedent':True,'current_body_return_types':['plain actor object','plain SQL result/error object','Response object'],'thenable_identity_limit':'No callback returns a Promise or thenable in this fixture; generic helper is not a claim of identical Promise identity for arbitrary external T'},indent=2)+'\n')
plan={'status':'PROPOSED_ONLY_NOT_APPLIED','path':name,'base_sha256':hashlib.sha256(old.encode()).hexdigest(),'candidate_sha256':hashlib.sha256(new.encode()).hexdigest(),'patch_sha256':hashlib.sha256((OUT/'proposed-fixture.patch').read_bytes()).hexdigest(),'changed_callbacks':3,'case_assertions_and_pdf_scenario_unchanged':old.split('async function errorResponse(',1)[1]==new.split('async function errorResponse(',1)[1],'callbacks':checks,'source_current_unchanged':all(hashlib.sha256((ROOT/r['path']).read_bytes()).hexdigest()==r['sha256'] for r in rows),'proposal_stage':str(STAGE),'root_review_before_apply':True}
assert plan['case_assertions_and_pdf_scenario_unchanged'] and plan['source_current_unchanged'];(OUT/'proposal.json').write_text(json.dumps(plan,indent=2)+'\n');print(json.dumps(plan))
