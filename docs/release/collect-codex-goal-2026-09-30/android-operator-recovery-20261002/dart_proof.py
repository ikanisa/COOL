from pathlib import Path
import json,hashlib,subprocess,time,os,re,signal
r=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');s=r/'.cache/android-recovery-operator-workflow-20261001';w=s/'dart-workspace-1';run=s/('dart-attempt-'+str(len(list(s.glob('dart-attempt-*')))+1));run.mkdir();sha=lambda x:hashlib.sha256(Path(x).read_bytes()).hexdigest();inputs=json.loads((w/'frozen-inputs.json').read_text());baseline=json.loads((s/'dart-dependency-baseline.json').read_text());deps=[]
excluded=[]
for entry in baseline['value']['entries']:
 if entry['path'].startswith('/Volumes/PRO-G40/Applications/Google Chrome.app/'):
  excluded.append({'path':entry['path'],'reason':'browser binary unused by VM widget/analyzer scope'});continue
 x=Path(entry['path']);value=sha(x)
 assert value==entry['expected_sha256'],str(x)
 deps.append({'path':str(x),'resolved_path':str(x.resolve()),'symlink_target':os.readlink(x) if x.is_symlink() else None,'sha256':value})
(run/'dependencies.json').write_text(json.dumps(deps,indent=2)+'\n');(run/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
tools={str(x):sha(x) for x in [Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter'),Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/dart-sdk/bin/dart'),Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/cache/flutter_tools.snapshot'),Path('/Volumes/PRO-G40/Development/Flutter/flutter/bin/internal/engine.version')]};commands=[]
def command(name,args):
 entry={'name':name,'argv':args,'cwd':str(w),'status':'running'};commands.append(entry);(run/'commands.json').write_text(json.dumps(commands,indent=2)+'\n');print(name,flush=True)
 out=run/(name+'.stdout');err=run/(name+'.stderr')
 with out.open('wb') as o,err.open('wb') as e:
  proc=subprocess.Popen(args,stdout=o,stderr=e,cwd=w,env={**os.environ,'FLUTTER_SUPPRESS_ANALYTICS':'true',**({'COLLECT_GATEWAY_RECOVERY_CAPTURE_DIR':str(s/'captures')} if '--capture-only' in __import__('sys').argv else {})},start_new_session=True);entry['pid']=proc.pid;start=time.monotonic()
  try:proc.wait(timeout=600)
  except BaseException:os.killpg(proc.pid,signal.SIGKILL);proc.wait();raise
 entry.update(status='terminal',exit_code=proc.returncode,owned_child_reaped=True,wall_seconds=time.monotonic()-start,stdout_sha256=sha(out),stderr_sha256=sha(err));(run/'commands.json').write_text(json.dumps(commands,indent=2)+'\n');print(name,proc.returncode,flush=True);return proc.returncode
flutter='/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter'
if '--capture-only' in __import__('sys').argv:
 code=command('widgets',[flutter,'test','--no-pub','--reporter','expanded','test/gateway/gateway_recovery_capture_test.dart'])
 analysis=command('analysis',[flutter,'analyze','--no-pub','test/gateway/gateway_recovery_capture_test.dart'])
else:
 code=command('widgets',[flutter,'test','--no-pub','--reporter','expanded','test/gateway/gateway_recovery_test.dart','test/gateway/gateway_safety_test.dart','test/gateway/gateway_local_dispatch_test.dart','test/gateway/gateway_enrollment_lifecycle_test.dart'])
 analysis=command('analysis',[flutter,'analyze','--no-pub','lib/gateway/gateway_app.dart','lib/gateway/gateway_recovery_page.dart','lib/gateway/gateway_recovery_platform.dart','test/gateway/gateway_recovery_test.dart'])
changes=[name for name,h in inputs.items() if sha(w/name)!=h];dependency_changes=[e['path'] for e in deps if sha(e['path'])!=e['sha256'] or str(Path(e['path']).resolve())!=e['resolved_path']];toolchanges=[x for x,h in tools.items() if sha(x)!=h]
text=(run/'widgets.stdout').read_text();counts=re.findall(r'\+(\d+)(?: -\d+)?: All tests passed!',text)
result={'status':'pass' if not code and not analysis and not changes and not dependency_changes and not toolchanges and counts else 'fail','commands':commands,'widget_test_count':int(counts[-1]) if counts else None,'inputs_sha256':sha(run/'inputs.json'),'source_changes':changes,'dependency_changes':dependency_changes,'tool_changes':toolchanges,'tools_sha256':tools,'dependencies_sha256':sha(run/'dependencies.json'),'dependency_count':len(deps),'excluded_baseline_dependencies':excluded,'limitations':['Flutter method-channel/widget proof on synthetic states; no physical Android SAF, TalkBack, native picker lifecycle or device recovery acceptance.']};(run/'validation.json').write_text(json.dumps(result,indent=2)+'\n');(s/'dart-latest.json').write_text(json.dumps({'path':str(run),'status':result['status']})+'\n');print(json.dumps({'terminal':result['status'],'path':str(run),'tests':result['widget_test_count']}),flush=True)
raise SystemExit(0 if result['status']=='pass' else 1)
