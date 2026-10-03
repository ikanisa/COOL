from pathlib import Path
import hashlib,json,subprocess,time,os,signal,sys
root=Path.cwd();base=root/'docs/release/critical-implementation-2026-10-01/be08-literal-replacement-preparation1';py=Path('/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3')
def run(name,argv,bound):
 t0=time.monotonic();p=subprocess.Popen(argv,cwd=root,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
 timed_out=False
 try:stdout,stderr=p.communicate(timeout=bound)
 except subprocess.TimeoutExpired:
  timed_out=True;os.killpg(p.pid,signal.SIGTERM)
  try:stdout,stderr=p.communicate(timeout=3)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);stdout,stderr=p.communicate()
 result={'argv':argv,'exit_code':p.returncode,'actual_seconds':time.monotonic()-t0,'deadline_seconds':bound,'timed_out':timed_out,'python_sha256':hashlib.sha256(py.read_bytes()).hexdigest(),'owned_group_id':p.pid,'stdout_sha256':hashlib.sha256(stdout).hexdigest(),'stderr_sha256':hashlib.sha256(stderr).hexdigest()}
 try:os.killpg(p.pid,0);result['owned_group_absent']=False
 except ProcessLookupError:result['owned_group_absent']=True
 for suffix,data in [('stdout.txt',stdout),('stderr.txt',stderr)]: (base/(name+'.'+suffix)).write_bytes(data)
 (base/(name+'.json')).write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'check':name,**result}),flush=True)
 print((stderr if name.startswith('tests') else stdout).decode()[-1500:],flush=True)
 if result['exit_code'] or result['timed_out'] or not result['owned_group_absent']:raise SystemExit(1)
run('tests-attempt3',[str(py),'-I','-B',str(base/'proposal/scripts/tests/collect_schema_domain_map_test.py')],30)
original=json.loads((base.parent/'root-be08-transform-mapper-integration1/generation.json').read_text())
argv=original['argv'];argv[3]=str(base/'proposal/scripts/audits/collect_schema_domain_map.py');argv[argv.index('--output')+1]=str(base/'reviewed-final/generated-current209')
run('generation-attempt2',argv,original['deadline_seconds'])
verify=json.loads((base.parent/'root-be08-transform-mapper-integration1/independent-semantic-verification.json').read_text())
argv=verify['argv'];argv[3]=str(base/'proposal/scripts/audits/collect_schema_domain_map.py');argv[argv.index('--output')+1]=str(base/'reviewed-final/generated-current209')
run('independent-semantic-verification-attempt2',argv,verify['deadline_seconds'])
