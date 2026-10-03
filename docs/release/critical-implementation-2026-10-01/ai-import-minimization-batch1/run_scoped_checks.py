"""Physically private affected source; pinned frozen cached-only Deno; no network permissions."""
from pathlib import Path
import datetime as dt,hashlib,json,os,re,shutil,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[4]
PACKET=Path(__file__).resolve().parent
DENO=ROOT/'.cache/roster-deno-2.5.6-20260929/deno'
CACHE=ROOT/'.cache/edge-current-integration-batch1/attempt2/deno-dir'
ENTRIES=json.loads((PACKET/'source-before.json').read_text())['entries']
FILES=[r['path'] for r in json.loads((PACKET/'source-before.json').read_text())['files']]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def cohort(base):return {p:sha(base/p) for p in FILES}
def run(command,stage,out,env,timeout=60):
 with out.with_suffix('.stdout').open('xb') as stdout,out.with_suffix('.stderr').open('xb') as stderr:
  start=time.monotonic()
  try:
   c=subprocess.run(command,cwd=stage,env=env,stdout=stdout,stderr=stderr,timeout=timeout)
   result={'command':command,'exit_code':c.returncode,'seconds':round(time.monotonic()-start,3)}
  except subprocess.TimeoutExpired:
   result={'command':command,'timeout_seconds':timeout,'seconds':round(time.monotonic()-start,3)}
 out.with_suffix('.json').write_text(json.dumps(result,indent=2)+'\n')
 return result
label=sys.argv[1]
assert label in ('old-source-negative-attempt2','corrected-source')
out=PACKET/label;out.mkdir(exist_ok=False)
stage=ROOT/'.cache/ai-import-minimization-batch1'/label/'source';stage.mkdir(parents=True,exist_ok=False)
env={'PATH':os.defpath,'DENO_DIR':str(CACHE),'DENO_NO_UPDATE_CHECK':'1','NO_COLOR':'1'}
report={'status':'fail','label':label,'started_at':dt.datetime.now(dt.timezone.utc).isoformat(),'no_runtime_network_permission':True,'dependencies_cached_only':True,'lock_frozen':True,'provider_calls':0,'database_calls':0,'stage':str(stage),'source_before':cohort(ROOT),'runtime_before':sha(DENO),'runner_before':sha(Path(__file__)),'phases':[]}
try:
 assert DENO.is_file() and CACHE.is_dir()
 version=subprocess.check_output([str(DENO),'--version'],env=env,text=True,timeout=10)
 (out/'runtime-version.txt').write_text(version)
 assert version.splitlines()[0].split()[1]==(ROOT/'.dvmrc').read_text().strip()
 for name in FILES:
  p=ROOT/name;assert p.is_file() and not p.is_symlink();target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target)
 assert cohort(stage)==report['source_before']
 (out/'source-copy.json').write_text(json.dumps({'regular_copy':True,'hardlinks':False,'source':cohort(stage)},indent=2)+'\n')
 external={str(p):{'sha256':sha(p),'bytes':p.stat().st_size} for p in sorted((CACHE/'remote').rglob('*')) if p.is_file()}
 assert external, 'Existing remote cache inputs required'
 report['external_cache_before']=external
 report['external_cache_scope']='Complete existing remote source-cache superset; actual resolution is cached-only/frozen with no runtime network permissions'
 flags=['--no-config','--cached-only','--no-prompt','--frozen','--lock=supabase/functions/deno.lock']
 if label=='corrected-source':
  command=[str(DENO),'test','--no-run',*flags,*ENTRIES]
  phase=run(command,stage,out/'types',env);report['phases'].append(phase);assert phase.get('exit_code')==0, 'Pinned offline compiler phase failed'
 command=[str(DENO),'test',*flags,*ENTRIES]
 phase=run(command,stage,out/'tests',env);report['phases'].append(phase)
 text=(out/'tests.stdout').read_text();summary=re.findall(r'(\d+) passed \| (\d+) failed',text)
 report['test_summaries']=[{'passed':int(p),'failed':int(f)} for p,f in summary]
 if label=='old-source-negative-attempt2':
  assert phase.get('exit_code')==1 and summary and int(summary[-1][1])==2
  assert 'PDF display filenames never enter the exact provider request' in text
  assert 'PDF source keeps its display filename internally' in text
  report['status']='expected_denial'
 else:
  assert phase.get('exit_code')==0 and summary and int(summary[-1][1])==0
  owned=['supabase/functions/_shared/openai_roster.ts','supabase/functions/_shared/openai_roster_test.ts','supabase/functions/prepare-roster-import/handler_test.ts']
  phase=run([str(DENO),'lint','--no-config',*owned],stage,out/'lint',env);report['phases'].append(phase);assert phase.get('exit_code')==0
  phase=run([str(DENO),'fmt','--check',*owned],stage,out/'format',env);report['phases'].append(phase);assert phase.get('exit_code')==0
  report['status']='pass'
except Exception as e:report['error']=str(e) or type(e).__name__
finally:
 report['source_after']=cohort(ROOT);report['source_stage_after']=cohort(stage);report['runtime_after']=sha(DENO);report['runner_after']=sha(Path(__file__))
 report['external_cache_after']={p:{**r,'sha256':sha(Path(p)),'bytes':Path(p).stat().st_size} for p,r in report.get('external_cache_before',{}).items()}
 report['source_unchanged']=report['source_before']==report['source_after']==report['source_stage_after']
 report['bindings_unchanged']=report['runtime_before']==report['runtime_after'] and report['runner_before']==report['runner_after'] and report.get('external_cache_before',{})==report['external_cache_after']
 if not report['source_unchanged'] or not report['bindings_unchanged']:report['status']='fail';report['error']='Source/tool/cache content drift'
 report['finished_at']=dt.datetime.now(dt.timezone.utc).isoformat();(out/'result.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'status':report['status'],'source_files':len(FILES),'test_summaries':report.get('test_summaries'),'external_cache_files':len(report.get('external_cache_before',{})),'error':report.get('error'),'output':str(out)}))
 sys.exit(0 if report['status'] in ('pass','expected_denial') else 1)
