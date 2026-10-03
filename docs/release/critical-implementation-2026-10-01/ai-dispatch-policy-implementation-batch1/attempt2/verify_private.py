from pathlib import Path
import hashlib,json,shutil,subprocess,os,time,datetime,sys,re
ROOT=Path(__file__).resolve().parents[4];OUT=Path(__file__).resolve().parent
BASE=ROOT/'.cache/ai-dispatch-policy-implementation-batch1'
DENO=ROOT/'.cache/roster-deno-2.5.6-20260929/deno'
ORIGINAL_CACHE=ROOT/'.cache/edge-current-integration-batch1/attempt2/deno-dir'
EXPECTED=json.loads((OUT/'source-before.json').read_text())['files']
MODE=sys.argv[1]; assert MODE in ('attempt1','attempt2','attempt3')
RUN=OUT/MODE;RUN.mkdir(exist_ok=False)
CACHE=BASE/MODE/'deno-dir';CACHE.mkdir(parents=True,exist_ok=False)
shutil.copytree(ORIGINAL_CACHE/'remote',CACHE/'remote')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def tree(base): return {str(p.relative_to(base)):sha(p) for p in sorted(base.rglob('*')) if p.is_file()}
def current(): return {r['path']:sha(ROOT/r['path']) for r in EXPECTED}
def remotes(): return tree(CACHE/'remote')
entries=['supabase/functions/_shared/openai_roster_test.ts','supabase/functions/_shared/roster_response_policy_test.ts','supabase/functions/prepare-roster-import/handler_test.ts','scripts/tests/roster_extraction_evaluation_test.ts']
candidate_entries=entries+['supabase/functions/_shared/roster_ai_dispatch_policy_test.ts','supabase/functions/_shared/roster_decoder_test.ts']
owned=['supabase/functions/_shared/roster_ai_dispatch_policy.ts','supabase/functions/_shared/roster_ai_dispatch_policy_test.ts','supabase/functions/_shared/roster_ai_dispatch_test_fixture.ts','supabase/functions/prepare-roster-import/handler.ts','supabase/functions/prepare-roster-import/handler_test.ts','supabase/functions/prepare-roster-import/index.ts','supabase/functions/_shared/roster_decoder_integration_test.ts']
flags=['--no-config','--cached-only','--no-prompt','--frozen','--lock=supabase/functions/deno.lock']
env={'PATH':os.defpath,'DENO_DIR':str(CACHE),'DENO_NO_UPDATE_CHECK':'1','NO_COLOR':'1'}
report={'status':'prepared','attempt':MODE,'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'shared_before':current(),'old_before':tree(BASE/'old/source'),'candidate_before':tree(BASE/'candidate/source'),'remote_before':remotes(),'runtime_before':sha(DENO),'runner_before':sha(Path(__file__)),'phases':[],'provider_calls':0,'hosted_database_calls':0,'network_permission':False,'cached_only_test_and_type_phases':True,'frozen_lock':True,'shared_promotion':False,'suppressed_exceptions':0}
try:
 assert report['shared_before']=={r['path']:r['sha256'] for r in EXPECTED},'shared baseline changed before run'
 assert report['runtime_before']=='a371e0605be5039a91a079a802d66b22c124a42e31573e43136c93c2b362f1c0'
 assert report['remote_before']==tree(ORIGINAL_CACHE/'remote')
 (RUN/'runtime.txt').write_text(subprocess.check_output([str(DENO),'--version'],env=env,text=True,timeout=10))
 phases=[]
 if MODE in ('attempt1','attempt2'): phases += [('old-types','old',['test','--no-run',*flags,*entries]),('old-tests','old',['test',*flags,*entries])]
 phases += [('candidate-types','candidate',['test','--no-run',*flags,*candidate_entries,'supabase/functions/_shared/roster_decoder_integration_test.ts','supabase/functions/prepare-roster-import/index.ts']),('candidate-tests','candidate',['test',*flags,*candidate_entries]),('baseline-integration-lint','old',['lint','--no-config','supabase/functions/_shared/roster_decoder_integration_test.ts']),('candidate-lint','candidate',['lint','--no-config',*[p for p in owned if not p.endswith('roster_decoder_integration_test.ts')]]),('candidate-format','candidate',['fmt','--check',*owned])]
 for label,stage,args in phases:
  cwd=BASE/stage/'source'; command=[str(DENO),*args];start=time.monotonic()
  with (RUN/(label+'.stdout')).open('xb') as stdout,(RUN/(label+'.stderr')).open('xb') as stderr:
   run=subprocess.run(command,cwd=cwd,env=env,stdout=stdout,stderr=stderr,timeout=120)
  report['phases'].append({'label':label,'command':command,'cwd':str(cwd),'exit_code':run.returncode,'seconds':round(time.monotonic()-start,3)})
  print(label,run.returncode,flush=True)
 report['status']='candidate-pass' if all(p['exit_code']==0 for p in report['phases'] if p['label'].startswith('candidate')) else 'actual-failure'
 for label in ['old-tests','candidate-tests']:
  p=RUN/(label+'.stdout')
  if p.exists(): report[label+'_summaries']=re.findall(r'(\d+) passed \| (\d+) failed(?: \| (\d+) ignored)?',p.read_text())
except Exception as e: report['error']=str(e) or type(e).__name__;report['status']='actual-failure'
finally:
 report.update(shared_after=current(),old_after=tree(BASE/'old/source'),candidate_after=tree(BASE/'candidate/source'),remote_after=remotes(),runtime_after=sha(DENO),runner_after=sha(Path(__file__)),finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
 report['source_unchanged']=all(report[a+'_before']==report[a+'_after'] for a in ['shared','old','candidate'])
 report['tools_unchanged']=all(report[a+'_before']==report[a+'_after'] for a in ['remote','runtime','runner'])
 if not report['source_unchanged'] or not report['tools_unchanged']:report['status']='actual-failure';report['error']='source/tool drift'
 (RUN/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'status':report['status'],'phases':[(p['label'],p['exit_code']) for p in report['phases']],'summaries':{k:v for k,v in report.items() if k.endswith('_summaries')},'source_unchanged':report['source_unchanged'],'tools_unchanged':report['tools_unchanged'],'error':report.get('error')}))
 sys.exit(0 if report['status']=='candidate-pass' else 1)
