from pathlib import Path
import hashlib,json,subprocess,time,os,signal
root=Path.cwd();base=root/'docs/release/critical-implementation-2026-10-01/be08-literal-replacement-integration1';py=Path('/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3')
rows=json.loads((base/'applied-source-readback.json').read_text())['paths'];original_inputs=json.loads((base/'source-input-fences-before.json').read_text())['inputs']
def sha(raw):return hashlib.sha256(raw).hexdigest()
def held_inputs():
 result=[]
 for row in original_inputs:
  p=Path(row['path']);p=p if p.is_absolute() else root/p;raw=p.read_bytes();expected=rows[0]['after_sha256'] if p==root/rows[0]['path'] else row['sha256']
  if sha(raw)!=expected:raise SystemExit('held mapper input drift: '+row['path'])
  result.append({'path':row['path'],'kind':row['kind'],'sha256':sha(raw),'bytes':len(raw),'expected_sha256':expected})
 for row in rows:
  if sha((root/row['path']).read_bytes())!=row['after_sha256']:raise SystemExit('owned source drift')
 return result
before=held_inputs();(base/'check-source-input-fences-before.json').write_text(json.dumps({'inputs':before,'count':len(before)},indent=2)+'\n')
def run(name,argv,bound):
 held_inputs();t0=time.monotonic();p=subprocess.Popen(argv,cwd=root,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True);timed_out=False
 try:stdout,stderr=p.communicate(timeout=bound)
 except subprocess.TimeoutExpired:
  timed_out=True;os.killpg(p.pid,signal.SIGTERM)
  try:stdout,stderr=p.communicate(timeout=3)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);stdout,stderr=p.communicate()
 result={'argv':argv,'exit_code':p.returncode,'actual_seconds':time.monotonic()-t0,'deadline_seconds':bound,'timed_out':timed_out,'python_sha256':sha(py.read_bytes()),'owned_group_id':p.pid,'stdout_sha256':sha(stdout),'stderr_sha256':sha(stderr),'owned_source_hashes':{r['path']:r['after_sha256'] for r in rows}}
 try:os.killpg(p.pid,0);result['owned_group_absent']=False
 except ProcessLookupError:result['owned_group_absent']=True
 result['held1095inputs_after_match']=len(held_inputs())==1095
 for suffix,data in [('stdout.txt',stdout),('stderr.txt',stderr)]:(base/(name+'.'+suffix)).write_bytes(data)
 (base/(name+'.json')).write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'check':name,**result}),flush=True);print((stderr if name.startswith('tests') else stdout).decode()[-1100:],flush=True)
 if result['exit_code'] or result['timed_out'] or not result['owned_group_absent']:raise SystemExit(1)
run('tests-maintained',[str(py),'-I','-B',str(root/'scripts/tests/collect_schema_domain_map_test.py')],30)
original=json.loads((base.parent/'root-be08-transform-mapper-integration1/generation.json').read_text());argv=original['argv'];argv[argv.index('--output')+1]=str(base/'generated-current209')
run('generation-maintained',argv,original['deadline_seconds'])
original=json.loads((base.parent/'root-be08-transform-mapper-integration1/independent-semantic-verification.json').read_text());argv=original['argv'];argv[argv.index('--output')+1]=str(base/'generated-current209')
run('independent-semantic-verification-maintained',argv,original['deadline_seconds'])
after=held_inputs();(base/'check-source-input-fences-after.json').write_text(json.dumps({'inputs':after,'count':len(after),'before_after_exact_parity':before==after},indent=2)+'\n')
if before!=after:raise SystemExit('check input hash parity failed')
