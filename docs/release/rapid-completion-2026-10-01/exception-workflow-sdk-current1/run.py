from pathlib import Path
import hashlib,json,shutil,subprocess,time
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
OUT=ROOT/'docs/release/rapid-completion-2026-10-01/exception-workflow-sdk-current1'
MANIFEST=ROOT/'docs/release/rapid-completion-2026-10-01/full-flutter-current-resumption1/source-export.json'
BASE=json.loads(MANIFEST.read_text());SOURCE=Path(BASE['export']);EXPORT=ROOT/'.cache/exception-workflow-sdk-current1'
SDK=ROOT/'.cache/flutter-sdk-isolated-admin-browser-current1'
TEST='test/admin_exception_workflow_sdk_test.dart'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert (not EXPORT.exists()) or (OUT/'inputs.json').exists()
for name,digest in BASE['inputs_sha256'].items():
 p=SOURCE/name;assert sha(p)==digest,name
 q=EXPORT/name;q.parent.mkdir(parents=True,exist_ok=True)
 if not q.exists():shutil.copy2(p,q)
shutil.copy2(ROOT/TEST,EXPORT/TEST)
inputs={name:sha(EXPORT/name) for name in BASE['inputs_sha256']}
assert [n for n in inputs if inputs[n]!=BASE['inputs_sha256'][n]]==[TEST]
sdk_paths=['bin/cache/artifacts/engine/darwin-x64/flutter_tester','bin/cache/dart-sdk/bin/dart','bin/cache/dart-sdk/bin/dartaotruntime','bin/cache/flutter_tools.snapshot']
sdk={n:sha(SDK/n) for n in sdk_paths}
root_sdk=json.loads((MANIFEST.parent/'sdk-before.json').read_text())
assert sorted(sdk.values())==sorted(root_sdk.values())
(OUT/'inputs.json').write_text(json.dumps({'root_manifest':str(MANIFEST),'root_manifest_sha256':sha(MANIFEST),'immutable_source':str(SOURCE),'export':str(EXPORT),'inputs_sha256':inputs,'sole_changed_input':TEST,'sdk_root':str(SDK),'sdk_before':sdk,'actual_sdk_runtime':'locked production Supabase + Postgrest + GoTrue; http MockClient supplies transport responses only; production repository/provider/widgets and real Auth events','excluded':'No current peer principal runtime, SQL, browser, native, hosted or delivery claim'},indent=2)+'\n')
# Retain exact original failing names/errors independently of the running broad suite.
records=[];names={};owned_ids=set();owned_suites=set();failed=[]
for line in (MANIFEST.parent/'vm.machine.jsonl').read_text().splitlines():
 try:d=json.loads(line)
 except ValueError:continue
 if d.get('type')=='suite' and d['suite']['path'].endswith(TEST):owned_suites.add(d['suite']['id'])
 if d.get('type')=='testStart':
  names[d['test']['id']]=d['test']['name']
  if d['test']['suiteID'] in owned_suites:owned_ids.add(d['test']['id'])
 if d.get('testID') in owned_ids:records.append(d)
 if d.get('type')=='testDone' and d.get('result')=='error' and d.get('testID') in owned_ids:failed.append({'name':names[d['testID']],'record':d})
(OUT/'prior-failures.json').write_text(json.dumps({'source_sha256':BASE['inputs_sha256'][TEST],'root_machine_sha256':sha(MANIFEST.parent/'vm.machine.jsonl'),'errors':failed,'error_records':[d for d in records if d.get('type')=='error']},indent=2)+'\n')
commands=[]
def run(args,label):
 t=time.time()
 with (OUT/(label+'.stdout')).open('w') as stdout,(OUT/(label+'.stderr')).open('w') as stderr:
  r=subprocess.run(args,cwd=EXPORT,stdout=stdout,stderr=stderr)
 commands.append({'label':label,'args':args,'cwd':str(EXPORT),'exit_code':r.returncode,'seconds':round(time.time()-t,3),'stdout_sha256':sha(OUT/(label+'.stdout')),'stderr_sha256':sha(OUT/(label+'.stderr'))})
 (OUT/'execution.json').write_text(json.dumps({'commands':commands},indent=2)+'\n')
 print(label,r.returncode,flush=True)
 return r.returncode
pub=run([str(SDK/'bin/flutter'),'pub','get','--offline','--enforce-lockfile'],'pub')
if pub:raise SystemExit(pub)
format_code=run([str(SDK/'bin/dart'),'format','--output=none','--set-exit-if-changed',TEST],'format')
analysis=run([str(SDK/'bin/flutter'),'analyze','--no-pub','--fatal-infos',TEST],'analysis')
code=run([str(SDK/'bin/flutter'),'test','--no-pub','--reporter=json','--concurrency=1',TEST],'cases39')
ids={};done=[];errors=[];final=None
for line in (OUT/'cases39.stdout').read_text().splitlines():
 try:d=json.loads(line)
 except ValueError:continue
 if d.get('type')=='testStart':ids[d['test']['id']]=d['test']['name']
 elif d.get('type')=='testDone' and not d.get('hidden'):done.append({'name':ids.get(d['testID']),'result':d['result'],'skipped':d.get('skipped',False)})
 elif d.get('type')=='error':errors.append(d)
 elif d.get('type')=='done':final=d
changed=[n for n,d in inputs.items() if not(EXPORT/n).is_file()or sha(EXPORT/n)!=d]
sdk_after={n:sha(SDK/n) for n in sdk_paths}
live=[n for n,d in inputs.items() if n.startswith(('lib/','third_party/')) and ((not(ROOT/n).is_file())or sha(ROOT/n)!=d)]
result={'status':'pass' if code==format_code==analysis==0 and len(done)==39 and not errors and not changed and sdk_after==sdk else 'fail','commands':commands,'cases':done,'case_count':len(done),'errors':errors,'final':final,'export_drift':changed,'sdk_unchanged':sdk_after==sdk,'runtime_base':'root fullVM immutable snapshot; new peer principal changes intentionally excluded','live_runtime_drift':live,'test_sha256':sha(EXPORT/TEST),'current_owned_test_matches':sha(ROOT/TEST)==sha(EXPORT/TEST),'scope':'39 actual locked SDK/provider/production inbox cases; no whole live Admin closure'}
(OUT/'validation.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:result[k]for k in ['status','case_count','sdk_unchanged','current_owned_test_matches','live_runtime_drift']}),flush=True)
raise SystemExit(0 if result['status']=='pass' else 1)
