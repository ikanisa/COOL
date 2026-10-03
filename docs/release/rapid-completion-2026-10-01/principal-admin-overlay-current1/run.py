from pathlib import Path
import hashlib,json,shutil,subprocess,time,os,importlib.util
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');OUT=ROOT/'docs/release/rapid-completion-2026-10-01/principal-admin-overlay-current1'
BASE_PATH=ROOT/'docs/release/rapid-completion-2026-10-01/full-flutter-current-resumption1/source-export.json';BASE=json.loads(BASE_PATH.read_text());SOURCE=Path(BASE['export']);EXPORT=ROOT/'.cache/principal-admin-overlay-current1';SDK=ROOT/'.cache/flutter-sdk-isolated-admin-browser-current1'
TOOL_FILES=['scripts/tests/admin_read_gateway_gate.py','scripts/tests/admin_matrix_acceptance.py']
CURRENT=json.loads((OUT/'stable-second-read.json').read_text());assert CURRENT['stable']and CURRENT['tool_tests_exit_code']==0
inputs_overlay={**CURRENT['inputs_sha256'],**{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest()for n in TOOL_FILES}}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert not EXPORT.exists()
assert all(sha(ROOT/n)==d for n,d in inputs_overlay.items())
for n,d in BASE['inputs_sha256'].items():
 p=SOURCE/n;assert sha(p)==d,n
 q=EXPORT/n;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
for n,d in inputs_overlay.items():
 p=ROOT/n;assert sha(p)==d,n
 q=EXPORT/n;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
assert all(sha(ROOT/n)==d and sha(EXPORT/n)==d for n,d in inputs_overlay.items())
inputs={n:sha(EXPORT/n)for n in set(BASE['inputs_sha256'])|set(inputs_overlay)}
sdk_paths=['bin/cache/artifacts/engine/darwin-x64/flutter_tester','bin/cache/dart-sdk/bin/dart','bin/cache/dart-sdk/bin/dartaotruntime','bin/cache/flutter_tools.snapshot'];sdk={n:sha(SDK/n)for n in sdk_paths}
VM=['test/'+n+'.dart'for n in ['admin_receipt_principal_models_test','admin_receipt_principal_recovery_test','admin_receipt_principal_integration_test','admin_automations_test','admin_exception_workflow_test','admin_exception_workflow_sdk_test','admin_action_session_test','admin_session_scope_test','admin_route_access_test','admin_declared_route_states_test']]
spec=importlib.util.spec_from_file_location('gate',EXPORT/TOOL_FILES[0]);gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
BROWSER=list(gate.BROWSER_TEST_FILES);EXPECTED=list(gate.BROWSER_REQUIRED_CASE_NAMES)
owned_runtime=[n for n in inputs_overlay if n.startswith('lib/')]
selected=[*owned_runtime,*VM,*BROWSER]
(OUT/'inputs.json').write_text(json.dumps({'base_manifest':str(BASE_PATH),'base_manifest_sha256':sha(BASE_PATH),'base_export':str(SOURCE),'export':str(EXPORT),'inputs_sha256':inputs,'overlay_sha256':inputs_overlay,'source_consistency_before_copy_after':True,'sdk_root':str(SDK),'sdk_before':sdk,'vm_selection':VM,'chrome_selection':BROWSER,'required_chrome_case_names':EXPECTED,'scope':'Current principal delta plus affected Automations/workflow/session/28-route compatibility; VM HTTP fixtures use actual locked SDK, not current SQL or external delivery. Chrome exercises actual same-origin storage/Web Locks.'},indent=2)+'\n')
commands=[]
def run(args,label,env=None):
 t=time.time()
 with (OUT/(label+'.stdout')).open('w')as stdout,(OUT/(label+'.stderr')).open('w')as stderr:r=subprocess.run(args,cwd=EXPORT,stdout=stdout,stderr=stderr,env=env)
 commands.append({'label':label,'args':args,'cwd':str(EXPORT),'exit_code':r.returncode,'seconds':round(time.time()-t,3),'stdout_sha256':sha(OUT/(label+'.stdout')),'stderr_sha256':sha(OUT/(label+'.stderr'))})
 (OUT/'execution.json').write_text(json.dumps({'commands':commands},indent=2)+'\n');print(label,r.returncode,flush=True);return r.returncode
if run([str(SDK/'bin/flutter'),'pub','get','--offline','--enforce-lockfile'],'pub'):raise SystemExit(1)
run([str(SDK/'bin/dart'),'format','--output=none','--set-exit-if-changed',*selected],'format')
run([str(SDK/'bin/flutter'),'analyze','--no-pub','--fatal-infos',*selected],'analysis')
run([str(SDK/'bin/flutter'),'test','--no-pub','--reporter=json','--concurrency=1',*VM],'vm')
env=os.environ.copy();env['CHROME_EXECUTABLE']='/Users/jeanbosco/.cache/selenium/chrome/mac-arm64/151.0.7922.34/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';assert Path(env['CHROME_EXECUTABLE']).is_file()
run([str(SDK/'bin/flutter'),'test','--no-pub','--platform=chrome','--reporter=json','--concurrency=1',*BROWSER],'chrome',env)
def summary(name):
 ids={};finished=[];errors=[];final=None
 for line in (OUT/(name+'.stdout')).read_text().splitlines():
  try:d=json.loads(line)
  except ValueError:continue
  if d.get('type')=='testStart':ids[d['test']['id']]=d['test']
  elif d.get('type')=='testDone'and not d.get('hidden'):finished.append({'name':ids[d['testID']]['name'],'source':ids[d['testID']].get('root_url')or ids[d['testID']].get('url'),'result':d['result'],'skipped':d.get('skipped',False)})
  elif d.get('type')=='error':errors.append(d)
  elif d.get('type')=='done':final=d.get('success')
 return {'cases':finished,'count':len(finished),'passed':sum(c['result']=='success'and not c['skipped']for c in finished),'errors':errors,'runner_success':final is True}
vm=summary('vm');chrome=summary('chrome');required={title:any(c['name']==title and c['result']=='success'and not c['skipped']for c in chrome['cases'])for title in EXPECTED}
export_drift=[n for n,d in inputs.items()if not(EXPORT/n).is_file()or sha(EXPORT/n)!=d];sdk_same={n:sha(SDK/n)for n in sdk_paths}==sdk;live_delta=[n for n,d in inputs_overlay.items()if not(ROOT/n).is_file()or sha(ROOT/n)!=d]
passed=all(c['exit_code']==0 for c in commands)and vm['runner_success']and vm['count']==vm['passed']and not vm['errors']and chrome['runner_success']and chrome['count']==15==chrome['passed']and not chrome['errors']and all(required.values())and not export_drift and sdk_same
result={'status':'pass'if passed else'fail','commands':commands,'vm':vm,'chrome':chrome,'required_browser_cases_passed':required,'export_drift':export_drift,'sdk_unchanged':sdk_same,'current_overlay_drift':live_delta,'current_overlay_matches':not live_delta,'all_live_Admin_source_claim':False,'source_scope':'Immutable fullVM base + exact three changed/seven added principal runtime files, four principal tests, corrected owned workflow/Overview fixtures and16dated principal JSON decoder inputs. This is source-bound affected acceptance, not a whole live-tree/backend/provider/design claim.'}
(OUT/'validation.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'status':result['status'],'vm':vm['count'],'chrome':chrome['count'],'export_drift':export_drift,'sdk_same':sdk_same,'overlay_drift':live_delta}),flush=True);raise SystemExit(0 if passed else 1)
