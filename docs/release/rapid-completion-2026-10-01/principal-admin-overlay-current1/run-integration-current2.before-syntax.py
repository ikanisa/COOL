from pathlib import Path
import hashlib,json,shutil,subprocess,time
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');PRIOR=ROOT/'docs/release/rapid-completion-2026-10-01/principal-admin-overlay-current1';OUT=ROOT/'docs/release/rapid-completion-2026-10-01/principal-integration-current2';OUT.mkdir();PREV=json.loads((PRIOR/'inputs.json').read_text());SOURCE=Path(PREV['export']);EXPORT=ROOT/'.cache/principal-integration-current2';SDK=ROOT/'.cache/flutter-sdk-isolated-admin-browser-current1';TEST='test/admin_receipt_principal_integration_test.dart';FORMAT='lib/admin/core/admin_repository_base.dart'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert not EXPORT.exists();assert sha(ROOT/FORMAT)=='21b62b7f5490beceed7b7d8d954b4275a27459bcfceb18d8c2ede292a1fb9ccf';assert(PRIOR/'formatter-applied.json').is_file()
changed={n:sha(ROOT/n)for n in [TEST,FORMAT]};sdk_paths=list(PREV['sdk_before']);sdk={n:sha(SDK/n)for n in sdk_paths}
for n,d in PREV['inputs_sha256'].items():
 p=SOURCE/n;assert sha(p)==d,n
 q=EXPORT/n;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
for n,d in changed.items():
 p=ROOT/n;assert sha(p)==d,n;shutil.copy2(p,EXPORT/n)
assert all(sha(ROOT/n)==d and sha(EXPORT/n)==d for n,d in changed.items())
inputs={n:sha(EXPORT/n)for n in PREV['inputs_sha256']}
(PRIOR/'principal-integration.peer-fixture.diff').write_text(subprocess.run(['diff','-u',str(SOURCE/TEST),str(EXPORT/TEST)],capture_output=True,text=True).stdout)
(OUT/'inputs.json').write_text(json.dumps({'base_inputs_receipt':str(PRIOR/'inputs.json'),'base_inputs_sha256':sha(PRIOR/'inputs.json'),'export':str(EXPORT),'inputs_sha256':inputs,'sole_changes':changed,'current_copy_before_after_stable':True,'formatter_receipt':str(PRIOR/'formatter-applied.json'),'formatter_receipt_sha256':sha(PRIOR/'formatter-applied.json'),'sdk_root':str(SDK),'sdk_before':sdk,'scope':'One affected integration cohort only. Current helper fixes +guarded exact formatter bytes; no other runtime edits/no482repeat.'},indent=2)+'\n')
commands=[]
def run(args,label):
 t=time.time()
 with(OUT/(label+'.stdout')).open('w')as stdout,(OUT/(label+'.stderr')).open('w')as stderr:r=subprocess.run(args,cwd=EXPORT,stdout=stdout,stderr=stderr)
 commands.append({'label':label,'args':args,'cwd':str(EXPORT),'exit_code':r.returncode,'seconds':round(time.time()-t,3),'stdout_sha256':sha(OUT/(label+'.stdout')),'stderr_sha256':sha(OUT/(label+'.stderr'))});(OUT/'execution.json').write_text(json.dumps({'commands':commands},indent=2)+'\n');print(label,r.returncode,flush=True);return r.returncode
if run([str(SDK/'bin/flutter'),'pub','get','--offline','--enforce-lockfile'],'pub'):raise SystemExit(1)
run([str(SDK/'bin/dart'),'format','--output=none','--set-exit-if-changed',TEST,FORMAT],'format')
run([str(SDK/'bin/flutter'),'analyze','--no-pub','--fatal-infos',TEST],'analysis')
run([str(SDK/'bin/flutter'),'test','--no-pub','--reporter=json','--concurrency=1',TEST],'cases')
ids={};cases=[];errors=[];done=None
for line in(OUT/'cases.stdout').read_text().splitlines():
 try:d=json.loads(line)
 except ValueError:continue
 if d.get('type')=='testStart':ids[d['test']['id']]=d['test']['name']
 elif d.get('type')=='testDone'and not d.get('hidden'):cases.append({'name':ids[d['testID']],'result':d['result'],'skipped':d.get('skipped',False)})
 elif d.get('type')=='error':errors.append(d)
 elif d.get('type')=='done':done=d.get('success')
prior=json.loads((PRIOR/'validation.json').read_text());integration_prior=[c for c in prior['vm']['cases']if c['source']and c['source'].endswith(TEST)];reused=[c for c in prior['vm']['cases']if not(c['source']and c['source'].endswith(TEST))];assert all(c['result']=='success'and not c['skipped']for c in reused)
export_drift=[n for n,d in inputs.items()if not(EXPORT/n).is_file()or sha(EXPORT/n)!=d];live=[n for n,d in changed.items()if sha(ROOT/n)!=d];sdk_same={n:sha(SDK/n)for n in sdk_paths}==sdk
passed=all(c['exit_code']==0 for c in commands)and done is True and len(cases)==len(integration_prior)and not errors and all(c['result']=='success'and not c['skipped']for c in cases)and not export_drift and sdk_same
result={'status':'pass'if passed else'fail','commands':commands,'cases':cases,'count':len(cases),'prior_integration_cases':len(integration_prior),'errors':errors,'current_changed_inputs_match':not live,'live_delta':live,'export_drift':export_drift,'sdk_unchanged':sdk_same,'prior_remaining_cases_reused':len(reused),'prior_remaining_cases':[c['name']for c in reused],'prior_chrome_named_cases_passed':prior['required_browser_cases_passed'],'reuse_conditions':'Exact unchanged candidate files +root guarded whitespace-only repository formatting receipt; current integration helper dependency changes executed here. No whole live Admin/server claim.'}
(OUT/'validation.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'status':result['status'],'cases':len(cases),'reused':len(reused),'live_delta':live}),flush=True);raise SystemExit(0 if passed else1)
