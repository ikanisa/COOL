from pathlib import Path
import hashlib,json,os,signal,subprocess,time,shutil
ROOT=Path(__file__).resolve().parents[4]
OUT=Path(__file__).resolve().parent
CANDIDATE=OUT/'proof-candidate'
DART=Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart')
sha=lambda b:hashlib.sha256(b).hexdigest()
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def save(name,value): (OUT/name).write_text(json.dumps(value,indent=2)+'\n')
bindings=json.loads((OUT/'inputs.json').read_bytes())
def external_inputs():
 result={}
 for rel,value in bindings['maintained'].items():
  p=ROOT/rel;result[str(p)]=digest(p)
  assert result[str(p)]==value['sha256'],rel
 for path,value in bindings['external_package_inputs'].items():
  result[path]=digest(Path(path));assert result[path]==value['sha256'],path
 for p in [DART,DART.parent/'snapshots/dartdev_aot.dart.snapshot',DART.parent/'snapshots/analysis_server_aot.dart.snapshot',DART.parent/'snapshots/kernel-service.dart.snapshot']:
  result[str(p)]=digest(p)
 return result
before=external_inputs();save('inputs-before-proof.json',before)
results=[]
def run(name,argv,limit):
 start=time.monotonic();env=dict(os.environ,DART_SUPPRESS_ANALYTICS='true',DART_DISABLE_ANALYTICS='true')
 process=subprocess.Popen(argv,cwd=CANDIDATE,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
 timed_out=False
 try: stdout,stderr=process.communicate(timeout=limit)
 except subprocess.TimeoutExpired:
  timed_out=True;os.killpg(process.pid,signal.SIGKILL);stdout,stderr=process.communicate(timeout=10)
 (OUT/(name+'.stdout')).write_bytes(stdout);(OUT/(name+'.stderr')).write_bytes(stderr)
 group_absent=False
 try: os.killpg(process.pid,0)
 except ProcessLookupError: group_absent=True
 item=dict(name=name,argv=argv,cwd=str(CANDIDATE),time_limit_seconds=limit,elapsed_seconds=time.monotonic()-start,exit_code=process.returncode,timed_out=timed_out,owned_group_absent=group_absent,stdout_sha256=sha(stdout),stderr_sha256=sha(stderr),pass_=process.returncode==0 and not timed_out and group_absent)
 results.append(item);save(name+'.json',item);print(name,item['exit_code'],flush=True)
 if not item['pass_']: raise RuntimeError(name+' failed; raw outputs retained')
 return stdout
try:
 baseline=CANDIDATE/'scripts/baseline/admin_receipt_operational_telemetry_test.dart';baseline.parent.mkdir();shutil.copy2(OUT/'baseline/scripts/tests/admin_receipt_operational_telemetry_test.dart',baseline)
 packages=str(CANDIDATE/'.dart_tool/package_config.json')
 original=run('baseline-telemetry-boundaries',[str(DART),'--disable-dart-dev','--packages='+packages,str(baseline),'--boundaries'],60)
 candidate=run('candidate-telemetry-boundaries',[str(DART),'--disable-dart-dev','--packages='+packages,str(CANDIDATE/'scripts/tests/admin_receipt_operational_telemetry_test.dart'),'--boundaries'],60)
 assert original==candidate,'Boundary outputs changed'
 run('candidate-strict-analysis',[str(DART),'analyze','--fatal-infos','--fatal-warnings','scripts/tests'],90)
 after=external_inputs();save('inputs-after-proof.json',after);assert before==after
 save('proof-result.json',dict(status='pass',commands=results,boundary_stdout_identical=True,source_busy_actual_fixture_execution='not run; exact reviewed fixture directory not supplied',maintained_and_external_inputs_unchanged=True,integrated=False,combined_candidate_acceptance=False))
except BaseException as e:
 after=external_inputs();save('inputs-after-proof.json',after)
 save('proof-result.json',dict(status='failed',commands=results,error=type(e).__name__+': '+str(e),maintained_and_external_inputs_unchanged=before==after,integrated=False))
 raise
