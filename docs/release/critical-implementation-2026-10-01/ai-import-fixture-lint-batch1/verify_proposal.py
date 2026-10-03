from pathlib import Path
import hashlib,json,subprocess,os,re,datetime,time
ROOT=Path(__file__).resolve().parents[4];OUT=Path(__file__).resolve().parent;STAGE=ROOT/'.cache/ai-import-fixture-lint-batch1/proposal/source';DENO=ROOT/'.cache/roster-deno-2.5.6-20260929/deno';CACHE=ROOT/'.cache/edge-current-integration-batch1/attempt2/deno-dir';PRIOR=ROOT/'docs/release/critical-implementation-2026-10-01/ai-import-minimization-batch1';ENTRIES=json.loads((PRIOR/'source-before.json').read_text())['entries'];FILES=[r['path'] for r in json.loads((OUT/'source-before.json').read_text())['files']];OWNED=['supabase/functions/_shared/openai_roster.ts','supabase/functions/_shared/openai_roster_test.ts','supabase/functions/prepare-roster-import/handler_test.ts']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def cohort(base):return {p:sha(base/p) for p in FILES}
def remotes():return {str(p):sha(p) for p in sorted((CACHE/'remote').rglob('*')) if p.is_file()}
report={'status':'fail','proposed_source_not_applied':True,'source_current_before':cohort(ROOT),'source_stage_before':cohort(STAGE),'runtime_before':sha(DENO),'remote_cache_before':remotes(),'runner_before':sha(Path(__file__)),'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'phases':[],'live_provider_calls':0,'database_calls':0,'runtime_network_permission':False,'cached_only':True,'lock_frozen':True}
env={'PATH':os.defpath,'DENO_DIR':str(CACHE),'DENO_NO_UPDATE_CHECK':'1','NO_COLOR':'1'};flags=['--no-config','--cached-only','--no-prompt','--frozen','--lock=supabase/functions/deno.lock']
try:
 version=subprocess.check_output([str(DENO),'--version'],env=env,text=True,timeout=10);assert version.splitlines()[0].split()[1]==(ROOT/'.dvmrc').read_text().strip();(OUT/'proposal-runtime.txt').write_text(version)
 for label,args in [('proposal-types',['test','--no-run',*flags,*ENTRIES]),('proposal-tests',['test',*flags,*ENTRIES]),('proposal-lint',['lint','--no-config',*OWNED]),('proposal-format-check',['fmt','--check',*OWNED])]:
  command=[str(DENO),*args];start=time.monotonic()
  with (OUT/(label+'.stdout')).open('xb') as out,(OUT/(label+'.stderr')).open('xb') as err:r=subprocess.run(command,cwd=STAGE,env=env,stdout=out,stderr=err,timeout=60)
  report['phases'].append({'label':label,'command':command,'exit_code':r.returncode,'seconds':round(time.monotonic()-start,3)});assert r.returncode==0,label+' failed'
 text=(OUT/'proposal-tests.stdout').read_text();summary=re.findall(r'(\d+) passed \| (\d+) failed',text);assert summary==[('109','0')];report.update(status='pass',tests={'passed':109,'failed':0},case_source_unchanged=True)
except Exception as e:report['error']=str(e) or type(e).__name__
finally:
 report.update(source_current_after=cohort(ROOT),source_stage_after=cohort(STAGE),runtime_after=sha(DENO),remote_cache_after=remotes(),runner_after=sha(Path(__file__)),finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
 report['source_unchanged']=report['source_current_before']==report['source_current_after'] and report['source_stage_before']==report['source_stage_after'];report['tools_unchanged']=report['runtime_before']==report['runtime_after'] and report['remote_cache_before']==report['remote_cache_after'] and report['runner_before']==report['runner_after']
 if not report['source_unchanged'] or not report['tools_unchanged']:report['status']='fail';report['error']='source/tool/cache drift'
 (OUT/'proposal-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':report['status'],'tests':report.get('tests'),'source_inputs':len(FILES),'remote_cache_inputs':len(report['remote_cache_before']),'source_unchanged':report['source_unchanged'],'tools_unchanged':report['tools_unchanged'],'error':report.get('error')}));raise SystemExit(0 if report['status']=='pass' else 1)
